# Sleep, lid and battery on the M3 Pro (J516S)

Tested 2026-10-26 over SSH (`user@<m3-tailscale-ip>`) on Fedora Asahi Remix 44, KDE Plasma (Wayland), with the user at the machine for the hands-on tests.
**Kernel tested: `7.2.11-m3gpu+`** (the GPU test kernel with the PMP memory floor, booted 20:42:53 and up for the whole test). This is not the stock 7.1.13. The memory floor keeps DRAM and the fabric at a high level, so idle power on this kernel can be higher than on stock. No test was run on stock.
No kernel, boot entry, m1n1, firmware or reboot change was made. The only state change was the user unplugging and replugging the charger and closing the lid.
Asahi status column: from `docs/asahi-m3-pro-status.md` (rows "Sleep and suspend", "Lid close", "Battery life and battery info"). That file is a research summary from 2026-10-26, not a primary source.

## Results

| Feature | Test run | Result | Evidence | Asahi status |
|---|---|---|---|---|
| Suspend: kernel support | `/sys/power/mem_sleep`, `/sys/power/state`, `/sys/power/disk` | **s2idle only.** Deep sleep (`mem`/S3) is not offered | `mem_sleep` = `[s2idle]`. `state` = `freeze mem`. `disk` = `[disabled]` (no hibernate) | Conflict: docs list SoC suspend as linux-asahi, press says sleep does not work |
| Suspend and resume (via lid close) | Lid closed and opened by the user three times, 21:14:42 to 21:16:21. Kernel and logind journal read afterwards | **Works in the log. 3 suspends, 0 failures.** User report on the screen: not received yet | `/sys/power/suspend_stats`: `success` 3, `fail` 0, no failed device, no errno. Each cycle logs `PM: suspend entry (s2idle)`, `suspend devices took 0.5 to 1.0 s`, `resume devices took 0.009 to 2.0 s`, `PM: suspend exit`. No oops, no BUG, no failed units after the test | Press: no sleep |
| Long sleep and wake | Third cycle: lid closed 21:15:02, opened 21:16:21 | **Works.** Mac was unreachable for 79 s and came back by itself | 12 SSH attempts timed out (6 s each). The first attempt after the lid opened worked. `systemd-sleep`: "System returned from sleep operation 'suspend'". Same boot (`uptime -s` 20:42:53), no reboot, uptime counter continuous | Press: no sleep |
| `systemctl suspend` (planned test) | Not run | **Not tested.** The lid close already uses the same logind suspend path | Over SSH, `CanSuspend` returns `challenge` (polkit asks for admin auth), so the command needs the user at the Mac or a password | n/a |
| Wake after resume: Wi-Fi | `nmcli`, kernel log after each resume | **Works, with an error on every resume** | `wld0` stays `connected`. Each resume logs `brcmf_p2p_set_firmware: failed to update device address ret -52` and `add iface p2p-dev-wld0 type 10 failed: err=-52`. The P2P device `p2p-dev-wld0` is left `disconnected`. Also `brcmf_c_set_joinpref_default: Set join_pref error (-52)` once. Wi-Fi and SSH worked after all three resumes | n/a |
| Wake after resume: Bluetooth | `journalctl -k`, `bluetoothctl list`, `systemctl is-active bluetooth` | **Partial.** Controller timed out on 2 of 3 resumes but is still present | `Bluetooth: hci0: command 0x0c01 tx timeout` and `Opcode 0x0c01 failed: -110` after the second and third resumes. Afterwards `bluetoothctl list` shows the controller and `bluetooth.service` is active. Pairing or audio after resume was not tested | n/a |
| Wake after resume: NVMe, keyboard, trackpad, SMC | Kernel log | **Works** | `nvme-apple` re-initialises and logs `boot mode normal` after each resume. SMC logs `HID Event` on lid close and open. The MTP (touch) firmware logs "Sending Cumulus Report to enter Dependent Mode". SSH shows a healthy system (0 failed units). Keyboard and trackpad input after wake: not confirmed by the user | n/a |
| Wake after resume: display | Kernel log | **Log shows DCP warnings. Picture not confirmed.** | Third resume: `apple-dcp 28ec00000.dcp: IOMFB LACS_ERROR: DCP took too long to respond to LAS stats` (twice). eDP-1 reads `connected`. Brightness read 101 after wake. What the screen looked like on close and open: not reported by the user yet | Press: sleep blocked by missing DCP support |
| Black screen after the tests (idle screen-off, not a suspend) | 21:29: user reported a black screen. `suspend_stats`, `uptime`, `/sys/class/drm/card2-eDP-1/dpms`, `loginctl`, journal | **Panel stayed off behind the lock screen. Fixed by DPMS on. The user then saw the lock screen.** Cause of the idle screen-off: not tied to sleep | `suspend_stats` still 3 and 0, no new `PM: suspend entry`, uptime 46 min, `LockedHint=yes`, `kscreenlocker_greet` running since 21:21. `dpms` read `Off`, `actual_brightness` 0 while `brightness` 31, connector `connected`. `kscreen-doctor --dpms on` over SSH set `dpms` to `On` and the user confirmed the picture. **Open question:** whether a key press or the trackpad also wakes a panel in this state (the user did not try it before I sent DPMS on) | n/a |
| Memory pressure during the test (side finding) | Journal, 21:28:59 | **Info.** Not a sleep fault | Kernel out-of-memory report at 21:28:59: about 13 GB in use, 6.3 GB swap peak. Other sessions ran GPU and LLM tests on the same Mac. It can affect later sleep tests, so check memory first | n/a |
| Lid: logind settings | `busctl get-property` on `org.freedesktop.login1.Manager` | **Suspend on lid close** | `HandleLidSwitch` = `suspend`. `HandleLidSwitchExternalPower` = empty (follows `HandleLidSwitch`). `HandleLidSwitchDocked` = `ignore`. No drop-in files change this. `LidClosed` false after the test | Press: one outlet says the lid shuts the system down. **Not true here:** the lid suspends, it does not power off |
| Lid: close and open events | Journal during the user's test | **Works** | `systemd-logind: Lid closed.` then `The system will suspend now!` then `Lid opened.` for all three cycles. Input device `Apple SMC power/lid events` exists | Not verified in the status file |
| Lid: KDE PowerDevil | `~/.config/powerdevilrc`, journal | **Mixed. Settings are "do nothing", but logind still suspends** | `powerdevilrc` has `LidAction=0` (AC) and no battery lid action. On the first close PowerDevil logged `Lid action was suppressed because an external monitor is present`. An HDMI cable was attached and being moved at that time (see `display-hdmi.md`). logind did the suspend anyway. The test with no external display attached and the lid closed on battery was not run separately | n/a |
| Lid: first two cycles were short | Journal | **Info** | Cycle 1 lasted about 4 s (21:14:49 to 21:14:53) and cycle 2 about 4 s (21:14:55 to 21:14:59), because the lid was reopened quickly. Both suspended and resumed cleanly | n/a |
| Battery: percent, state | `upower -i`, `/sys/class/power_supply/macsmc-battery` | **Works** | 100%, `fully-charged` on AC. 12.85 V. `Discharging` at 21:13 after the unplug, with `power_now` -5.8 to -6.1 W | Battery info: linux-asahi |
| Battery: health | Same sources | **Works. Health Good.** | `energy_full` 93.05 Wh, `energy_full_design` 97.80 Wh, so 95.1% of design. `charge-cycles` 84. `health` = `Good`. Model `bq40z651`. Temperature 23.5 to 24 C | Battery info: linux-asahi |
| Battery: charge control | `charge_behaviour`, `charge_control_*_threshold` | **Present, read only in this test** | `charge_behaviour` offers `auto`, `inhibit-charge`, `force-discharge` (set: `auto`). sysfs thresholds read 100 and 100. `upower` reports 75% start and 80% end with `charge-threshold-supported: yes`. The two disagree. Writing them needs root, not tried | n/a |
| Battery: charge and discharge rate | `power_now`, `current_now`, `voltage_now`, 10 s samples | **Works for discharge. Charge rate not measured** | AC plugged and full: 0 W. Unplugged, idle desktop at brightness 26: -5.8 to -6.1 W (first sample -11.7 W while the screen was still bright). The battery was full, so a charging rate was never seen. `time_to_empty_now` returns "No data available" | Battery info: linux-asahi |
| Battery: 10-minute idle power on battery | Sampler over SSH every 10 s | **Not done.** Only 50 s of valid data | First run waited for the unplug and sampled 10 min with AC online, so it is invalid and was discarded. The second run started 21:13:20 on battery. The user wanted to test the lid first and I stopped it after 6 samples. Mean of the last 4: about 6.0 W (screen at brightness 26, CPU clusters near 2 GHz and 0.7 GHz, load 0.2). **This is not a 10-minute figure.** Memory floor was on | Battery life: not stated by any source |
| Power draw while asleep | Energy before and after the 79 s sleep | **Not measurable** | Capacity read 100% before and after, and energy_now 88.86 Wh after. 79 s is too short to show a drain | n/a |
| Charger plug and unplug | `macsmc-ac/online`, `status` | **Works** | `online` 1 on AC, 0 after the unplug. `status` changed from `Not charging` to `Discharging` within the poll | n/a |
| CPU frequency scaling | `/sys/devices/system/cpu/cpufreq/policy*` | **Works** | Driver `apple-cpufreq`, governor `schedutil`. `policy0` (cpus 0, 7 to 11): 696 to 4056 MHz. `policy1` (cpus 1 to 6): 744 to 2748 MHz. Available governors: conservative, ondemand, userspace, powersave, performance, schedutil. A `boost` control exists. Idle samples varied from 696 MHz to 3.4 GHz. Changing the governor or boost needs root and was not tried. Note: "P" and "E" cluster names were not confirmed | n/a |
| Power profiles | `powerprofilesctl`, `systemctl is-active`, `/sys/firmware/acpi/platform_profile` | **Not available as KDE's profile switch** | `powerprofilesctl` is not installed. `power-profiles-daemon` inactive, `tlp` inactive, `tuned` active (its profile was not read). No `platform_profile` and no `/sys/class/platform-profile` entry | n/a |
| Thermal sensors | `/sys/class/thermal` | **Works** | `macsmc-battery` 24 C, `macsmc_soc_die` 34 C, `apple_pmp_hotspot` 44 C at idle | n/a |
| Keyboard backlight | `/sys/class/leds` | **Device present, not tested** | `white:kbd_backlight` exists, brightness read 0 | n/a |
| Screen brightness on battery | `apple-panel-bl` | **Works, KDE dims on battery** | `brightness` was 140 on AC and 26 right after the unplug (max 500) | n/a |

## Kernel messages after resume (test kernel 7.2.11-m3gpu+)

- `brcmf_p2p_set_firmware: failed to update device address ret -52`, `brcmf_p2p_create_p2pdev: set p2p_disc error`, `brcmf_cfg80211_add_iface: add iface p2p-dev-wld0 type 10 failed: err=-52`: after every resume. Wi-Fi P2P device only.
- `Bluetooth: hci0: command 0x0c01 tx timeout`, `Opcode 0x0c01 failed: -110`: resumes 2 and 3.
- `apple-dcp 28ec00000.dcp: IOMFB LACS_ERROR: DCP took too long to respond to LAS stats`: resume 3 (also in the boot log, see `display-hdmi.md`).
- Not seen: kernel oops, BUG, hung task, failed units, NVMe errors.

## Overall answer

- **Sleep: works on this kernel in the logs.** Three s2idle suspends, 0 failures, and one 79 s sleep that came back by itself. This is better than the Asahi status file says ("no sleep"). The status file may describe the stock kernel. Not tested on stock.
- **Lid: suspends, does not power off.** This contradicts the press line in the status file.
- **Not proven:** that the screen comes back correctly (user report open), a long sleep (minutes or hours), battery drain while asleep, and what happens with no HDMI cable attached.
- **Battery reporting: works** (percent, health, cycles, voltage, power). **Idle battery life: not measured.**
- **Power profiles: none.** CPU frequency scaling works.

## Next steps

1. User: say what the screen and keyboard light did on close and on open (black on close? picture back on open? flicker? login screen or desktop?). This decides whether the sleep row becomes "Works". The only screen report so far is the black panel at 21:29 (see the table), which came from idle screen-off and not from a suspend.
1a. Find out why the panel stays black until DPMS is turned on: wait for the next screen-off, press a key and note whether it wakes. If it does not wake, the DCP or KWin DPMS path needs a fix.
2. User, at the Mac: lid close for 10 minutes with no HDMI or USB cable attached, on battery. Then read `upower` energy before and after to get the sleep drain in W.
3. User: unplug the charger and leave the desktop idle for 10 minutes, lid open, no keyboard use. I rerun the sampler (script in the session scratchpad: 10 s samples of `power_now`, `current_now`, frequency, load, brightness).
4. Repeat the idle and sleep drain tests with `pmp_report.memory_floor=0` or on stock 7.1.13 to measure what the memory floor costs. Needs the user to pick the kernel in GRUB. The GPU session owns the boot setup, so do not change the default boot.
5. User, in own Terminal tab: `sudo` test of `systemctl suspend`, and write tests for `charge_control_end_threshold` and the CPU governor (needs the sudo password).
6. Look at the Wi-Fi P2P (`-52`) and Bluetooth (`0x0c01` timeout) errors after resume: the GPU session or a driver session can check whether the firmware or the driver causes them.
7. Test a longer sleep (30 minutes), wake by keyboard and by power button, and sleep with a USB-C device attached.

## What needs the user's hands

- Be at the Mac for every sleep, lid and unplug test.
- Unplug and replug the charger.
- Close and open the lid and report what the screen, keyboard light and fans do.
- Type the sudo password in your own Terminal tab for root tests, or choose the kernel in GRUB.
- Power-button reset (hold 10 s) if a suspend ever hangs. The Mac then boots the default GPU kernel.

## Not done in this test

- `systemctl suspend` itself, hibernate, and wake by keyboard or power button.
- A 10-minute idle battery run. A complete one needs a repeat.
- Charging rate (the battery was full) and time to empty.
- Stock kernel 7.1.13 and memory-floor-off comparisons.
- A check of the Asahi status rows against the primary source.
