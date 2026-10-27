# Video encode (AVE2) and ProRes on the M3 Pro (t6030, J516S)

Research only. Written 2026-10-27. Nothing was changed on the M3 (read-only SSH checks, no sudo, no module load, no reboot).
Kernel on the M3 during the checks: `7.2.11-m3gpu+`.
All web pages below were read on 2026-10-27.

## 1. Short answer

- **Is it possible?** Probably yes for H.264 and HEVC encode. A community driver already encodes on M1, M1 Pro, M1 Max, M1 Ultra and M2. The M3 Pro has the same kind of block (`ave2`, firmware `H15S`). Nobody has ported the driver to M3.
- **Is it easy?** No. It needs four pieces, and the last two are the hard ones: a device-tree node, an m1n1 patch, a new driver row, and knowledge of the H15S firmware interface.
- **ProRes?** No public work exists. The block (`apr`) is a different design with no coprocessor firmware. Treat it as a separate research project.
- **Recommendation:** Run Stage 0 below (read-only, low cost) when the GPU session is done. Do not start Stage 2 or later until the maintenance window is over and the user gives a go. Use CPU encode (x264, x265, SVT-AV1) until then.

## 2. Status today on the M3 Pro

| Item | Status | Evidence |
|---|---|---|
| Asahi feature page, M3 Pro (T6030) | Video Decoder = `linux-asahi`. **Video Encoder = TBA. ProRes Codec = TBA.** The page defines TBA as "Active work on this feature is not being undertaken at this time" | [M3 Series Feature Support](https://asahilinux.org/docs/platform/feature-support/m3/), read 2026-10-27 |
| Asahi accelerator doc | Lists AVE (encode), ProRes (APR) and AVD (decode) as blocks. Says nothing about Linux status. Warns not to extract AVE firmware with the generic script and points to the ADT guide | [Accelerators](https://asahilinux.org/docs/hw/soc/accelerators/), read 2026-10-27 |
| Linux device tree on the M3 | **No AVE node, no AVE DART node, no `apr` node.** `/sys/firmware/devicetree/base` has `avd@30a000000` and no `ave`, `venc` or `apr` name anywhere. No IOMMU node exists at the AVE DART address | SSH read-only `find`, 2026-10-27 |
| Kernel config | `VIDEO_DEV=m`, `V4L2_MEM2MEM_DEV=m`, `VIDEO_APPLE_AVD=m`, `APPLE_DART=m`, `APPLE_RTKIT=y`, `APPLE_PMGR_PWRSTATE=y`, `APPLE_SART=m`. **No AVE option exists.** | `/proc/config.gz` over SSH |
| Loaded modules | `apple_avd` (decoder, bound, `booting hw version: 40000`), `apple_isp`, `apple_dart`, `apple_rtkit_helper`, `v4l2_mem2mem`, `videobuf2_*` | `lsmod` over SSH |
| Video nodes | `/dev/video0` = `apple-isp` (camera), `/dev/video1` = `avd`. No encoder node | `/sys/class/video4linux` |
| Firmware dir | `/lib/firmware/apple/` holds only `avd-fw-v4-t0.bin`. No AVE image | `ls` over SSH |
| Press | No report of AVE on M3 found in two web searches | searches on 2026-10-27 |

The AVD decoder work is a good sign for the method. It runs on RTKit, `apple-dart` and V4L2 mem2mem. Those three parts are the same ones the AVE driver uses.

## 3. What exists: the community AVE driver

### 3.1 Sources

- Upstream: [aquarat/apple-m-series-ave-driver](https://github.com/aquarat/apple-m-series-ave-driver), read 2026-10-27. 387 commits, 2 stars, 1 open issue. The page shows no commit date. The README says the repository is "almost entirely AI-generated" and calls the work beta.
- Fork: [henriSchulz/apple-m-series-ave-driver](https://github.com/henriSchulz/apple-m-series-ave-driver), read 2026-10-27. 321 commits. Earlier alpha state (status text dated 2026-09-24, M1 Max only). The page does not show what the fork changes. The upstream is more advanced and is the one to follow.
- M1 Pro port PR: [aquarat PR 2](https://github.com/aquarat/apple-m-series-ave-driver/pull/2), merged 2026-10-02. It is the best model for a new SoC port.
- Porting checklist: [docs/79-porting.md](https://raw.githubusercontent.com/aquarat/apple-m-series-ave-driver/main/docs/79-porting.md), read 2026-10-27.
- Firmware loading: [docs/09-firmware-load.md](https://raw.githubusercontent.com/aquarat/apple-m-series-ave-driver/main/docs/09-firmware-load.md), read 2026-10-27.
- m1n1 DAPF patch: [docs/50-m1n1-ave-dapf.md](https://raw.githubusercontent.com/aquarat/apple-m-series-ave-driver/main/docs/50-m1n1-ave-dapf.md), read 2026-10-27.
- Method: [docs/00-methodology.md](https://raw.githubusercontent.com/aquarat/apple-m-series-ave-driver/main/docs/00-methodology.md), read 2026-10-27.
- Downstream use: [opendisplay issue 360](https://github.com/peetzweg/opendisplay/issues/360), read 2026-10-27. It says only an out-of-tree alpha driver exists, no official Asahi work, and that upstreaming is "realistically not before late 2027" (that is the issue author's estimate). It says nothing about M3 encode.

### 3.2 What the upstream driver does (README of 2026-10-27)

- A V4L2 stateful mem2mem encoder. Works with `ffmpeg` (`h264_v4l2m2m`, `hevc_v4l2m2m`) and GStreamer (`v4l2h264enc`, `v4l2h265enc`). The README recommends a patched FFmpeg 8.1 (seven patches in `ffmpeg/`).
- Codecs: H.264 (High with CABAC, Main, Baseline) and HEVC (Main, Main 10). Input NV12 or P010. Sizes 192x96 to 4096x4096. P frames, IDR control, fixed QP and rate control.
- B frames and more than one reference: controls exist, but the M1 table notes hangs on t8103, so some paths are clamped.
- Speed (reported by the author): about 70 fps at 1080p and 19 fps at 4K on a stock device tree. About 170 and 48 fps with an optional PMP performance vote.
- Quality (author's numbers): about 20% more bitrate than x265 `medium` for the same VMAF with P frames only. About 25 to 75 times less energy per 1080p frame than x265 `medium`.
- Tests the author reports: `v4l2-compliance -s` 54 of 54, a two-hour run of 6055 streams with no failure.
- Not done: suspend and resume untested, 2-pass not in V4L2.
- Warning in the README: the kernel code "can hang or reset the machine".
- License: code GPL-2.0-only. No Apple firmware or kext is in the repository.

### 3.3 Supported SoCs (README table dated 2026-10-04)

| SoC | Firmware variant | State |
|---|---|---|
| t6001 M1 Max (2 encoders) | `AppleAVE2FW_H13C` | Bring-up machine |
| t6000 M1 Pro | `H13S` | Works with stock m1n1 (per README) |
| t8103 M1 | `H13G` | Mac mini works. H.264 clamped to IPPP |
| t8112 M2 | `H14G` | H.264 and HEVC tested |
| t6002 M1 Ultra (4 encoders) | `H13D` | Works |

The README says M2 Pro/Max, M3 and later are "not ported". No M3 or M4 document exists in the `docs/` listing (96 files read on 2026-10-27, the page said more may be hidden).

### 3.4 How the driver finds and starts the block

1. **Device tree.** The ADT has `/arm-io/ave0` (and `ave1` on Max and Ultra). Fedora's device tree has no encoder node, so the repository ships `test/ave-overlay.ko`, which adds a node at load time, plus `dts/apple,ave.yaml` and `dts/t6001-ave.dtsi`. The first compatible string selects a row in `driver/ave_soc.c` (for example `apple,t6000-ave`).
2. **MMIO.** Bank N is ADT `reg` index N. The coprocessor (ASC) is bank 1. The doorbell is in bank 2.
3. **IOMMU.** `dart,t6000` or `dart,t8110` with 16 KB pages, handled by `apple-dart` and the normal DMA API.
4. **Coprocessor.** The firmware runs on RTKit. The existing `apple-rtkit` code applies.
5. **Power.** `apple-pmgr-pwrstate`. An optional PMP vote raises the clock.
6. **Firmware.** iBoot loads the image into DRAM before the kernel runs. The kext, and the driver, only adopt it. The ADT node carries the properties `pre-loaded` and `segment-ranges` (two entries: TEXT and DATA). The image is mapped at DART IOVA 0, TEXT then DATA. The driver keeps a pristine copy of DATA and restores it before every start. Each SoC needs these local files: `/lib/firmware/apple/ave_<variant>.bin`, a register table `ave-13.5-dpe-<set>.bin` built from the user's own macOS 13.5 kernelcache (`tools/ave_fwgen.py`), and a pristine DATA blob. None may be redistributed.
7. **DAPF (the dangerous part).** Linux cannot write the AVE DAPF. A first write raises a fatal asynchronous SError. The fix is a patch to m1n1 stage 2 that programs the DAPF at boot (`dart-ave0`, using the live ADT). The author reports on M1 Max that iBoot's entry was already present and the patch appended nothing. A bad stage 2 can cause a black screen or a boot loop. The restore path is to put `boot.bin.pre-ave` back on the ESP from macOS or recoveryOS, and to set `M1N1_UPDATE_DISABLED=1` so package updates do not overwrite the test build. The README text says M1 Pro "works with stock m1n1", so the patch need is SoC dependent.
8. **Posted writes.** Any new MMIO write must use `ioremap_np`, because `/soc` is non-posted. A posted write gives an SError.

The method is static analysis of `AppleAVE2.kext` and the firmware. Each finding is read from disassembly or marked as inferred. This is the same kind of work the GPU session did.

## 4. The M3 facts (macOS side)

Source: macOS hardware tree dump and restore firmware folder, read only. Only structural facts are kept here. No addresses, serials or identifiers are copied.

### 4.1 AVE block

| Property | M3 Pro value | M1 Pro (from the PR and README) |
|---|---|---|
| Node | `ave@BD100000`, name `ave`, class `AppleARMIODevice`, one instance, `soc-id` `t6030` | `/arm-io/ave0`, 1 instance |
| Compatible | `ave2` | same family |
| `pre-loaded` | present, value 1 | present |
| `segment-ranges` | present, 2 entries. TEXT about 1.16 MB at IOVA 0, DATA about 1.17 MB right after it (sizes read from the property) | 2 entries |
| `reg` banks | 5 (about 4.4 MB, 8 MB, 16 KB, 31 KB, 16 MB) | not stated in what I read |
| Interrupts | **5** | 1 (README) |
| Power gates and clock gates | **10 ids** in each list | Max has a fabric domain (`afnc4_ioa`) that M1 Pro lacks. The count was not stated |
| `iommu-parent` | the AVE DART | same |

The M3 block is larger and has more wiring than the M1 family. The 5 interrupts and 10 gates suggest more sub-units than the single-interrupt M1 design. This is an inference. The driver code must be checked against it.

### 4.2 AVE DART

- Node `dart-ave@BD030000`, compatible `dart,t8110`, page size 0x4000 (16 KB), 16 stream ids, `sid` list of 3, `bypass-12` and `bypass-15` properties, `real-time`, `remap`, two DART tunable sets (`dart-tunables-instance-0` and `-1`), `smmu-clock-gating`.
- `dart,t8110` is the same DART family the driver already handles for the M2 row (`dart_t8110` flag in `ave_soc.c`, per docs/79). So the IOMMU part should be the easy part. Linux `apple-dart` on this M3 already handles many `t8110`-style DARTs (23 users on this boot, per `lsmod`).

### 4.3 Firmware

- `AppleAVE2FW_H15S.im4p`, about 1.7 MB (compressed image file). The header shows a Mach-O with `__TEXT`, `__text`, `__const`, `__cstring` and an `_rtk_mtab` section. That matches an RTKit firmware, the same kind as H13/H14.
- Variant letter `S` matches the M1 Pro (`H13S`) naming scheme: S is the Pro-class chip, not the Max or the base chip. This is a naming observation only. It does not show that the interface is the same.
- I did not decompress or disassemble it. Stage 0 does.

### 4.4 ProRes block

- Node `apr@FD000000`, compatible `apr,h0`, with its own DART node `dart-apr@FD028000`. 3 `reg` banks, 2 interrupts, 3 clock gates.
- **No `apr` firmware file** exists in the restore firmware folder and the node has no `pre-loaded` or `segment-ranges`. So it is not an RTKit coprocessor like AVE. It is probably a register-programmed engine (inference).
- Web search for a ProRes hardware driver or reverse engineering found nothing (two web searches on 2026-10-27, no useful hit). The Asahi pages list it as TBA.

## 5. Gap between the M3 Pro and the community driver

| # | Gap | Size | Notes |
|---|---|---|---|
| 1 | **Device-tree node** for `ave` (5 banks, 5 interrupts, power domains, `iommus`) and a `dart-ave` node in `t6030` files | Small to medium | The driver's overlay approach (a loadable module that adds the node) avoids a kernel rebuild. A static node needs a kernel and device-tree build, which the GPU session owns. The power domains depend on the PMGR domain map for ids `0x1a2 0x180 0x181 0xaf 0xb0 0xb1 0xb2 0xae 0x182 0x19f`. I did not map these to the Linux `t6030-pmgr` nodes. The ADT device table is needed for that. A quick id to offset guess collided with ATC domains, so it is not valid |
| 2 | **IOMMU (DART)** | Small | `dart,t8110`, 16 KB pages. Same as the M2 row. Add the node, `apple-dart` binds |
| 3 | **Firmware variant** `H15S` | **Large, main risk** | The port checklist says a new variant needs the assert line numbers, MCPU image layouts, firmware VAs and `iboot.*` sizes re-checked. New host fields can hide in changed functions. The M1 to M2 step (H13 to H14) needed work (docs/90). H13/H14 to H15 is a bigger jump, with more interrupts, so the command ABI may have changed |
| 4 | **Register tables** `ave-13.5-dpe-<set>.bin` | Medium. **Source found (section 11)** | The driver builds these from a macOS kernelcache. The kernelcache of this Mac (macOS 26.7.1) already holds the t6030 tables, so no M3 reboot is needed to get them. Open point: the kext version must match the firmware version (section 11.4) |
| 5 | **DAPF and m1n1** | Medium, **boot risk** | Unknown if stock m1n1 is enough on t6030 (as on t6000) or if a patch is needed (as on t6001). Needs a test on the M3. Any m1n1 change can stop the boot |
| 6 | **Reserved memory** | Small, but **a data-loss risk** | The firmware sits in DRAM, placed by iBoot. The Linux device tree on the M3 has `asc-firmware@...` reserved regions for other coprocessors, but none for the AVE TEXT and DATA ranges. m1n1's `dt_reserve_asc_firmware()` is not called for `ave0` (docs/09). Without a reserved region, Linux may reuse that memory. A stage must reserve both ranges. Confirm on a Linux boot whether iBoot still loads AVE and what addresses it uses (they can change per boot) |
| 7 | **PMP performance vote** | Optional | Without it the block runs at the boot clock (about 3 times slower on M1 Pro, per the numbers in PR 2). Asahi's `apple-pmp-report` matches t6000, t6020 and t8112 only. t6030 is not listed |
| 8 | **Driver row** `t6030` in `ave_soc.c` | Medium | Register bases, DART layout, DATA ownership, iBoot placement. Template: t8112 (same DART family), not t6001 |
| 9 | **User space** | Small | Patched FFmpeg exists. A VA-API shim is not in the repository. Browsers and OBS need VA-API or V4L2 |

## 6. Effort and risk (estimates, not measurements)

- **Effort for H.264 and HEVC encode on the M3 Pro:** about 2 to 6 weeks of focused work with AI help, if the H15S interface is close to H14G. Longer if the command ABI changed. The M1 Pro port (PR 2) was a modest change on top of working M1 Max code. An M3 port has no working base. Basis: PR 2 content and the size of the `docs/` tree (96 notes) that the author needed for the first SoC. This is a judgement, not a number from a source.
- **Risk to the machine:**
  - Kernel hang or reset when the driver starts (the README warns of it). A hang is recoverable by reboot.
  - A fatal SError from a wrong MMIO write (posted write, DAPF). Same recovery.
  - A bad m1n1 stage 2 can stop the boot. Recovery needs recoveryOS or macOS. The user's M3 holds the GPU kernel, so this must wait for the maintenance window and a rollback path.
  - Unreserved AVE firmware memory could corrupt kernel memory. Reserve first.
- **Risk to the data:** low if gaps 6 and 5 are done in the order below. Do not test on a fresh kernel while other sessions use the M3.
- **Legal and policy:** driver code is GPL-2.0. The firmware, kext and register tables come from the user's own macOS and must not be committed or redistributed. The repository's author states this. The code is AI-generated and needs self-review before any trust.
- **Upstream outlook:** the Asahi page says no active work. The opendisplay issue estimates upstreaming "not before late 2027". Plan for an out-of-tree module.

## 7. ProRes

- Block `apr,h0` has no firmware and no public driver, notes or reverse engineering that I found. The AVE driver does not cover it.
- Work needed: trace macOS MMIO with the m1n1 hypervisor (the method in the 39C3 talk, [media.ccc.de](https://media.ccc.de/v/39c3-asahi-linux-porting-linux-to-apple-silicon), found by search on 2026-10-27, not watched), study the kext, then write a new driver. No work plan can be made without that data.
- Effort: months, high uncertainty. Recommendation: **do not start**. Use software `prores_ks` on the CPU. Revisit only if the AVE port succeeds and the user wants ProRes specifically.

## 8. Recommendation and staged plan

**Recommendation:** a port looks possible. Start with the read-only Stage 0 now, because it costs little and it decides if the rest is worth the risk. Stages 1 to 5 each need the user's own go. Stages 2 to 5 wait until the GPU window and the maintenance window (USB4 and reboot) are finished.

| Stage | Action | Changes the M3? | Gate |
|---|---|---|---|
| 0 | **Offline facts, on the Mac.** (a) Clone the upstream driver into its own empty directory. Read `docs/79`, `docs/87`, `docs/90`, `driver/ave_soc.c`. (b) Use the driver's `tools/` on the user's own `AppleAVE2FW_H15S.im4p` and the macOS kext to list firmware symbols, and diff them against H14G. (c) Read the ADT `power-gates` ids against the ADT pmgr device table to name the 10 power domains. (d) Compare `ave` node properties with the M1 Pro and M2 nodes. Keep every output in `private-dumps/`. Write only derived facts into the repo | No | none (offline) |
| 0b | **Boot-time check on the M3, read-only.** Record, on a Linux boot, whether the live ADT still has `pre-loaded` and `segment-ranges` for `ave`, and the TEXT and DATA addresses. Use the m1n1 proxy or a boot log, not a write | No | The user's go, and only after the GPU window |
| 1 | **Reserve the firmware memory.** Add `reserved-memory` entries for the two ranges (device-tree change or m1n1 `dt_reserve_asc_firmware` for `ave`) in the next kernel build | Kernel or m1n1 build | User's go, part of a planned kernel build |
| 2 | **Overlay node, no driver start.** Load a node-only overlay for `ave` and `dart-ave`. Check that `apple-dart` binds and that the power domains name correctly. Do not start the coprocessor | Module load | User's go, one module, rollback is `rmmod` |
| 3 | **Driver bring-up on t6030.** Add the `t6030` row, build the firmware blobs from the user's macOS, start the coprocessor, wait for the firmware handshake. Stop at the first sign of a DAPF SError. If it appears, decide on the m1n1 patch (Stage 4) | Module load, hang risk | User's go for each attempt. Keep a rescue path ready |
| 4 | **m1n1 stage 2 DAPF patch, only if Stage 3 shows the SError.** Keep `boot.bin.pre-ave` and a restore script on the ESP, set `M1N1_UPDATE_DISABLED=1`, boot once | Boot chain | User's explicit go, in the maintenance window, with macOS reachable |
| 5 | **First frame, then codecs.** Encode a test ramp, then H.264, then HEVC, then Main 10. Check with `v4l2-compliance -s`. Then a VA-API shim for desktop apps | Module load | User's go |

Stop conditions: stop and report if Stage 0 shows the H15S command interface changed in a way the checklist cannot cover. Stop at Stage 3 if the handshake fails twice for unknown reasons.

Meanwhile:
- Use CPU encode. The M3 Pro has 12 cores. `libx264` and `libx265` run well. `libopenh264` also works (used in the decode tests).
- Hardware decode already works (see [audio-camera-video.md](audio-camera-video.md)).

## 9. What I did not verify

- I did not read the upstream driver source, only its README and docs through the web fetch tool (a summarising reader, so details could be lost). Stage 0 must read the real files.
- I did not decompress or disassemble the H15S image.
- I did not map the 10 power-gate ids to Linux power domains.
- I did not confirm what the live Linux boot ADT holds for `ave`. The Linux device tree on the M3 does not carry it, and the kernel does not show it.
- The effort figures are estimates.
- The statement "M3 and M4 not ported" comes from the README text. The listing of the `docs/` directory had hidden files.
- The `ProRes` search found no hits, which does not prove that nothing exists.

## 10. Sources (all read 2026-10-27)

- https://github.com/aquarat/apple-m-series-ave-driver (README)
- https://github.com/henriSchulz/apple-m-series-ave-driver (README)
- https://github.com/aquarat/apple-m-series-ave-driver/pull/2
- https://github.com/aquarat/apple-m-series-ave-driver/tree/main/docs (file list)
- https://raw.githubusercontent.com/aquarat/apple-m-series-ave-driver/main/docs/79-porting.md
- https://raw.githubusercontent.com/aquarat/apple-m-series-ave-driver/main/docs/09-firmware-load.md
- https://raw.githubusercontent.com/aquarat/apple-m-series-ave-driver/main/docs/50-m1n1-ave-dapf.md
- https://raw.githubusercontent.com/aquarat/apple-m-series-ave-driver/main/docs/00-methodology.md
- https://asahilinux.org/docs/hw/soc/accelerators/
- https://asahilinux.org/docs/platform/feature-support/m3/
- https://github.com/peetzweg/opendisplay/issues/360
- https://media.ccc.de/v/39c3-asahi-linux-porting-linux-to-apple-silicon (listed in a search, not watched)
- Local, read only: macOS hardware tree dump and restore firmware folder (kept in `private-dumps/`, not copied here), and SSH checks of the Linux device tree, kernel config and modules on the M3.

## 11. Follow-up research (2026-10-27, later the same day)

The user asked for more research before a build decision. All work below was offline on the Mac. The M3 was not touched. Extracted files stayed in a scratch folder outside the repository.

### 11.1 New sources read (2026-10-27)

- [docs/90-t8112-m2.md](https://raw.githubusercontent.com/aquarat/apple-m-series-ave-driver/main/docs/90-t8112-m2.md): the M1 to M2 port. Firmware change H13 to H14G needed new host fields, a new DART layout path and a symbol diff of the firmware. One bug (all-black output) came from a changed source-reader path.
- [docs/87-t6000-m1-pro.md](https://raw.githubusercontent.com/aquarat/apple-m-series-ave-driver/main/docs/87-t6000-m1-pro.md): the M1 Pro port took about two days of lab work (2026-09-29 to 2026-09-30). No hang or SError was reported. One unclean unload leaked DART mappings and needed a reboot.
- [driver/ave_soc.h](https://raw.githubusercontent.com/aquarat/apple-m-series-ave-driver/main/driver/ave_soc.c) (the file is named `ave_soc.h` in the fetch result): the per-SoC rows. Fields that depend on the firmware variant are `fw_name`, pristine DATA blob, `data_stkg_off`, `text_win`, the `iboot` block and the `dev` rows. A new row also needs the DART and DAPF addresses from the ADT.
- [docs/93-firmware-emulation.md](https://raw.githubusercontent.com/aquarat/apple-m-series-ave-driver/main/docs/93-firmware-emulation.md): the author runs the AVE firmware under the Unicorn emulator from a memory snapshot. This answers "what would the firmware program" questions on the host Mac, without hardware risk.
- GitHub API, 2026-10-27: upstream has 4 issues and pull requests, the last commit is 2026-10-18, and one fork exists (henriSchulz). No M3 issue, pull request or branch. A code search for `AppleAVE2FW_H15` found only [blacktop/ipsw-diffs](https://github.com/blacktop/ipsw-diffs), which lists firmware diffs for the H15 variants (H15C, H15D, H15G, H15M, H15S) between macOS builds. It is a diff log, not a driver. No other M3 encoder effort found.
- Web search 2026-10-27: nothing new. [Phoronix](https://www.phoronix.com/news/Asahi-Linux-AVD-Firmware-M3) covers decode only.

### 11.2 H15S firmware: what it shows

Analysis of the firmware image from the macOS restore folder. The Mach-O is stored uncompressed and unencrypted inside the IM4P wrapper.

- **Layout matches the device tree.** TEXT is 0x128000 bytes at IOVA 0. DATA starts at 0x128000 and is 0x12c000 bytes. These match the two `segment-ranges` entries of the live macOS tree exactly. So H15S is the image iBoot preloads on this M3 (confirmed), and the DART mapping rule of the driver (TEXT then DATA from IOVA 0) fits. For comparison, the M1 Pro (H13S) TEXT is 0xd0000 and DATA 0x128000. The M3 TEXT is about 40 percent larger.
- **Same code base.** The source paths in the image show the same `Legacy` controllers that the M1/M2 driver already drives: `CAVCController`, `CHEVCController`, `CDMAController`, `COFController`, `CMCTFController`, `CLRMEFSController`. Even file names with `_H13C` remain. The M1/M2 driver ABI is therefore a good starting model.
- **New or extra parts.** There are also `Firmware/` modules (HW engine scheduler, MCPU controller, reference manager, rate control, device capability table). The image has 1252 text symbols, so the symbol-diff method of docs/90 works.
- **Source-reader path grew.** `CDMAController::ConfigPipeRdDMA` is 0x670 bytes on H15S. The M2 doc gives 0x3e0 (H13S) and 0x4d4 (H14G). This is the function that caused the all-black bug on M2. Expect work here.
- **Device capability check.** The firmware refuses to start when its device capability lookup fails. The lookup uses DevID, DevType, ChipType, DevRevision, Arch, SVE number and group size. The driver's `dev` row must carry the right values for the M3. The kext holds the t6030 table (section 11.3).
- **RTKit.** The image reports RTKit 2784.140.9, older than the RTKit 3255.160.4 that the fork's README names for M1 Max. The RTKit protocol version may differ. Not yet checked against `apple-rtkit`.
- **No ProRes, AV1 or VP9 strings** in the AVE image. ProRes is the separate `apr` block.

### 11.3 The kext tables for t6030 exist and are readable here

This Mac runs macOS 26.7.1 (kext `AppleAVE2` 905.41.1). Its kernelcache is world-readable and holds the AVE2 kext. A scan of the decompressed kernelcache found symbol names for these table sets:

| Chip family | DPE configuration set | Other tables |
|---|---|---|
| M1 | `Acis_8101`, `Acis_8103` | CAC 8 bit, 10 bit, default |
| M2 | `Atlas_8110`, `Atlas_8112` | CAC and CAT, 8 bit, 10 bit, default |
| M1 Pro, Max, Ultra | `Castor_6000`, `Castor_6001`, `Castor_6002` | plus AXI2AF configuration |
| **M3 Pro (t6030)** | **`Janus_6030`** | CAC and CAT 8 bit, 10 bit, default; AXI2AF configuration and default; **device capability `CEntry_6030`** |
| M3 Max | `Janus_6031`, `Janus_6034` | AXI2AF configuration |

So gap 4 (register tables) and the device capability row can be built offline from a file on this Mac. The upstream tool `ave_fwgen.py` reads a macOS 13.5 kernelcache. It must be adapted to the macOS 26 layout. The driver already has a `dev[26.6]` row type, so a 26.x path exists.

### 11.4 Open point: version match

- The M3's own macOS is 15.6.1 (build 24G90). The H15S image comes from that restore folder.
- The kext in this Mac is from macOS 26.7.1. The ABI between kext and firmware changes with the macOS version (the driver has separate ABI modes for 13.5 and 26.6).
- Two safe ways: (a) take the kernelcache from the M3's own macOS 15.6.1 (needs a boot into macOS on the M3), or (b) take the H15S firmware from a macOS 26.x restore image and pair it with this Mac's kext (needs a download of one file from a restore image; the file is about 1.7 MB, the image is several GB, so a partial fetch tool is needed).
- Stage 0 must say which pair the driver supports. Mixing versions is the main way to get a wrong ABI.

### 11.5 Updated assessment

- **Risk:** lower than first thought for the offline part. The firmware code base is the same family, the table source is on hand, the DART family is known, and the layout matches the live tree.
- **Still unknown:** whether stock m1n1 is enough (DAPF), whether the live Linux boot tree still carries `pre-loaded` and `segment-ranges` for `ave`, the 10 power domains, the version match, and the changed source-reader path.
- **Effort estimate (judgement):** the M1 Pro port took two days and the M2 port a few days after it. The M3 firmware differs more. My estimate is 1 to 4 weeks with AI help for H.264 encode at first-frame quality, plus extra time for HEVC, speed votes and desktop apps. This replaces the 2 to 6 weeks in section 6.
- **No blocker found.** Nothing found so far rules out a port.

### 11.6 Updated Stage 0 (offline, no M3 access)

1. Clone upstream into its own folder under the project (GPL-2.0 source, public, small). Read `driver/ave_soc.c`, `docs/79`, `docs/90`, `docs/99`.
2. Adapt the table extractor to the macOS 26 kernelcache. Build the `Janus_6030` tables and the `CEntry_6030` row into local files in `private-dumps/` only.
3. Diff the H15S symbols against an H14G image (upstream docs give sizes and function names; a second image needs a restore image download, ask first).
4. Resolve the 10 power-gate ids through the ADT device table. Write the draft overlay for `ave` and `dart-ave`.
5. Draft the `t6030` row in a patch file. Do not load anything.
6. Run the firmware emulator on H15S with the host Mac only, if the snapshot tools allow a start from the file image (the author starts from a live snapshot, so this may not be possible).

Then stop and ask for the first go that touches the M3 (Stage 0b).
