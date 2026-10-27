# agx-linux-kit

Build, install and test native GPU acceleration for Linux on Apple silicon Macs (the Apple GPU is called AGX).

The kit builds a community kernel, m1n1 and Mesa from pinned commits, and installs them next to your distribution's own kernel in small stages that you can undo. The stock kernel stays installed and stays the default boot. The GPU kernel boots only when you select it.

## Tested machines

| Machine | Profile | Date | Result |
|---|---|---|---|
| MacBook Pro 16-inch M3 Pro (Mac15,7, J516s, chip revision B1), Fedora Asahi Remix 44 | `machines/j516s.sh` | 2026-10-26 | OpenGL 4.6, GLES 3.2, Vulkan 1.4; KDE desktop and login screen on the GPU; exact readback and stress tests pass |

Other machines need a profile in `machines/` (see `machines/README.md`). Untested profiles are welcome only with test results.

### Results on the tested machine

| Item | Result |
|---|---|
| GPU driver | Accepts the firmware after a one-entry pin (`patches/`). 18 cores. |
| OpenGL / GLES / Vulkan | 4.6 / 3.2 / 1.4.363, renderer "Apple M3 Pro (G15S B1)" |
| Vulkan compute | Exact results (`tests/vk-compute.c`). llama.cpp runs on the GPU: Llama 3.1 8B at 150 tokens/s prompt, 22.7 tokens/s generation (with the memory floor patch). Flash attention works with `patches/mesa-agx3-fmul-narrow-wait.patch` (not yet installed). |
| Memory bandwidth | 123 GB/s (P cores) and 130 GB/s (GPU) with `patches/t6030-pmp-memory-floor.patch`; about 32 GB/s without it. See `docs/performance.md`. |
| KDE desktop and login screen | KWin composites with OpenGL on the GPU |
| Render correctness | Exact pixel and integer readback tests pass |
| Shader stress, 10 min | 228 billion pixel-iterations per second, 0 wrong values in 32,621 checks |
| Native display and brightness | Work (3456x2160, `/sys/class/backlight/apple-panel-bl`) |
| Stock kernel with the GPU boot.bin | Boots normally and keeps the system Mesa |
| Default boot | GPU kernel with the memory floor (stage K, 2026-10-26); stock kernel as the GRUB fallback. First boot as default not tested yet |
| Not done yet | Desktop stress test, sleep |

Details: `docs/performance.md` and the test log `TEST-LOG.html` (build it with `python3 -I log/build-log.py`, then open it in a browser).

## Read this first

- **Unofficial.** This is not Asahi Linux code, and the Asahi project does not support it. The tested source set is the community SiliconForest fork (`iconidentify/siliconforest-*`, based on `omacom/linux-aurora`).
- **Private use.** The SiliconForest Mesa contains instruction tables derived from Apple's LLVM AGX3 encoder. Their license status is unclear. Build it for yourself; do not redistribute the binaries.
- **Firmware identity.** The M3-generation GPU driver accepts only firmware builds it knows by hash. If yours is refused, read `docs/gpu-firmware-investigation.md` before you add a pin. Never force an unknown build with the prefix override.
- **Safe kernel config.** `build/build-kernel.sh` turns off the SEP driver (it writes to xART storage shared with macOS), the user 4K page mode, livepatch and KUnit. See `docs/gpu-stack-review.md`.
- **Have a way back.** Rehearse the macOS rollback in `docs/install-plan.md` (section 3) before stage C. It needs SSH from another Mac to the target in macOS, or a keyboard at the target.

## Requirements

- A Mac with a profile in `machines/`, and Fedora Asahi Remix (KDE) installed.
- About 40 GB free in the home folder for sources and builds.
- The Mac on power, with automatic sleep turned off during builds.

## Layout

| Path | Contents |
|---|---|
| `config.sh` | Shared settings. Reads `config.local.sh` (yours, not in git) and the machine profile. |
| `machines/` | One profile per Mac: board, DTB, GPU node, GPU driver, m1n1 options. |
| `build/` | Fetch the pinned sources, install build tools, build the kernel, m1n1 and Mesa. No install. |
| `install/` | Stages A to K. Each one runs with `sudo`, checks the machine, and prints what it changed. `install/m3-installed/` holds copies of the root-owned files on the tested M3 (old `m3gpu` names). |
| `system/` | Templates for the root-owned files. The install stages fill in the machine's values. |
| `patches/` | Kernel patches, for example the J516S B1 firmware pin. |
| `tests/` | GPU tests: readback, stress, soak, desktop stress, Vulkan compute, and a Metal version for macOS. |
| `docs/` | Research, reviews, the install plan, the firmware investigation, performance. |
| `log/` | Generator and overview for `TEST-LOG.html`. |

## Steps

Run everything on the target Mac in Fedora, as your normal user, from this folder.

1. Pick the profile: `cp config.local.example.sh config.local.sh`, then set `AGX_PROFILE` and any other value you need.
2. Fetch and build. Only `build/deps.sh` asks for the sudo password.
   ```bash
   build/fetch-sources.sh
   ```
   ```bash
   build/deps.sh
   ```
   ```bash
   systemd-run --user --unit=agx-kernel build/build-kernel.sh
   ```
   ```bash
   build/build-m1n1.sh
   ```
   ```bash
   build/build-mesa.sh
   ```
   If the driver later refuses your GPU firmware, apply a pin from `patches/` with `git -C ~/agx-work/src/linux apply <patch>` and build the kernel again.
3. Install in stages. Check the output of each stage before the next one.

| Stage | Command | What it does | Reboots |
|---|---|---|---|
| A | `sudo install/stage-a.sh` | Backups, pauses automatic boot.bin rebuilds. Then rehearse the macOS rollback. | No |
| B | `sudo install/stage-b.sh` | Mesa into `/opt/mesa-agx`, test kernel as an extra GRUB entry (next boot only). | No |
| C | `sudo install/stage-c.sh` | New m1n1 with the distribution's DTBs, no new options. | Yes, stock kernel |
| D | `sudo install/stage-d.sh` | New m1n1 with the test kernel's DTBs, GPU still off. | Yes, test kernel once |
| E | `sudo install/stage-e.sh` | boot.bin with the GPU and display options. | Yes, test kernel once |
| F | `sudo install/stage-f.sh` | Replace the installed test kernel with a rebuild (for example with a pin). | No |
| G | `sudo install/stage-g.sh` | Desktop and login screen on the native Mesa, only on GPU boots. Also installs the no-password tool. | No |
| H | `sudo install/stage-h-diag.sh` | J516S only: test kernel image with firmware digest log lines. | No |
| I | `sudo install/stage-i-masked.sh` | J516S only: test kernel image that admits the firmware by UUID plus the masked digest. | No |
| J | `sudo install/stage-j-memfloor.sh` | T6030 only: test kernel image with the PMP memory floor (memory 4 times faster). | No |
| K | `sudo install/stage-k-default.sh` | J516S only: GPU kernel becomes the default boot, stock kernel stays the GRUB fallback, kernel updates keep the default. | No |

Stages H to K are copied unchanged from the tested M3. They still use its old names: `~/m3gpu`, `/usr/local/sbin/m3gpu-boot`, `/opt/mesa-m3` and `/root/m3gpu-backup`. Read each script before you run it on another machine.

4. Test (as your user):
   ```bash
   tests/build-tests.sh
   ```
   ```bash
   nohup setsid tests/soak.sh >/dev/null 2>&1 < /dev/null &
   ```
   In an SSH shell, select the native Vulkan driver before any Vulkan test. The desktop session does this for you.
   ```bash
   export VK_DRIVER_FILES=/opt/mesa-agx/share/vulkan/icd.d/asahi_icd.aarch64.json
   ```

### Boot actions without a password

`install/setup-nopasswd.sh` (also run by stage G) installs `/usr/local/sbin/agx-boot` and a sudoers rule for exactly these actions:

```bash
sudo -n /usr/local/sbin/agx-boot status
```

Other actions: `build-stageE`, `use-stock`, `use-stageC`, `use-stageD`, `use-stageE`, `test-once` (boot the test kernel once), `mesa-select`, `restart-login`, `cleanup` (removes the rule), and `sudo -n systemctl reboot`.

A GPU test boot over SSH:

```bash
sudo -n /usr/local/sbin/agx-boot use-stageE && sudo -n /usr/local/sbin/agx-boot test-once && sudo -n systemctl reboot
```

### Boot macOS once from Fedora

`sudo install/setup-macos-switch.sh` installs `asahi-bless` and `/usr/local/sbin/agx-os`, with a sudoers rule for its three subcommands. The default boot volume does not change.

```bash
sudo -n /usr/local/sbin/agx-os macos-once && sudo -n systemctl reboot
```

`agx-os status` shows the default and next boot volumes, and `agx-os clear-next` cancels `macos-once`. To return from macOS, restart it normally: Fedora stays the default. Tested on the M3 Pro on 2026-10-26 (set, read back and cleared, no reboot).

## Undo

- Boot the stock kernel: reboot without `test-once`. The default entry is the stock kernel.
- GPU options off for every kernel: `sudo -n /usr/local/sbin/agx-boot use-stageD` (or `use-stock`).
- Native Mesa off: `sudo touch /etc/agx-native-mesa.off`, then reboot.
- Fedora does not boot: the macOS rollback in `docs/install-plan.md` section 3 puts `boot.bin.stock` back.
- End of testing: `sudo -n /usr/local/sbin/agx-boot cleanup`, and remove `M1N1_UPDATE_DISABLED=1` from `/etc/sysconfig/update-m1n1`.

## Rebuild the tested M3 Pro state

These steps rebuild the state of the tested MacBook Pro 16-inch M3 Pro (J516S) on 2026-10-26, from a fresh Fedora Asahi Remix 44 (KDE) install.

1. Build with the M3's old names (see `config.local.example.sh`): work folder `~/m3gpu`, Mesa prefix `/opt/mesa-m3`, kernel `7.2.11-m3gpu+`.
2. Kernel: before `build/build-kernel.sh`, apply `patches/m3-kernel-tree-2026-10-26.patch` to the SiliconForest kernel at commit `0e1f46661376`. That one patch equals the stack `g15-j516s-b1-pin.patch`, `g15-fw-digest-diag.patch`, `g15-fw-masked-identity.patch` and `t6030-pmp-memory-floor.patch`. The installed image has sha256 `65798c91...`.
3. Mesa: SiliconForest commit `7515336`. Optional: apply `patches/mesa-agx3-fmul-narrow-wait.patch` for llama.cpp flash attention. On the M3 this fix is built but not yet installed in `/opt/mesa-m3`.
Built but not installed on the M3 (2026-10-26 21:45, staged in `~/m3gpu/out/kernel-7.2.11-m3gpu+-usb4-bt`): `CONFIG_USB4_APPLE_SOC=m` (now in `build/build-kernel.sh`) and `patches/hci-bcm4377-j516s-resume-recovery.patch`. The kernel image is the same. Only two modules differ: the new `thunderbolt_apple.ko` and a changed `hci_bcm4377.ko`.
4. Run stages A to G, then I, J and K. Stage H is a diagnostic step that stage I replaces. Stage F is only for a rebuilt kernel; stages I and J do the same for their images.
5. Optional: `sudo install/setup-macos-switch.sh` (boot macOS once without a password).
6. Test: `tests/mem-shared.sh` (expect about 120 GB/s for the P cores and 130 GB/s for the GPU) and `ane-linux/llm/stage0.sh bench`.

Only on the M3, not in this repository:

- The GPU firmware. Fedora extracts it from macOS during the Asahi install; it is not redistributable.
- The source trees and build folders in `~/m3gpu` (`src`, `build-linux`, `build-mesa`, `out`). The kernel and Mesa edits are saved here as patches.
- Backups in `/root/m3gpu-backup` (one folder per stage) and `/root/agx-backup` (stage A).
- The action log `/var/log/m3gpu/actions.log`.
- llama.cpp, the models and the results in `~/llm-work`.
- The full Apple device tree dumps (machine identifiers), kept only in a private folder on the host Mac.

## Upgrading from the first test install

The first install (2026-10-26) used the names `m3gpu-boot`, `/etc/sudoers.d/m3gpu`, `m3gpu-mesa-select` and `~/m3gpu`. `install/setup-nopasswd.sh` and stage G remove those files and install the `agx-*` ones. Keep the old work folder, kernel suffix and Mesa prefix with the commented values in `config.local.example.sh`.

## Documents

| File | Topic |
|---|---|
| `docs/whats-in-the-repo.md` | Every kernel and Mesa change, and where its patch is |
| `docs/performance.md` | Benchmarks, soak results and the comparison plan |
| `docs/gpu-firmware-investigation.md` | Why the firmware was refused, and the pin |
| `docs/upstream-report-draft.md` | Report for SiliconForest, posted as chriskearney/siliconforest-linux#20 (`docs/upstream-issue-title.txt`, `docs/upstream-issue-body.md` hold the exact posted text) |
| `docs/features/` | Feature test reports on the M3: audio, camera and video; display and HDMI. More reports follow when their tests end |
| `docs/memory-pmp-findings.md` | Why memory was slow, and the PMP memory floor fix |
| `docs/install-plan.md` | Install plan, stage results, macOS rollback |
| `docs/build-status.md` | Build notes and problems |
| `docs/gpu-stack-review.md` | Review of the SiliconForest kernel, m1n1 and Mesa |
| `docs/asahi-m3-pro-status.md` | What Asahi supports on the M3 Pro, with sources |
| `docs/feasibility.md` | How the missing parts could be finished |
| `docs/rea-plan.md` | Plan for a private reverse-engineering toolkit |
| `docs/asahi-install-findings.md` | Notes from the Fedora Asahi install |

The documents in `docs/` record the work on the tested machine. They use the names of that time (`m3gpu`, `~/m3gpu/scripts`).

## License

No license is chosen yet for the scripts and documents in this repository. The kernel, m1n1 and Mesa sources keep their own licenses.
