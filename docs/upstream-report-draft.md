# Upstream report draft: J516S GPU firmware hash cd05af6a (not posted)

Status: draft only. Nothing is posted. Target: an issue in `chriskearney/siliconforest-linux` (the kernel we run). A copy could also go to `omacom/linux-aurora`, which carries the same firmware table.

---

## Title

J516S (Mac15,7, B1): GPU firmware TEXT sha256 cd05af6a… refused on the 14.7 boot chain

## Body

On a 16-inch M3 Pro (Mac15,7, J516s, T6030), the native G15 driver refuses the GPU firmware that iBoot loads. The driver asked for this line and the boot chain:

```text
asahi-g15 292400000.gpu: unsupported GPU firmware build: TEXT 0x5c000 DATA 0x114000 GKTS 0x58e88 sha256 cd05af6a828b52e4c2fed20086d3d18a7db42e03a8fd6f8354f9f06e0a61363e; to have it supported, report this line and the macOS version of the boot chain that loaded it
```

### Boot chain and hardware

| Item | Value |
|---|---|
| Machine | `apple,j516s` (Mac15,7) |
| arm-io `chip-revision` | `<11000000>` = 0x11 (B1), read with `ioreg` in macOS |
| iBoot1 (system firmware) | iBoot-11881.140.96 (15.6) |
| iBoot2 (OS firmware) | iBoot-10151.140.19.700.2 (14.7) |
| m1n1 | stage 1 v1.6.1, stage 2 `iconidentify/siliconforest-m1n1` aca1258 |
| Kernel | `siliconforest/next` 0e1f4666, `CONFIG_SILICONFOREST_NATIVE_GPU=y` |
| m1n1 header match | "g15s build b0" (UUID dbf37c40-ead5-3760-9441-995018782955); the GPU node gets 14 8 3 |

### What we found

- The sizes and the GKTS marker equal both pinned T6030 entries. Only the TEXT digest differs.
- The existing "J516S B0 RTKit-2419.140.12" entry (`da26ecca…`) names the same UUID. So two TEXT images with the same UUID exist on J516S.
- Another J516S with B1 silicon measures the same `cd05af6a…` digest, three captures, and runs native GL and Vulkan with it: `LisaScheers/Forge`, `docs/asterion-gpu-test.md` and `packages/asterion-gpu-test-kernel/g15-firmware-qualification.patch` (commit cb671eaec9).
- Chip revision does not explain the difference between `da26ecca` and `cd05af6a`, because both known `cd05af6a` machines are B1. We do not know which machine produced `da26ecca`.

### Result with a local exact-hash pin

We added one `FirmwareBuild` entry for `apple,j516s` with this digest (no prefix override). Results on 2026-10-26:

- Firmware identity accepted, `version=0x7031100 counts=0x110209`, 18 cores (9 + 9), firmware READY, `renderD128`.
- Mesa 26.3.0-devel (iconidentify/siliconforest-mesa 7515336b3d): OpenGL 4.6 core, GLES 3.2, Vulkan 1.4.363 (Honeykrisp).
- Exact pixel readback tests pass. KWin 6.7.5 composites with OpenGL on "Apple M3 Pro (G15S B1)".
- Headless shader stress with exact integer checks: see the soak result below.

- Shader stress, 10 min: 228.04 G pixel-iterations/s, 0 wrong values in 32,621 checks.
- Idle soak, 60 min, login screen on the GPU: readback 3/3 after it, no GPU or display errors in the kernel log.
- Load soak, 60 min: 228.17 G pixel-iterations/s for the full hour, 0 wrong values in 195,843 checks, no GPU or display errors in the kernel log.

### Request

Please consider pinning this digest for `apple,j516s`, or tell us what other data would help (for example a TEXT dump diff against the `da26ecca` image).

---

## Notes for us (not part of the post)

- The draft has no serial number, account name or network address.
- Posting is outward-facing. It waits for your approval of the exact text.
