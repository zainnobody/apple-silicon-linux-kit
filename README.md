# m3-linux

Native GPU acceleration for Fedora Asahi Linux on the MacBook Pro 16-inch M3 Pro (Mac15,7, J516s, T6030).

This project builds the community SiliconForest kernel, m1n1 and Mesa, and installs them in small stages that you can undo. The stock Fedora kernel stays installed and stays the default boot. The GPU kernel boots only when you select it.

## Status (2026-10-26)

| Item | Result on our M3 Pro |
|---|---|
| GPU driver | Accepted the firmware after a one-entry pin (see `patches/`). 18 cores. |
| OpenGL / GLES / Vulkan | 4.6 / 3.2 / 1.4.363, renderer "Apple M3 Pro (G15S B1)" |
| KDE desktop and login screen | KWin composites with OpenGL on the GPU |
| Render correctness | Exact pixel and integer readback tests pass |
| Shader stress, 10 min | 228 billion pixel-iterations per second, 0 wrong values in 32,621 checks |
| Native display and brightness | Work (3456x2160, `/sys/class/backlight/apple-panel-bl`) |
| Stock kernel with the GPU boot.bin | Boots normally and keeps the system Mesa |
| Not done yet | Desktop stress test, making the GPU kernel the default boot, sleep |

The full record is in `M3-LINUX-LOG.html` (open it in a browser). `log/build-log.py` rebuilds it from the files in this repository.

## Read this first

- **Unofficial.** This is not Asahi Linux code. The kernel, m1n1 and Mesa come from the community SiliconForest project (`iconidentify/siliconforest-*`, based on `omacom/linux-aurora`). The Asahi project does not support it.
- **Private use.** The SiliconForest Mesa contains instruction tables derived from Apple's LLVM AGX3 encoder. Their license status is unclear. Build it for yourself; do not redistribute the binaries.
- **Firmware identity.** The GPU driver accepts only firmware builds it knows by hash. If yours is refused, read `docs/gpu-firmware-investigation.md` before you add a pin. Never force an unknown build with the prefix override.
- **Safe config.** `build/build-kernel.sh` turns off the SEP driver (it writes to xART storage), the user 4K page mode, livepatch and KUnit. See `docs/gpu-stack-review.md`.
- **Have a way back.** Rehearse the macOS rollback in `docs/install-plan.md` (section 3) before stage C. It needs SSH from another Mac to the M3 in macOS, or a keyboard at the M3.

## Requirements

- MacBook Pro 16-inch M3 Pro (J516s) with Fedora Asahi Remix 44 (KDE) installed. Other M3 Pro and M3 Max models need the changes in "Other machines" below.
- The OS firmware of the Linux install is 14.7 (`/proc/device-tree/chosen/asahi,os-fw-version`).
- About 40 GB free in the home folder for sources and builds.
- The machine on power, with automatic sleep turned off during builds.

## Layout

| Folder | Contents |
|---|---|
| `config.sh` | All machine-specific settings. Edit this first. |
| `build/` | Fetch the pinned sources, install build tools, build the kernel, m1n1 and Mesa. No install. |
| `install/` | Stages A to G. Each one runs with `sudo`, checks the machine, and prints what it changed. |
| `system/` | Templates for the root-owned files. The install stages fill in this machine's values. |
| `patches/` | Kernel patches, for example the J516S B1 firmware pin. |
| `tests/` | GPU tests: readback, stress, soak, desktop stress, and a Metal version for macOS. |
| `docs/` | Research, reviews, the install plan, the firmware investigation, performance. |
| `log/` | Generator and overview for `M3-LINUX-LOG.html`. |

## Steps

Run everything on the M3 in Fedora, as your normal user, from this folder.

1. Edit `config.sh` if your machine is not the J516s.
2. Fetch and build. Only `build/deps.sh` asks for the sudo password.
   ```bash
   build/fetch-sources.sh
   ```
   ```bash
   build/deps.sh
   ```
   ```bash
   systemd-run --user --unit=m3-kernel build/build-kernel.sh
   ```
   ```bash
   build/build-m1n1.sh
   ```
   ```bash
   build/build-mesa.sh
   ```
   If the driver later refuses your GPU firmware, apply a pin (see `patches/`) with `git -C ~/m3gpu/src/linux apply <patch>` and build the kernel again.
3. Install in stages. Check the output of each stage before the next one.

| Stage | Command | What it does | Reboots |
|---|---|---|---|
| A | `sudo install/stage-a.sh` | Backups, pauses automatic boot.bin rebuilds. Then rehearse the macOS rollback. | No |
| B | `sudo install/stage-b.sh` | Mesa into `/opt/mesa-m3`, test kernel as an extra GRUB entry (next boot only). | No |
| C | `sudo install/stage-c.sh` | New m1n1 with Fedora's DTBs, no new options. | Yes, Fedora kernel |
| D | `sudo install/stage-d.sh` | New m1n1 with the test kernel's DTBs, GPU still off. | Yes, test kernel once |
| E | `sudo install/stage-e.sh` | boot.bin with the GPU and display options. | Yes, test kernel once |
| F | `sudo install/stage-f.sh` | Replace the installed test kernel with a rebuild (for example with a pin). | No |
| G | `sudo install/stage-g.sh` | Desktop and login screen on the native Mesa, only on GPU boots. Also installs the no-password tool. | No |

4. Test (tests run as your user):
   ```bash
   tests/build-tests.sh
   ```
   ```bash
   nohup setsid tests/soak.sh >/dev/null 2>&1 < /dev/null &
   ```

### Boot actions without a password

`install/setup-nopasswd.sh` (also run by stage G) installs `/usr/local/sbin/m3gpu-boot` and a sudoers rule for exactly these actions:

```bash
sudo -n /usr/local/sbin/m3gpu-boot status
```

Other actions: `build-stageE`, `use-stock`, `use-stageC`, `use-stageD`, `use-stageE`, `test-once` (boot the test kernel once), `mesa-select`, `restart-login`, `cleanup` (removes the rule), and `sudo -n systemctl reboot`.

A GPU test boot from SSH:

```bash
sudo -n /usr/local/sbin/m3gpu-boot use-stageE && sudo -n /usr/local/sbin/m3gpu-boot test-once && sudo -n systemctl reboot
```

## Undo

- Boot the stock kernel: reboot without `test-once`. The default entry is the stock kernel.
- GPU options off for every kernel: `sudo -n /usr/local/sbin/m3gpu-boot use-stageD` (or `use-stock`).
- Native Mesa off: `sudo touch /etc/m3gpu-native-mesa.off`, then reboot.
- Fedora does not boot: the macOS rollback in `docs/install-plan.md` section 3 puts `boot.bin.stock` back.
- End of testing: `sudo -n /usr/local/sbin/m3gpu-boot cleanup`, remove `M1N1_UPDATE_DISABLED=1` from `/etc/sysconfig/update-m1n1`.

## Other machines

Edit `config.sh`:

- `M3_MACHINE` and `M3_DTB_NAME`: from `/proc/device-tree/compatible` (for example `apple,j514s` and `t6030-j514s.dtb` for the 14-inch M3 Pro).
- `M3_GPU_NODE`: the GPU device name in `/sys/bus/platform/devices`.
- `M3_GPU_OPTIONS`: the m1n1 options for your SoC (T6031 uses `t6031` names).
- `M3_GREETER_USER`: the login screen account (`plasmalogin` on Fedora 44 KDE, `sddm` on older releases).

The firmware pin in `patches/` is for the J516s with B1 silicon only. Your machine prints its own hash if the driver refuses it. Compare it with known captures before you pin it.

## Documents

| File | Topic |
|---|---|
| `docs/asahi-m3-pro-status.md` | What Asahi supports on the M3 Pro, with sources |
| `docs/feasibility.md` | How the missing parts could be finished |
| `docs/rea-plan.md` | Plan for a private reverse-engineering toolkit |
| `docs/gpu-stack-review.md` | Review of the SiliconForest kernel, m1n1 and Mesa |
| `docs/build-status.md` | Build notes and problems |
| `docs/install-plan.md` | Install plan, stage results, macOS rollback |
| `docs/gpu-firmware-investigation.md` | Why the firmware was refused and the pin |
| `docs/performance.md` | Benchmarks and the comparison plan |
| `docs/upstream-report-draft.md` | Draft report for SiliconForest (not posted) |
| `docs/asahi-install-findings.md` | Notes from the Fedora Asahi install |

## License

No license is chosen yet for the scripts and documents in this repository. The kernel, m1n1 and Mesa sources keep their own licenses.
