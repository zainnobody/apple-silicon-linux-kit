# What is in this repository

Every change behind the tested M3 Pro (J516S) state, and where it is. Upstream sources: SiliconForest kernel `0e1f46661376`, SiliconForest Mesa `7515336`, SiliconForest m1n1 `aca1258` (unchanged).

Last full review: 2026-10-27 22:40. Nothing is pushed to a remote. Some sessions work in an older copy of this kit and of ane-linux; their commits were merged into these copies on 2026-10-27 22:35. Feature status for each area: `docs/features/*.md` and the local board `../status/BOARD.html`.

## Kernel changes

All stage A to L kernel changes together: `patches/m3-kernel-tree-2026-10-26.patch` (applies on `0e1f46661376`; checked against the M3 tree). The later patches below apply on top of it.

| Change | Patch | Status on the M3 |
|---|---|---|
| GPU firmware pin for the J516S B1 image | `patches/g15-j516s-b1-pin.patch` | Replaced by the masked identity |
| Firmware digest log lines (`fwdiag:`) | `patches/g15-fw-digest-diag.patch` | Installed (stage H, kept in stage I) |
| Admit the GPU firmware by UUID plus the patchbay-masked digest | `patches/g15-fw-masked-identity.patch` | Installed (stage I). Reported upstream as chriskearney/siliconforest-linux#20 |
| PMP memory floor (DCS4, FAB2): memory 4 times faster | `patches/t6030-pmp-memory-floor.patch` | Installed (stage J), default boot (stage K) |
| Bluetooth resume recovery for BCM4388 on J516S | `patches/hci-bcm4377-j516s-resume-recovery.patch` | Module installed (stage L) |
| Apple USB4 host router driver as a module (`CONFIG_USB4_APPLE_SOC=m`) | `build/build-kernel.sh` (config line) | Module installed (stage L), loads at boot; Thunderbolt 20 Gb/s measured |
| GPU target utilisation parameter (`tgt_util`) | `patches/g15-perf-tgt-util.patch` | Stage N; tested, no gain at 50 |
| GPU fault recovery: drain and halt instead of a fail-stop | `patches/g15-recovery-drain-halt.patch` | Stage O, the current default boot (pinned in `tests/pre-reboot-check.sh`) |
| Fan control: set `Ftst` before a fan mode write | `patches/macsmc-hwmon-ftst-unlock.patch` | Module in `updates/`, used by the fan curve. Every new kernel build must carry it |
| Touch ID (SEP), stages 3a to 3f | `patches/touchid/` and `patches/apple-sep-sensor-probe.patch` | Test boots only, see the Touch ID section |

Kernel config: `m3-legacy/kernel/config-7.2.11-m3gpu+-installed` (installed image) and `config-7.2.11-m3gpu+-usb4` (stage L modules). The safe settings (SEP off, user 4K pages off, livepatch off, KUnit off) are set and checked by `build/build-kernel.sh`. The Touch ID test modules are built out of tree against this kernel.

## Mesa changes

| Change | Patch | Status on the M3 |
|---|---|---|
| AGX3 packer: retire a wide wait before the narrow f32 multiply (llama.cpp flash attention) | `patches/mesa-agx3-fmul-narrow-wait.patch` | Installed in `/opt/mesa-m3` (stage M, 2026-10-27) |
| AGX3 packer: allow an in-place op with a multi-slot scoreboard wait (llama.cpp Q3_K mat-vec) | `patches/mesa-agx3-inplace-multislot-wait.patch` | Installed in `/opt/mesa-m3` 2026-10-28 00:29 (q3_K 48/48, 0 GPU faults) |
| A lost context does no GPU work instead of crashing (after a GPU fault the VM refuses all binds) | `patches/mesa-asahi-lost-context-noop.patch` | Tested 2026-10-27: not effective (moves the crash), not installed; see docs/gpu-fault-2026-10-26.md |

The SiliconForest Mesa is for private use: build it yourself, do not share the binaries.

## Touch ID (Secure Enclave and fingerprint sensor)

Status 2026-10-27: enrol, match, reject and persistence across reboots work in test boots. A touch that comes after the check starts is not seen yet. Not used for any login. Full results: `docs/features/touchid.md`, "Stage 3 results".

| What | Where |
|---|---|
| Driver patches, in order: T6030 profile, 13.5 key store, sensor probe, guard level 3, polled-state trace (3d), capture re-arm (3e), re-arm settle and full restart (3f) | `patches/touchid/` (`t6030-profile`, `t6030-sepos13`, `sensor-probe`, `guard-loaded-only`, `sensor-poll-trace`, `sensor-rearm`, `sensor-rearm-settle`) |
| Test boot: build the test DTB, arm a one-time `boot.bin`, the restore unit, disarm | `tools/touchid/window/make-window-dtb.py`, `touchid-boot.sh` (`--sensor`, `--sensor-irq`, `--probe`), `restore-bootbin.sh`, `touchid-disarm.sh` |
| Load, open, enrol, verify, alarm check | `tools/touchid/window/touchid-3b.sh` (module choice: `TOUCHID_3B_MODULE=apple-sep-3X.ko`) |
| xART store backup, verify, diff, restore | `tools/touchid/window/touchid-xart.sh` |
| Sensor calibration carve and install | `tools/touchid/window/touchid-calib.sh` |
| Checks after a test boot | `tools/touchid/window/touchid-check.sh` |
| `/dev/sep-bio` client (info, list, enrol, verify, cancel) | `tools/touchid/sepbio.py` (same file in `window/`) |
| Restart-loop test for the late touch (not run yet) | `tools/touchid/window/loopverify.sh` |
| Plans and analyses | `docs/features/touchid.md`, `touchid-stage2-plan.md`, `touchid-stage3b-plan.md` |

Module hashes (sha256, first 16): 3a `194b730a6287d3f6`, 3b `1138669b8cb6f46c`, 3c `ec3308f82cf4df33`, 3d `f4c21b0ae6baad1c`, 3e `e9533dec72cace21`, 3f `d7b1e23d711bdcca`. The built modules are on the M3 in `~/window/touchid/`, with a checked copy (modules, logs, build sources) in `../private-dumps/m3-collect-2026-10-27/`.

## Feature tools (installed on the M3)

| Feature | Files | Undo |
|---|---|---|
| Fan curve with fail-safe to auto | `tools/m3-fancurve.sh`, `tools/m3-fancurve.service`, `tools/m3-fancurve-install.sh` | `m3-fancurve-install.sh --undo` |
| Wi-Fi recovery after sleep | `tools/sleep-wifi-hook.sh` | see `docs/features/sleep-lid-battery.md` |
| Clean PipeWire camera (denoise, colour fix) | `tools/camera-clean.sh` | see `docs/features/audio-camera-video.md` |
| Hardware video decode for apps (VA-API layer) | `build/build-libva-v4l2-request.sh`, `build/build-avd-fw.sh` | remove the layer from `~/.local` |
| AirDrop (OpenDrop-based), root step, notifications and UI | `build/airdrop-setup.sh`, `build/airdrop-persist.sh`, `build/airdrop-notify.sh`, `build/airdrop-ui/` | see `docs/features/airdrop.md` |
| AirPods features (LibrePods) | `build/build-librepods.sh`, `patches/librepods-m3-*.patch`, `install/librepods.service` | see `docs/features/bluetooth.md` |
| Power and fan sensor dump | `tools/adt-power-dump.sh` | read-only |

## Tests and monitors

| What | Where |
|---|---|
| Self-test, one PASS/WARN/FAIL/SKIP line per check, hourly timer | `tests/m3-selftest.sh`, `.service`, `.timer` (result `~/selftest/last.json`) |
| GPU fault watcher | `tests/gpu-fault-watch.sh`, `tests/gpu-fault-watch.service` |
| GPU readback, fragment stress, soak | `tests/gles-*.c`, `tests/soak.sh`, `tests/load-soak.sh` |
| Vulkan compute check, compute stress, GPU memory read | `tests/vk-compute.c`, `tests/vk-stress.c`, `tests/vk-bandwidth.c` |
| GPU clock and performance | `tests/gpu-clock-probe.sh`, `tests/gpu-perf-suite.sh`, `tests/gpu-pstate.py` |
| GPU fault reproduction and lost-context tests | `tests/gpu-fault-repro.sh`, `tests/fault-gate.sh`, `tests/lost-context-*`, `tests/robust-reset-test.c` |
| CPU memory read, shared limit, governor test | `tests/cpu-bw.c`, `tests/mem-shared.sh`, `tests/governor-bw-test.sh` |
| Heat guard, heat samples, heat soak | `tests/heat-guard.sh`, `tests/heat-sample.sh`, `tests/heat-soak.sh` |
| USB, Thunderbolt and camera | `tests/usb-test.sh`, `tests/tb-tcp-send.py`, `tests/tb-tcp-sink.py`, `tests/camera-test.sh` |
| AirDrop send from a Mac | `tests/airdrop-send-from-mac.swift` |
| Pre-reboot and post-boot checks | `tests/pre-reboot-check.sh`, `tests/health-check.sh` |
| Metal reference test for macOS | `tests/metal-stress.swift` |

## Boot and install

| What | Where |
|---|---|
| Build scripts (kernel, m1n1, Mesa) | `build/` |
| Install stages A to O | `install/` (H to O are M3-only, with the first test names) |
| Root-owned files on the M3 (`m3gpu-boot`, Mesa selector, sudoers) | `install/m3-installed/` |
| The exact M3 copies of the build and stage scripts, the incremental kernel builds, the kernel configs | `m3-legacy/` |
| macOS one-time boot without a password | `install/setup-macos-switch.sh` |
| Load `apple_dart` before its consumers (late IOMMU probe warning), draft with undo | `install/dart-order/` (not installed) |

## Research

| What | Where |
|---|---|
| Video encoder (AVE) on T6030: DPE table builder, DevCap and DevInfo probes, overlay and SoC drafts | `research/ave-m3/` (upstream: aquarat/apple-m-series-ave-driver at `9ab14e4`) |
| Missing drivers overview | `docs/features/missing-drivers.md` |
| GPU firmware, memory bandwidth, PMP | `docs/gpu-firmware-investigation.md`, `docs/memory-bandwidth-research.md`, `docs/memory-pmp-findings.md` |

## Other repositories in the parent folder (each with its own local history)

| Repo | What |
|---|---|
| `../ane-linux` | Neural Engine: T6030 ANE node, probe-only power test driver, LLM baseline, stage 2 window results |
| `../distro-pack` | `agx` tool: these drivers for Debian, Ubuntu, Kali, Fedora and Arch (dry runs) |
| `..` (parent) | `status/` board and compare pages, `RUNBOOK.md`, `docs/` (partition resize, reboot plan) |

## Only on the M3 (collect when it is online)

- The kernel source tree with other sessions' uncommitted changes (`~/m3gpu/src/linux`). The Touch ID build sources from `~/m3gpu/touchid-stage1/` are copied to `../private-dumps/m3-collect-2026-10-27/`.
- The VA-API layer build in `~/.local`, and the AirDrop test folder `~/omdrop-test`.

## Not in the repository

- Source trees and build folders (`~/m3gpu/src`, `build-linux`, `build-mesa`, `out`). The patches above rebuild them.
- Binaries, models and GPU firmware (the firmware comes from macOS during the Asahi install).
- Private data in `../private-dumps/`: xART backups, the sensor calibration, device tree and ADT dumps, crash and Wi-Fi logs. These hold machine identifiers and keys. Never share or push them.
