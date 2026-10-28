# SEP random source returns zeros (analysis from source and logs, 2026-10-28)

## What happens

After the enclave reports ready, the driver asks it for four entropy words (control operation 0x36, `GET_ENTROPY`, reserved tag 0xE7). If all four words are zero it returns `EIO`, waits and tries again, five times in all, and then gives up without registering a hardware random source. The log shows `hwrng: survey attempt N failed (EIO)` five times and `survey failed after 5 attempts`. `/dev/hwrng` exists, but its current source is `none`.

## What the source and logs show

- **The enclave answers.** `EIO` is the driver's own zero check in `survey_hwrng`. A lost message would give `ETIMEDOUT`, a stopped driver `ECANCELED`. The control handler also drops every message that is not of the reply type, so what arrives is a reply with tag 0xE7.
- **The driver reads only part of the reply.** The entropy word is bits 32 to 63 of the first message word. The second message word is never read. `deliver` takes the word for tag 0xE7 whatever the type and parameter fields say, so an error code in those fields would also look like "zero entropy".
- **It does not depend on the key store.** The zeros appear in the first read-only load (before any key store work) and in every later test boot, after the key store is open and the keybag exists.
- **It is not specific to this chip.** The driver's own comment says an M1-family Mac on the 13.5 key store firmware also returned four zero words.
- **Nothing breaks without it.** The kernel keeps its own random source. Touch ID result tokens come from the kernel generator (`mint_token_bytes`). Registering the all-zero source would have been harmful, because the random core credits it with the full quality value (1024). The survey exists to prevent that, and it works.

## Explanations that fit (none tested)

1. The word is in the second message word, or in other bits of the first one. The driver never looks there.
2. The operation needs a non-zero parameter on this firmware generation. The driver sends parameter 0 and data 0.
3. The enclave hands out entropy only in an early boot phase, or only to a caller with a certain policy, and returns zeros otherwise.
4. Operation 0x36 is acknowledged on this firmware but does nothing for this caller.

## What is drafted: a read-only trace

Patch `patches/touchid/sep-entropy-trace.patch` (on top of the 3f sources; module `apple-sep-3g.ko`, 3f plus this trace). The new module parameter `entropy_trace=1` logs:
- the raw message words (both) of the first eight `GET_ENTROPY` replies: `hwrng: GET_ENTROPY reply N msg0 ... msg1 ...`;
- the four words of the first survey: `hwrng: survey words ...`.

It adds no request to the enclave. The survey already runs at every load, so one load gives the data. Use: `TOUCHID_3B_MODULE=apple-sep-3g.ko TOUCHID_3B_PARAMS="entropy_trace=1" touchid-3b.sh load` (a module without the patch rejects the parameter at `insmod`). The module compiles against the running kernel with no missing symbol. It has not been loaded.

## How to read the result

| The log shows | Meaning and next step |
|---|---|
| `msg1` non-zero, differs between replies | The word is in the second message word. Fix: read the low 32 bits of `msg1`. Check the eight values are distinct and not a counter, then re-run the survey. |
| The type or parameter fields of `msg0` differ from a plain reply | The enclave sends a status code. Record it. A probe with other parameters would be the next step, only with the user present. The driver notes that control operation 0x18 wedges the endpoint, so unknown operations are not tried blindly. |
| All eight words equal and non-zero | A constant, not entropy. Leave it. |
| `msg0` data and `msg1` both zero | This firmware gives no entropy through this operation. Keep it unregistered and close the item. |

## Status

Low priority: Touch ID and the key store do not use it. No fix is claimed without the trace. The item stays open in the task list until one load with `entropy_trace=1` has been read.
