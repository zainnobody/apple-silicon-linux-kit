# Test results, November 2026

Date: 2026-11-02. Machine: MacBook Pro 16 (J516S, M3 Pro), Fedora Asahi Remix 44, KDE Plasma 6.7.5 on Wayland.
Kernel: `7.2.11-m3gpu+`. Mesa: 26.3.0-devel (git-7515336b3d) from `/opt/mesa-m3`.
All checks ran over SSH as the desktop user (`user@m3`) from a copy of the kit in `~/kit-check/`. No stage was installed, no module was loaded or built, and the machine did not reboot.
Battery was 8 to 11 % and charging for the whole run. The long runs (full selftest, health check, module build) need 30 % or more, so they are listed under "Not checked".

## Feature checks

PASS means the check gave the expected result. It does not mean more than the check shows.

| Feature | Check | Result | Evidence |
|---|---|---|---|
| Kernel | `uname -r` | PASS | `7.2.11-m3gpu+` |
| GPU, OpenGL | `glxinfo -B` | PASS | renderer `Apple M3 Pro (G15S B1)`, core profile `4.6 (Core Profile) Mesa 26.3.0-devel` |
| GPU, Vulkan | `vulkaninfo --summary` with `VK_DRIVER_FILES=/opt/mesa-m3/share/vulkan/icd.d/asahi_icd.aarch64.json` | PASS | apiVersion `1.4.363`, driver `Honeykrisp`, `Apple M3 Pro (G15S B1)` |
| Memory speed | `tests/mem-shared.sh` | PASS | CPU P cores 126.9 GB/s, E cores 65.2, all cores 117.7; GPU 134.5 GB/s |
| Built-in display | `kscreen-doctor -o` | PASS | `3456x2160@120.00`, scale 2 |
| Brightness | `/sys/class/backlight` | PASS (read only) | `apple-panel-bl 76/500`. The value reads. A change was not tried. |
| Bluetooth | `systemctl is-active bluetooth`, selftest | PASS | `active`, controller `powered`. AirPods were not tested. |
| Fans | service and sensors | PASS (idle only) | `m3-fancurve.service` active, `fan-control` `Y`, fans 0 rpm at SoC 34 C. Spin-up under heat was not tested. |
| Power key, logind | `/etc/systemd/logind.conf.d/50-m3-power-key.conf` | PASS | `HandlePowerKey=ignore`, `HandlePowerKeyLongPress=poweroff`, `PowerKeyIgnoreInhibited=yes` |
| Power key, KDE | `~/.config/powerdevilrc` | PASS (setting only) | `PowerButtonAction=32` in all three profiles. A key press was not tested. |
| Touch ID service | `systemctl is-active fprintd` | PASS | `active` |
| Touch ID guard | kernel log | PASS | `apple_sep: xART guard level 3: 10 session records exist, 2 created by Linux; the other 8 are protected` |
| Touch ID, lock screen | see next section | FAIL with the repo file, PASS with a fixed copy | see next section |
| Wi-Fi, internet | selftest | PASS | `wld0 connected`, 864.6 MBit/s, ping OK |
| Battery and charger | selftest | PASS | `Charging`, charger `online` |
| Audio devices | selftest | PASS (devices only) | 3 sinks, 2 inputs. No sound was played or recorded. |
| Hardware video decode | selftest | PASS (init only) | `v4l2_request driver initialises`. No video was decoded. |
| Thunderbolt and USB4 | selftest | PASS (module only) | `usb4-module loaded`, 5 type-C ports. No device was connected. |

## Selftest, quick mode

`tests/m3-selftest.sh --quick` (kernel name from the default, `7.2.11-m3gpu+`, no kernel or GPU name mismatch):

- 24 PASS, 0 WARN, 0 FAIL.
- SKIP: `boot.bin` and `smart` (they need `sudo -n`), `camera capture` and `gpu load` (quick mode).

## Touch ID on the lock screen

1. Lock with Meta+L, finger on the key, no mouse or key press, with the lock screen file from `distro-pack` (commit 6dc5510): FAIL. It did not unlock. The user had to press a key and type the password.
2. Cause: `LockScreenUi.qml` has two `Component.onCompleted` handlers in the same `MouseArea` (line 144 the new `startAuthenticating()`, line 204 the old `launchAnimation.start()`). QML allows one. `kscreenlocker_greet` logged `Property value set multiple times`, `Type LockScreenUi unavailable` and `falling back to built-in locker`. The built-in locker waits for a key press or mouse move. The custom design did not show either.
3. Fix tested on the installed copy only: one merged handler, `Component.onCompleted: { authenticator.startAuthenticating(); launchAnimation.start() }`. The repo file was not changed by this test.
4. Retest with the fixed copy: Meta+L at 22:28:55, finger only. It unlocked at 22:29:04 (8.3 s, which includes the time the user took to touch the key). PASS. The journal showed no QML error.

## Touch ID speed test

`speed-test.sh 3`, settle time 1000 ms, fixed copy of the lock screen:

| Try | Lock to unlock |
|---|---|
| 1 | 12.5 s (includes the time the user took to touch the key) |
| 2 | 1.0 s |
| 3 | 1.0 s |

The script waits 1 s before its first check, so 1.0 s means at or below 1 s. The finger was probably already on the key for tries 2 and 3. No STOP or alarm appeared in the kernel log. The `xART guard (loaded only)` lines only allowed rewrites of records that the enclave loaded at attach.

## Build check

NOT RUN. `build/build-apple-sep.sh` needs the battery at 30 % or more.
Installed module, read only: `/lib/modules/7.2.11-m3gpu+/updates/apple_sep.ko*`, vermagic `7.2.11-m3gpu+ SMP preempt mod_unload aarch64`. It is loaded. Nothing to compare yet.

## Not checked

- `tests/health-check.sh` and `tests/m3-selftest.sh` in normal mode (20 s GPU load, camera capture): battery below 30 %.
- `build/build-apple-sep.sh` and the vermagic comparison with a fresh build: battery below 30 %.
- `sudo /usr/local/sbin/ti-install.sh verify`: needs the sudo password, and the user did not run it.
- `tests/touchid-integration-test.sh` and the `distro-pack` `tests/run.sh` on the M3. They passed offline on the Mac (50 of 50 and 12) and were not repeated.
- A wrong finger was not tested this session.
- GPU clock drop after about 20 s of load, HDMI, USB-C displays, 4K at 60 Hz, Thunderbolt devices, USB 3 speed, SD card, internal SSD read and write test.
- AirDrop, sleep and lid close, MagSafe plug event.
- Speakers (listening), microphone recording, headphone jack, webcam capture, video decode of a real file.
- Ambient light sensor, keyboard light, trackpad, Neural Engine.
- Fan spin-up under heat. Adaptive refresh rate (the kit says it is not adaptive).
