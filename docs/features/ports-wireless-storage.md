# Ports, wireless and storage: test report

Machine: MacBook Pro 16-inch M3 Pro (J516S, Mac15,7), Fedora Asahi Remix 44, tested over SSH.
Kernel tested: `7.2.11-m3gpu+` (test kernel, one boot, booted 2026-10-26 20:42). Stock `7.1.13` was not tested.
Date: 2026-10-26. Status column source: `docs/asahi-m3-pro-status.md` (Asahi project status, Sep 2026).
Rules kept: no reboot, no kernel or boot change, nothing posted, one temporary file (deleted).

## Result table

| Feature | Test run | Result | Evidence | Asahi status |
|---|---|---|---|---|
| USB-C: controllers | `lsusb -t`, `journalctl -k`, `/sys/bus/platform` | Controllers load. Nothing plugged in yet, so no speed result. | 3 `dwc3-apple` USB controllers bound (`702280000`, `b02280000`, `f02280000`); 4 `phy-apple-atc` PHYs bound; `lsusb -t` empty. | USB 2 and 3 working (Phoronix, 6 Sep 2026) |
| USB-C: type-C ports | `/sys/class/typec` | Only `port0` is visible. The MacBook has 3 USB-C ports. | `port0`: data_role `[device]`, power_role `[sink]` (a charger or host is attached). `port0` is the DisplayPort-only HDMI path (`spmi 1-06`). The three real USB-C power-delivery controllers (`1-0c`, `1-0a`, `2-08`) stay in deferred probe, so the 3 USB-C ports have no Type-C role control. Cause found by the `m3-usbc-usb4-gap` session: `CONFIG_USB4_APPLE_SOC` is not set in the kernel config (`docs/features/usbc-usb4-gap.md`). I expect USB devices in the USB-C ports to FAIL until that is fixed. | Not stated |
| USB 3 speed | Needs a drive in each port | PENDING (needs the user) | | Working up to the hardware limit |
| USB 2 speed | Needs a device in each port | PENDING (needs the user) | | Working |
| Thunderbolt / USB4 | `boltctl list`, `/sys/bus/thunderbolt`, kernel log | FAIL: no Thunderbolt or USB4 support on this kernel. Cause: the driver `thunderbolt_apple` is not built (`CONFIG_USB4_APPLE_SOC` not set). | `boltctl list` returns nothing. No `/sys/bus/thunderbolt` devices. The 3 `cio` nodes (`701ac0000.cio`, `b01ac0000.cio`, `f01ac0000.cio`) have no driver bound. Kernel log shows `apple-display-crossbar ... T602X route -2, clocks disabled`. `phy-apple-atc 1303000000.phy: DisplayPort-only PHY`. | Thunderbolt WIP |
| Thunderbolt device | No device tested | NOT TESTED (no driver, so a device would not work) | | WIP |
| SD card slot | `lsblk`, kernel log | Reader present. Card test PENDING (needs the user). | `sdhci-pci 0000:02:00.0: SDHCI controller found [17a0:9755]`, `mmc0` registered. No card inserted. | linux-asahi |
| Wi-Fi: link | `iw dev wld0 link` | PASS | 5 GHz channel 40, 160 MHz HE, signal -48 to -53 dBm, tx 1441 to 1730 Mb/s, rx up to 2162 Mb/s. Chip BCM4388, driver `brcmfmac`. | Working |
| Wi-Fi: 10 min ping | `ping -i 1 -c 600` to gateway and to 1.1.1.1 | PASS | Gateway: 600/600 received, 0% loss, rtt 3.6 / 5.5 / 19.9 ms (min/avg/max). Internet: 600/600, 0% loss, rtt 15.4 / 19.3 / 39.1 ms. | Working |
| Wi-Fi: speed | `curl` download and upload | PASS (limited by the internet line, not shown to be limited by Wi-Fi) | Download: 18.8 MB/s from cachefly (100 MB) and 14.1 MB/s from Hetzner. About 150 Mb/s. Upload: 17.7 MB/s (141 Mb/s). LAN `iperf3` not run (no `iperf3` on the Mac host). | Working |
| Wi-Fi: log errors | `journalctl -k` | Minor | `brcmf_c_set_joinpref_default: Set join_pref error (-52)`, P2P device creation fails (`-52`). Normal Wi-Fi works. | |
| Bluetooth: controller | `bluetoothctl show`, `rfkill` | Controller is listed and powered. | `hci0` BCM4388 (`hci_bcm4377`), Powered yes, not blocked. | Working |
| Bluetooth: scan | `bluetoothctl scan on`, 3 runs of 20 to 25 s | FAIL: 0 devices found | Kernel log: `hci0: command 0x0c01 tx timeout`, `Opcode 0x202d failed: -110`, `Unable to disable Address Resolution: -110`. A power off and on did not fix it. Early in boot: `Failed to read codec capabilities (-22)` (10 times). | Working |
| Bluetooth: pairing | Needs a device in pairing mode | NOT TESTED (scan fails first) | | Working |
| Internal SSD | `fio` on one 1 GB file in `~`, then deleted | PASS | Apple SSD AP1024Z, btrfs with `compress=zstd:1`. Direct I/O: sequential read 6135 MiB/s, sequential write 2008 MiB/s with 1 job, 3.7 to 3.9 GiB/s with 4 jobs. Random 4k: read 219k IOPS (855 MiB/s), write 48.8k IOPS (191 MiB/s). Buffered write 3.0 GiB/s (1 job). No macOS number measured on this machine. | Not listed |
| Keyboard and keyboard backlight | `/proc/bus/input/devices`, `/sys/class/leds` | PASS for the keyboard and the backlight. The MacBook Pro keyboard has no backlight keys (F5 is dictation, F6 is Do Not Disturb), so the default KDE shortcuts never fire. Set from software: the light turned on and off through KDE PowerDevice (`setKeyboardBrightness`, 0 to 255). The user set the shortcuts `Ctrl+Alt+Up` and `Ctrl+Alt+Down` in `kglobalshortcutsrc` (group `org_kde_powerdevil`); both work. | `Apple MTP keyboard`, LED `white:kbd_backlight` (0 to 255, now 0). | Keyboard backlight: linux-asahi, kernel 7.3 |
| Trackpad | `/proc/bus/input/devices` | Device present. Pointer speed felt slow with the KDE default (acceleration 0, adaptive profile). Pointer speed set to 0.6 through KWin and saved in `kcminputrc`. The user says it feels much better and close to the Mac. | `Apple MTP multi-touch`. `libinput list-devices` returned no output over SSH (the test user is not in the `input` group). | linux-asahi |
| AirDrop and file sharing | Web research and read-only checks by the `m3-airdrop` session (nothing installed or tested on the M3) | NOT TESTED. Probably possible with the built-in chip. | The `m3-airdrop` session found AWDL code already in the running kernel's `brcmfmac`, so no kernel change may be needed (an earlier note in this report said a MediaTek adapter is required; that was too strong). Details and plan: `side-session-notes/local_beeadd4b-7455-462f-bd22-fa7a051ccef2/airdrop-m3.md`. Intel Unison is Windows only. Tailscale Taildrop and KDE Connect work, but the user does not want Taildrop. | Not listed |

## Update 2026-10-26 22:15 (not my own test; from the coordinator and `usbc-usb4-gap.md` section 6b)

- My USB test at 22:13 with the user's external drive showed no device. The `thunderbolt_apple` module was not loaded then.
- At 22:13:55 the USB-C session loaded `thunderbolt_apple`. All three PD controllers bound, `typec` `port1` to `port3` appeared, and a Samsung PSSD T7 Shield on `port3` (`2-08`) showed in `lsusb` on the USB 3 bus. So the earlier failure was the missing driver.
- I must rerun the USB 2, USB 3, SD and Thunderbolt tests myself after the module is loaded again. Speed tests wait until the partition backup ends.

## USB 3 test, 2026-10-26 22:56 to 23:00 (my own test, `thunderbolt_apple` loaded by the USB-C session)

Drive: Samsung PSSD T7 Shield, 3.6 TB, exFAT (53% full). Port: `port2` (PD `1-0a`, left front; `typec` shows host mode). Driver `uas`.

| Item | Result | Evidence |
|---|---|---|
| Detect and speed | PASS | `lsusb -t`: Mass Storage, Driver=uas, 10000M. `/sys/bus/usb/devices/2-1/speed` = 10000. |
| Read | PASS | fio direct, queue depth 8, 1 MiB: 902 MiB/s (a second run: 428 MiB/s). dd direct, queue depth 1: 386 MB/s. |
| Write, hardware path | PASS | `dd oflag=direct` to a new file on the drive: 518 MB/s (1 MiB blocks) and 685 MB/s (16 MiB blocks). So the port, the 10 Gb/s link and the drive write fast. |
| Write, exFAT buffered | SLOW (Linux exFAT driver, not the port) | `dd` buffered 512 MiB then `sync`: 16.8 s (about 32 MB/s). `dd conv=fsync`: 65 MB/s and 22 MB/s. `fio` direct with libaio on exFAT: 2.3 MB/s (aborted at 337 MiB). Mount: `exfat rw,...,errors=remount-ro`, not rotational, write cache on. Control on the internal SSD: 5.4 GB/s. The drive and the USB path are not the limit. The exFAT write path in this kernel is. A Linux filesystem on the drive (ext4, btrfs) should write fast, but that needs a format, so I did not test it. |
| Port left rear (`port1`) | NOT TESTED (the USB-C session uses it) | |
| Port right (`port3`) | NOT TESTED | |
| USB 2 | NOT TESTED | |
| SD card | NOT TESTED | |

Notes: the kernel log says `exFAT-fs (sda2): Volume was not properly unmounted`. The drive was already marked so when it was plugged in. Temporary files (`.fio-usb-test.bin`, `.dd-usb-test.bin`) were deleted, and the drive has none left. The user's data on the drive was not changed.

## USB hub dongle on the right port, 2026-10-27 00:14 (my own test; detection only, no speed test because the GPU benchmark runs)

Dongle: VIA Labs USB-C hub with a Realtek gigabit Ethernet port and two storage slots. Port: `port3` (PD `2-08`, right side). `typec` shows host mode.

| Item | Result | Evidence |
|---|---|---|
| Hub, USB 3 side | PASS | `lsusb -t`: Bus 002, USB 3.1 hub at 10000M. |
| Hub, USB 2 side | PASS | `lsusb -t`: Bus 001, USB 2.0 hub at 480M. |
| USB 2 flash drive | PASS (detection) | 1.9 GB NTFS flash drive, `usb-storage`, 480M. Appears as `sda`. Not mounted by me. No speed test yet. |
| Ethernet adapter | PASS (detection) | Realtek `r8152`, SuperSpeed link 5000M. No network test yet. |
| Card reader slot in the dongle | EMPTY | `sdb` shows 0B, "Media removed". No card inserted, so no result. |

The built-in MacBook SD slot (`mmc0`) is a different device and is still untested. Speed tests and the left rear port (`port1`) are still open.

## USB 2 speed on the right port, 2026-10-27 01:55 (my own test, after the combined reboot, `thunderbolt_apple` loaded at boot)

Same hub dongle on `port3` (right side). The 1.9 GB NTFS flash drive is a USB 2 device (480M).

| Item | Result | Evidence |
|---|---|---|
| USB 2 read speed | PASS | Raw read with `dd iflag=direct` (read only, drive not mounted, no data written): 29.6 MB/s over 256 MiB, 29.5 MB/s over a second 128 MiB. This is the normal limit of USB 2 (about 30 to 40 MB/s). |
| USB 2 write speed | NOT TESTED | The drive was not mounted (a user mount over SSH was refused by polkit), and I chose not to write to the user's flash drive. |
| Ethernet port of the dongle | Link DOWN | `r8152` interface present, no carrier because no cable is plugged in. Not a fault. |
| Dongle after reboot | PASS | The same devices and speeds as before the reboot. |

USB 3 speed of the T7 on `port3` (right) and `port1` (left rear) is still not measured. The T7 is not plugged in right now.

## Notes

- `lsusb -t` is empty because no USB device was plugged in during the tests. The root hubs appear only when a device attaches.
- `fio` and `iperf3` were not installed. The user installed them with `sudo dnf install -y fio iperf3` (this is a change to the system outside the report; it only adds two packages).
- The test kernel is not the default boot. Results on the stock kernel `7.1.13` may differ, most of all Bluetooth. It was not tested because a reboot needs the user's go.

## Next steps

1. USB 3 speed of the T7 on the two other ports (done once on `port2`: 722 MB/s read). Port1 waits for the USB-C session release.
2. SD card test on the built-in slot (`mmc0`) and on the dongle card reader. Waits for the user to find an SD card.
3. Thunderbolt device test. Waits for the user to plug in a device. The dock test is a separate task in `TASKS.md`.
4. USB write speed on a mounted drive. Use `dd oflag=direct`. Buffered exFAT writes are slow on Linux. This is not a hardware fault.
5. Fix the mount-point detection in `tests/usb-test.sh`. `lsblk` shows `TRAN=usb` only on the disk, not on its partitions.
6. Optional: run LAN `iperf3` to the Mac host to measure Wi-Fi without the internet line.

Closed since the first version of this report: the USB-C data fix (`thunderbolt_apple` loads at boot), the Bluetooth fix (patched `hci_bcm4377`, owned by the `m3-bluetooth` session), the keyboard backlight shortcut and the trackpad speed.

## What needs the user's hands

- Plug the T7 into the right-side USB-C port. Then into the left front port. Then into the left rear port. Say when each is in.
- Say which USB-C port you use every day.
- Find an SD card and insert it in the MacBook slot. Then in the dongle reader.
- Plug in a Thunderbolt device if you have one.

## T7 direct on a USB-C port, 2026-10-27 14:17 (my own test, read only)

The user confirmed the T7 was on the left front port. Linux showed the partner on `port2`. The port map is correct.

| Item | Result |
|---|---|
| Link | `PSSD T7 Shield`, 10000M (USB 3.2 Gen 2), driver `uas` |
| Raw read, `dd iflag=direct`, 2 GB, two runs | 722 MB/s and 734 MB/s |
| Raw read, 6.3 GB, later offset | 701 MB/s |
| Write test | Not done. The drive holds user data. |

The M3 had just booted (up 1 minute at the check). I did not cause that reboot. The T7 passes USB 3 on the left front port. The right port and the left rear port are still open.

## T7 on the second port, 2026-10-27 14:23 (my own test, read only)

The user said the T7 was on the left rear port, the one closest to MagSafe. Linux showed the partner on `port3`. This boot, `port2` is left front and `port3` is left rear. The earlier map (`port3` = right) fails. The right port needs one more test to find its number.

| Item | Result |
|---|---|
| Link | `PSSD T7 Shield`, 10000M (USB 3.2 Gen 2), driver `uas` |
| Raw read, `dd iflag=direct`, 2 GB, two runs | 699 MB/s and 660 MB/s |
| Write test | Not done. The drive holds user data. |
