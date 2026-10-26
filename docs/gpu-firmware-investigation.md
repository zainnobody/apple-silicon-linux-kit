# Why our M3 Pro GPU firmware was refused (2026-10-26)

Nothing was posted externally. Nothing on the M3 was changed during this investigation.

## Short answer

Our GPU firmware is a known, good image. The SiliconForest kernel only does not list its hash.

- Another 16-inch M3 Pro (`Mac15,7`, J516s, Lisa Scheers' "Asterion") measures the **same hash**: `cd05af6a828b52e4c2fed20086d3d18a7db42e03a8fd6f8354f9f06e0a61363e`.
- On that Mac, this image runs native GLES 3.2 and Vulkan with exact readback tests passing (24 to 25 October 2026).
- That project admits the image with a small kernel patch: one exact-hash entry, scoped to `apple,j516s`. It does not use the prefix override.
- Source: `LisaScheers/Forge`, `docs/asterion-gpu-test.md` and `packages/asterion-gpu-test-kernel/g15-firmware-qualification.patch` (commit cb671eaec9, 2026-10-25).

## What we measured on our M3

| Item | Our value | Source |
|---|---|---|
| Machine | `apple,j516s` (Mac15,7) | `/proc/device-tree/compatible` |
| iBoot1 (system firmware) | iBoot-11881.140.96 (15.6) | `/chosen/asahi,iboot1-version` |
| iBoot2 (OS firmware, the stub) | iBoot-10151.140.19.700.2 (14.7) | `/chosen/asahi,iboot2-version` |
| m1n1 stage 1 / stage 2 | v1.6.1 / aca1258 | `/chosen` |
| GPU TEXT / DATA / GKTS marker | 0x5c000 / 0x114000 / 0x58e88 | kernel log, stage E boot |
| GPU TEXT hash (8 entropy bytes zeroed) | `cd05af6a...363e` | kernel log, stage E boot |
| GPU node firmware-version / compat / abi | 14 8 3 (all three) | `/proc/device-tree/soc/gpu@292400000` |
| Chip revision | 0x11 = B1 (`chip-revision = <11000000>`, little-endian) | macOS `ioreg -p IODeviceTree -n arm-io`, 2026-10-26 |

## Item by item

### 1. Stub version: not the cause

- Our stub is iBoot-10151.140.19.700.2. This is the exact string in the kernel's supported entry "macOS 14.7-14.8.x stub firmware (iBoot-10151.140.19.700.2)".
- m1n1 notes that iBoot reports the 14.8.3 GPU image as "14.7". So "os-fw 14.7" is the expected value.
- Asterion also uses a "14.7 boot chain".

### 2. The 14.8.3 DTB values: correct, and set by m1n1

- The DTB file has `apple,firmware-version = <0 0 0>` (`arch/arm64/boot/dts/apple/t6030-gpu.dtsi:112-114`).
- m1n1 (`src/kboot_gpu.c:2220-2229, 2376-2380`) writes 14 8 3 only after it identifies the loaded image header.
- m1n1 matches the whole header (UUID, patchbay offset and size, TEXT size) against a table in `src/firmware.c:331-338`. For T6030 the table has two images: "g15s build a0" (UUID `0cbb17af-...`) and "g15s build b0" (UUID `dbf37c40-ead5-3760-9441-995018782955`).
- Our node shows 14 8 3, so our header matched one of these two.
- Our TEXT hash equals Asterion's, and Asterion records UUID `dbf37c40-...`. A SHA-256 match means identical bytes, so our image is also "build b0".

### 3. Why the hash differs from the two pinned hashes

The kernel (`drivers/gpu/drm/asahi-m3/g15/hw.rs`, SiliconForest 0e1f4666 and still at 65cd54ba, 2026-10-22) lists:

| Entry | Hash | Scope |
|---|---|---|
| macOS 14.7-14.8.x stub firmware | `11e49f75...` | any T6030 |
| J516S B0 RTKit-2419.140.12 | `da26ecca...` | `apple,j516s` only; comment names UUID `dbf37c40-...` |
| (ours, and Asterion's) | `cd05af6a...` | not listed |

- The B0 entry and our image have the same UUID, sizes and marker, but different TEXT bytes.
- The kernel zeroes only the 8 entropy bytes after the GKTS marker. iBoot writes the patchbay at 0x58e88 (0x1e8 bytes). Any other per-machine value written there changes the hash.
- Asterion states its two captures differ only in the entropy bytes. So the hash is stable on one Mac, and two J516s Macs (theirs and ours) agree.
- **Likely cause (not proven):** the `da26ecca` pin came from a J516s with a different chip revision or iBoot state. Asterion's doc names its chip "G15S B1". If ours is also B1, the "B0" entry came from B0 silicon, and iBoot writes revision-specific values into TEXT.

### 4. Chip revision

- The driver expects `gpu_revision 0x11` and `hw_ids 0x07031100 / 0x00110209` (`hw.rs`). It checks these only after the firmware identity passes, so our boot did not reach that check.
- Linux has no `soc0` device here, and the ADT is not exposed. m1n1 prints `arm-io chip-revision` only on its serial console.
- macOS can show it read-only: `ioreg -p IODeviceTree -n arm-io -r | grep -i chip-revision`.
- **Result (2026-10-26):** our arm-io `chip-revision` is `<11000000>`, which is 0x11 (B1). This equals the driver's `gpu_revision: 0x11`, so the later hardware check should pass.
- Asterion is also B1. So chip revision does not explain our difference from the `da26ecca` pin. The B0/B1 explanation in section 3 is rejected. "b0" in "g15s build b0" names the firmware build, not the silicon.
- The source Mac of `da26ecca` stays unknown. Two B1 J516s Macs with the same boot chain measure `cd05af6a`.

## Upstream status (checked 2026-10-26)

- GitHub code search finds `cd05af6a` only in the Asterion docs. No issue or PR in `omacom/linux-aurora` or `chriskearney/siliconforest-linux` reports it.
- linux-aurora PR 202 (merged 2026-10-24) fixed M3 Pro GPU startup on a J514S. It does not add firmware pins.
- `iconidentify/siliconforest-m1n1` has issues turned off.

## Options

- **A. Local exact-hash pin (recommended).** Add one `FirmwareBuild` entry to our private kernel: name "J516S g15s b0 (14.7 boot chain)", `machine: apple,j516s`, same sizes and marker, hash `cd05af6a...`. This is the same change Asterion made and tested. Cost: one kernel rebuild (the driver is built in) and stage E again. Residual risk: our driver tree is SiliconForest, theirs is linux-aurora b6f070c9. The Asterion patch context shows the same `da26ecca` B0 entry, so both trees carry the same firmware table. Asterion's reverse engineering also confirms the same InitData magic `0x0c08e21e83800490`.
- **B. Prefix override `g15_accept_text_prefix=cd05af6a828b52e4`.** No rebuild. Not recommended: the driver then returns no build object (`identity.rs`, `Verdict::Admitted`), so build-specific settings are not selected.
- **C. Wait for upstream.** Send the refusal line and our boot chain to SiliconForest or linux-aurora, with the Asterion reference. Only after you approve the text.
- **D. Read the chip revision (optional, read-only).** Next time macOS runs, read `chip-revision` with `ioreg`. This confirms or rejects the B0/B1 explanation. It does not block option A.

## Option A progress (2026-10-26)

- Patch: `patches/g15-j516s-b1-pin.patch`, applied on the M3 to `~/m3gpu/src/linux` (0e1f4666).
- Rebuild finished 13:02 with no errors. New image sha `a503543e...0b85`; it contains the entry name and the 32 hash bytes once each.
- The J516s DTB is unchanged (`18baac96...`), so `boot.bin.stageE` stays valid.
- Next: `stage-f.sh` (sudo, once) backs up and replaces the installed test kernel. Then `use-stageE`, `test-once` and reboot through the no-password rule.

## Stage F result (2026-10-26 13:06)

- Kernel log: "GPU firmware build: J516S g15s b0 on B1 silicon", "firmware identity accepted", hardware `version=0x7031100 counts=0x110209`, 18 cores, firmware READY, `[drm] Initialized asahi` and `renderD128`.
- With /opt/mesa-m3: OpenGL 4.6 core, GLES 3.2, Vulkan 1.4.363 (Honeykrisp), renderer "Apple M3 Pro (G15S B1)".
- `tests/gles-readback.c`: 3 of 3 runs passed, 0 of 4096 pixels wrong.
- Open problem: KWin uses system Mesa 26.2.5. Its submits fail (EINVAL / EOPNOTSUPP), so the desktop is not accelerated.
- `boot.bin` set back to stageD at 13:08.
