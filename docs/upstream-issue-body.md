On a 16-inch M3 Pro (Mac15,7, J516s, T6030), the native G15 driver refused the GPU firmware that iBoot loads. The driver printed:

```text
asahi-g15 292400000.gpu: unsupported GPU firmware build: TEXT 0x5c000 DATA 0x114000 GKTS 0x58e88 sha256 cd05af6a828b52e4c2fed20086d3d18a7db42e03a8fd6f8354f9f06e0a61363e; to have it supported, report this line and the macOS version of the boot chain that loaded it
```

The same UUID (dbf37c40-ead5-3760-9441-995018782955), sizes and marker are already pinned for `apple,j516s` with a different digest (`da26ecca…`, commit 19cebe3632). We found why two images with one UUID differ, and we tested a fix.

### Boot chain and hardware

| Item | Value |
|---|---|
| Machine | `apple,j516s` (Mac15,7), 18 GB RAM |
| arm-io `chip-revision` | `<11000000>` = 0x11 (B1), read with `ioreg` in macOS |
| iBoot1 (system firmware) | iBoot-11881.140.96 (15.6) |
| iBoot2 (OS firmware) | iBoot-10151.140.19.700.2 (14.7) |
| m1n1 | stage 1 v1.6.1, stage 2 `iconidentify/siliconforest-m1n1` aca1258 |
| Kernel | `siliconforest/next` 0e1f4666, `CONFIG_SILICONFOREST_NATIVE_GPU=y` |
| m1n1 header match | "g15s build b0" (UUID dbf37c40-ead5-3760-9441-995018782955); the GPU node gets 14 8 3 |

### Why the digest depends on the machine

The image-info header at TEXT+0x4200 names a patchbay at 0x58e88, 0x1e8 bytes long (m1n1 `src/firmware.c`: `0x58e88, 0x1e8, 0x5c000`). The GKTS marker is its first slot. We logged and decoded the whole patchbay on our machine. It is a list of tagged slots (tag, size, value). Four slots hold physical addresses that equal the UAT regions in our device tree:

| Slot | Value | Device tree |
|---|---|---|
| `PTPB` | `0x1047ff78000` | `/reserved-memory/uat-pagetables` base |
| `PplB` | `0x1047ff70000` | `uat-handoff` base |
| `Gx2S` | `0x1047ff74000` | `uat-pagetables-l2` base |
| `GptB` | `0x1047ffb8000` | `uat-ttbs` base |

Slot `PTPS` (`0x40000`) equals the `uat-pagetables` size. Slots `SOC_` and `SOCR` hold `0x6030` and `0x11`. iBoot places these four regions directly below the top of DRAM (ours end at `0x1047ffbc000`, the 18 GiB boundary is `0x10480000000`). So the hashed TEXT contains the end of DRAM. The J516S ships in more than one RAM size. We infer that the `da26ecca` machine has another RAM size or carveout layout. This is an inference: we have no capture from that machine. Hashing only the 8 entropy bytes, as the driver does now, cannot be stable across RAM sizes.

Digests measured on our machine (the driver logged them with a small private patch):

| Digest | Value |
|---|---|
| full, 8 entropy bytes zeroed (the current rule) | `cd05af6a828b52e4c2fed20086d3d18a7db42e03a8fd6f8354f9f06e0a61363e` |
| whole patchbay zeroed | `6ad4ba484e9a784d7783205f66618933732f84c00e18a5f783182908e5284092` |
| TEXT[0 .. 0x58e88) only | `26c0909f4efb6a41ab08178aabd2d0a61bf6aace5a85ac68ad0635d72dc2fd6f` |

Another J516S with B1 silicon measures the same full digest `cd05af6a…` (three captures; `LisaScheers/Forge`, `docs/asterion-gpu-test.md`, commit cb671eaec9). The chip revision does not explain the difference, because both `cd05af6a` machines are B1.

### Proposal and test

Admit a build by image UUID, segment sizes, marker, board and a digest of TEXT with the whole patchbay `[off, off+size)` zeroed, where `off` and `size` come from the validated image-info header. An unknown build has another UUID or other code bytes, so it is still refused. The rule needs no new pin for each RAM size.

We implemented it as a private patch (`FirmwareBuild` gets an optional `masked` identity; `identity/lookup.rs` gets `image_info()` and `masked_verdict()`) and tested it:

- Host tests (rustc, the existing `identity/lookup.rs` harness): a change inside the patchbay is admitted; a change at five positions outside it is refused (offset 0x100, 0x3fff, just before and just after the patchbay, last byte of TEXT); a wrong UUID, machine, size or marker is refused; a malformed header or a marker outside the patchbay is refused. 17 tests pass.
- Hardware, 2026-10-26: with only the UUID and the masked digest `6ad4ba48…` pinned for `apple,j516s` (no full digest), the driver logs `GPU firmware build: J516S g15s b0 (UUID dbf37c40, patchbay masked)` and `firmware identity accepted`. Then `version=0x7031100 counts=0x110209`, firmware at READY, `renderD128`, and a Vulkan compute readback with 0 wrong values.

Earlier results with a plain exact-hash pin of `cd05af6a…` on the same machine:

- Firmware identity accepted, 18 cores (9 + 9), firmware READY, `renderD128`.
- Mesa 26.3.0-devel (iconidentify/siliconforest-mesa 7515336b3d): OpenGL 4.6 core, GLES 3.2, Vulkan 1.4.363 (Honeykrisp).
- Exact pixel readback tests pass. KWin 6.7.5 composites with OpenGL on "Apple M3 Pro (G15S B1)".
- Shader stress, 10 min: 228.04 G pixel-iterations/s, 0 wrong values in 32,621 checks.
- Idle soak, 60 min, login screen on the GPU: readback 3/3 after it, no GPU or display errors in the kernel log.
- Load soak, 60 min: 228.17 G pixel-iterations/s for the full hour, 0 wrong values in 195,843 checks, no GPU or display errors in the kernel log.

### Request

1. Please consider the UUID plus patchbay-masked rule, or at least pin `cd05af6a…` for `apple,j516s` as a second digest under the same UUID.
2. If the `da26ecca` machine can log the whole-patchbay-zeroed digest, it should equal `6ad4ba48…` if our reading is right. That would confirm the cause. If it differs, the difference is outside the patchbay, and we want to know where.
3. We can share the patch and the 0x1e8-byte patchbay decode.

Related: `malik-na/linux-aurora#76` asks the same question for a J516C ("decide whether the pin should hash only the invariant part").
