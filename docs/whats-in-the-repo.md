# What is in this repository

Every change behind the tested M3 Pro (J516S) state, and where it is. Upstream sources: SiliconForest kernel `0e1f46661376`, SiliconForest Mesa `7515336`, SiliconForest m1n1 `aca1258` (unchanged).

## Kernel changes

All kernel changes together: `patches/m3-kernel-tree-2026-10-26.patch` (applies on `0e1f46661376`; checked against the M3 tree).

| Change | Patch | Status on the M3 |
|---|---|---|
| GPU firmware pin for the J516S B1 image | `patches/g15-j516s-b1-pin.patch` | Replaced by the masked identity |
| Firmware digest log lines (`fwdiag:`) | `patches/g15-fw-digest-diag.patch` | Installed (stage H, kept in stage I) |
| Admit the GPU firmware by UUID plus the patchbay-masked digest | `patches/g15-fw-masked-identity.patch` | Installed (stage I). Reported upstream as chriskearney/siliconforest-linux#20 |
| PMP memory floor (DCS4, FAB2): memory 4 times faster | `patches/t6030-pmp-memory-floor.patch` | Installed (stage J), default boot (stage K) |
| Bluetooth resume recovery for BCM4388 on J516S | `patches/hci-bcm4377-j516s-resume-recovery.patch` | Module installed (stage L), resume test open |
| Apple USB4 host router driver as a module (`CONFIG_USB4_APPLE_SOC=m`) | `build/build-kernel.sh` (config line) | Module installed (stage L), automatic load blocked, not loaded yet |

Kernel config: `m3-legacy/kernel/config-7.2.11-m3gpu+-installed` (installed image) and `config-7.2.11-m3gpu+-usb4` (stage L modules). The safe settings (SEP off, user 4K pages off, livepatch off, KUnit off) are set and checked by `build/build-kernel.sh`.

## Mesa changes

| Change | Patch | Status on the M3 |
|---|---|---|
| AGX3 packer: retire a wide wait before the narrow f32 multiply (llama.cpp flash attention) | `patches/mesa-agx3-fmul-narrow-wait.patch` | Installed in `/opt/mesa-m3` (stage M, 2026-10-27) |
| A lost context does no GPU work instead of crashing (after a GPU fault the VM refuses all binds) | `patches/mesa-asahi-lost-context-noop.patch` | Tested 2026-10-27: not effective (moves the crash), not installed; see docs/gpu-fault-2026-10-26.md |

The SiliconForest Mesa is for private use: build it yourself, do not share the binaries.

## Boot and install

| What | Where |
|---|---|
| Build scripts (kernel, m1n1, Mesa) | `build/` |
| Install stages A to L | `install/` (H to L are M3-only, with the first test names) |
| Root-owned files on the M3 (`m3gpu-boot`, Mesa selector, sudoers) | `install/m3-installed/` |
| The exact M3 copies of the build and stage scripts, the incremental kernel builds, the kernel configs | `m3-legacy/` |
| macOS one-time boot without a password | `install/setup-macos-switch.sh` |

## Other components (from the feature sessions)

| What | Where |
|---|---|
| Apple video decoder (AVD) firmware build | `build/build-avd-fw.sh` |
| LibrePods (AirPods features) build and two patches | `build/build-librepods.sh`, `patches/librepods-m3-*.patch` |
| AirDrop setup | `build/airdrop-setup.sh` |

## Tests

| What | Where |
|---|---|
| GPU readback, fragment stress, soak | `tests/gles-*.c`, `tests/soak.sh`, `tests/load-soak.sh` |
| Vulkan compute check, compute stress, GPU memory read | `tests/vk-compute.c`, `tests/vk-stress.c`, `tests/vk-bandwidth.c` |
| CPU memory read, shared limit, governor test | `tests/cpu-bw.c`, `tests/mem-shared.sh`, `tests/governor-bw-test.sh` |
| Pre-reboot and post-boot checks | `tests/pre-reboot-check.sh`, `tests/health-check.sh` |
| Metal reference test for macOS | `tests/metal-stress.swift` |

## Not in the repository

- Source trees and build folders (`~/m3gpu/src`, `build-linux`, `build-mesa`, `out`). The patches above rebuild them.
- Binaries, models and GPU firmware (the firmware comes from macOS during the Asahi install).
- Backups (`/root/m3gpu-backup`), logs and the full Apple device tree dumps (machine identifiers, kept private).
