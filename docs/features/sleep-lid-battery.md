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
| **BUG: suspend refused with a USB-C display attached, Wi-Fi does not recover** | Not run by me. Found in the logs the GPU session saved at `~/Documents/M3-Pro-Asahi-Linux/private-dumps/wifi-drop-2026-10-27/` (kernel, NetworkManager and wpa_supplicant, 00:30 to 00:42) | **Fails.** A suspend request while a USB-C display is attached is refused by the DCP. Wi-Fi does not come back on its own after the refused suspend | 2026-10-27 00:38:59: logind "Suspend key pressed short", NetworkManager "sleep requested", state `DISABLED (ASLEEP)`, `wld0` deactivated. 00:39:00, two tries in the same second: `apple-dcp 2d6c00000.dcp: refusing system sleep: a USB-C display is attached`, `PM: device_prepare(): genpd_prepare returns -16`, `PM: Some devices failed to suspend, or early wake event detected`. systemd-sleep: "Failed to put system to sleep. System resumed again: Device or resource busy". Then NetworkManager "sleep: wake requested" at 00:39:00.85 and the state went to `CONNECTED_LOCAL`, but Wi-Fi never associated: `brcmf_cfg80211_add_iface: iface validation failed: err=-16`, `wpa_supplicant: Failed to create interface p2p-dev-wld0: -16`, `brcmf_c_set_joinpref_default: Set join_pref error (-52)`, "association took too long", `wld0` failed with reason `no-secrets` (00:40:29). USB devices on the display or dock disconnected at 00:40:02. The GPU session reports Wi-Fi and Tailscale down until 01:04:50 (about 26 min). **That recovery time is not in the saved log window** (it ends 00:42), so I could not check it | Press: no sleep. Not listed |
| Repeated key-wake suspend cycles (2026-10-27) | Run by the GPU session with `~/suspend-cycle.sh` on the M3, after the combined reboot. **Relayed to me by the coordinator. I did not run it or read its log.** Three s2idle cycles at 01:15, 01:21 and 01:27, woken by a key press | **Works. 3 of 3 passed.** Whether a USB-C display was attached was not stated | `suspend_stats` `success` went 1 to 3. Wi-Fi came back after each cycle. `brcmf` P2P device add failed with `-52` after each resume (same error as in the lid test, cosmetic so far) | n/a |
| Wake after resume: Wi-Fi | `nmcli`, kernel log after each resume | **Works, with an error on every resume** | `wld0` stays `connected`. Each resume logs `brcmf_p2p_set_firmware: failed to update device address ret -52` and `add iface p2p-dev-wld0 type 10 failed: err=-52`. The P2P device `p2p-dev-wld0` is left `disconnected`. Also `brcmf_c_set_joinpref_default: Set join_pref error (-52)` once. Wi-Fi and SSH worked after all three resumes | n/a |
| Wake after resume: Bluetooth | `journalctl -k`, `bluetoothctl list`, `systemctl is-active bluetooth` | **Partial.** Controller timed out on 2 of 3 resumes but is still present | `Bluetooth: hci0: command 0x0c01 tx timeout` and `Opcode 0x0c01 failed: -110` after the second and third resumes. Afterwards `bluetoothctl list` shows the controller and `bluetooth.service` is active. Pairing or audio after resume was not tested | n/a |
| Wake after resume: NVMe, keyboard, trackpad, SMC | Kernel log | **Works** | `nvme-apple` re-initialises and logs `boot mode normal` after each resume. SMC logs `HID Event` on lid close and open. The MTP (touch) firmware logs "Sending Cumulus Report to enter Dependent Mode". SSH shows a healthy system (0 failed units). Keyboard and trackpad input after wake: not confirmed by the user | n/a |
| Wake after resume: display | Kernel log | **Log shows DCP warnings. Picture not confirmed.** | Third resume: `apple-dcp 28ec00000.dcp: IOMFB LACS_ERROR: DCP took too long to respond to LAS stats` (twice). eDP-1 reads `connected`. Brightness read 101 after wake. What the screen looked like on close and open: not reported by the user yet | Press: sleep blocked by missing DCP support |
| Black screen after the tests (idle screen-off, not a suspend) | 21:29: user reported a black screen. `suspend_stats`, `uptime`, `/sys/class/drm/card2-eDP-1/dpms`, `loginctl`, journal | **Panel stayed off behind the lock screen. Fixed by DPMS on. The user then saw the lock screen.** Cause of the idle screen-off: not tied to sleep | `suspend_stats` still 3 and 0, no new `PM: suspend entry`, uptime 46 min, `LockedHint=yes`, `kscreenlocker_greet` running since 21:21. `dpms` read `Off`, `actual_brightness` 0 while `brightness` 31, connector `connected`. `kscreen-doctor --dpms on` over SSH set `dpms` to `On` and the user confirmed the picture. **Later user report (relayed by the coordinator, 2026-10-27, not measured by me):** after 10 minutes idle the screen goes black, and a mouse move brings it back, so DPMS blank and wake work. The 21:29 case is still unexplained: the user did not try input before I sent DPMS on, and the panel may have been blank behind the lock screen (the locker ran from 21:21). Test (5) is still to be run once with a log of the idle time and the wake input | n/a |
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

## Bug: failed suspend with a USB-C display attached (found 2026-10-27 00:38:59)

What the saved logs show, in order (kernel `7.2.11-m3gpu+` family, the build with the display stack):

1. The suspend key was pressed. logind started a suspend. NetworkManager went to `ASLEEP` and dropped Wi-Fi.
2. The DCP of the USB-C display controller (`2d6c00000.dcp`, which is `dcpext1`) refused: "refusing system sleep: a USB-C display is attached". The PM core got `-16` (`-EBUSY`) from `genpd_prepare` and stopped the suspend. This happened twice in the same second.
3. The system stayed up. NetworkManager did get its wake request 0.85 s later, so it was **not** stuck in `ASLEEP` in the saved window. It went to `CONNECTED_LOCAL`, then Wi-Fi failed to associate for the next two minutes of the saved log.
4. The Broadcom driver logged `err=-16` (device busy) when it re-created the P2P interface, and `-52` on the join preferences. This looks like the Wi-Fi firmware was left in a bad state by the aborted suspend. This is my reading, not proven.

Why the DCP returns `-16`: the message is a deliberate guard in the driver ("refusing system sleep: a USB-C display is attached"), not a hardware fault. I could not read the source, because it is in the kernel tree on the M3 and I was told to run nothing on the M3. The likely reason is that a display tunnel through the USB-C port cannot be restored after sleep (`usbc-usb4-gap.md` explains the missing Thunderbolt/USB4 support). Check the guard in `drivers/gpu/drm/apple/` or the T6030 display patch to confirm. With only the HDMI port or the built-in panel (see the three clean suspends above) the guard did not trigger.

Fix proposals, most useful first:

1. **Make the refusal harmless (systemd-sleep hook).** Written as `tools/sleep-wifi-hook.sh`, **not installed**. It installs one file, `/usr/lib/systemd/system-sleep/90-agx-wifi-recover` (needs root). In `pre` it saves `/sys/power/suspend_stats/fail`. In `post` it compares the count. If it grew, the suspend failed, so it logs a line (`agx-wifi-recover`) and runs `nmcli radio wifi off; sleep 2; nmcli radio wifi on`. A successful suspend does nothing. Commands: `tools/sleep-wifi-hook.sh print` (show the hook), `sudo tools/sleep-wifi-hook.sh install`, `sudo tools/sleep-wifi-hook.sh undo` (removes the file), `tools/sleep-wifi-hook.sh status`. I tested the hook logic on the Mac with a fake `nmcli` and fake stats: no action after a good suspend, radio off and on after a failed one (fail count 0 to 2), no action without a `pre` record. It has **not** run on the M3. Whether toggling the radio really fixes the stuck Wi-Fi after the aborted suspend is **not proven**; test it by attaching the USB-C display and pressing the suspend key. If the toggle is not enough, change the hook to `systemctl restart NetworkManager` or reload `brcmfmac`.
2. **Stop the request earlier.** Add a logind inhibitor or a PowerDevil rule so the suspend key, the lid and the idle timer do not start a suspend while a USB-C display is attached. Then NetworkManager never goes to sleep and nothing needs recovery. Trade-off: the lid and the key then do nothing with a display attached, so show a desktop notification.
3. **Fix it in the kernel (best, GPU session).** Either let the DCP sleep with a display attached (needs the USB4 and Thunderbolt resume path), or fail earlier, in the `PM_SUSPEND_PREPARE` notifier, so the freezer and NetworkManager are not touched. Also look at why `brcmfmac` ends up in a bad state after an aborted suspend.
4. **Debug first.** On the next occurrence save `journalctl -b -u NetworkManager -u wpa_supplicant --since "-5min"` for the full 26 minutes. Find what happened at 01:04:50. The current log stops at 00:42.

Status: not fixed. Nothing was installed or run on the M3.

## Charger loss at 08:51:52 on 2026-10-27 (read-only investigation)

Read on the M3 on 2026-10-27 after the reboot (current kernel `7.2.11-m3gpu+`, stage O). Source: the journal of the previous boot (`journalctl -b -2`, boot id `c7f6dd7e`, 07:24 to 09:40), the `macsmc-power` driver source in `~/m3gpu/src/linux/drivers/power/supply/macsmc-power.c`, and a web search. Nothing was written to the M3.

**Facts from the journal**

- The only kernel message at the moment of the loss is the SMC firmware line `macsmc 36c400000.smc: RTKit: syslog message: aceElec.cpp:708: Elec: Elec Cause 0x20` at 08:51:52. No USB, Type-C, `tipd` or power-supply message came with it. The kernel does not log AC changes, so the AC `online` change itself (0 for about 30 min, per the user) is not in the journal. I did not see a sampler log of it.
- `Elec Cause` lines exist only in that boot. The three other boots I checked (`-3`, `-1` and the current one) have none; boot `-4` was not checked. The first line in that boot is the one at 08:51:52, so it is the first such event of the run.
- 47 seconds later (08:52:39) a GPU compute fault in `llama-bench` was followed by a KWin crash, see `docs/gpu-fault-2026-10-26.md`. The load at that moment was high. Whether a heavy load can make the SMC drop an adapter is **not proven**; it is a timing match only.
- 08:51:52 to 09:08: no further `Elec` line. Then three plug sequences at 09:08:56, 09:09:04 and 09:16:29 (the user re-plugging the dongle and charger). Each has the same pattern: `0x0`, `0x200000`, `0x8000`, `0x20`, then `charger.cpp:2638: Not charging:0` (the third had `Not charging:2000` first), then `0x1000` and `0x0`. USB hubs on `xhci-hcd.4.auto` appear and vanish in the same seconds.
- 09:16:46: the VIA hub and RTL8153 (`r8152 enu1u2`) disconnect (`usb 1-1`, `1-1.2`, `2-1`), and the log shows `Elec Cause 0x0`. The user's AC `online` came back at about 09:20.
- Nothing in the journal says which Type-C port had the charger. Today the charger is on PD controller `1-0c` (`tps6598x-source-psy-1-0c` online 1, status `Charging`). `typec/port3` and `port2` are `source [sink]`.

**What the driver and the web say about the bits**

- `macsmc-ac` `online` is the SMC key `CHIS` (non-zero means online). The battery `status` comes from `CH0R`, `CHCE`, `CHCC`, `AC-i` (below 100 mA reads as discharging), `BSFC`, `CHLS`/`CHWA` and `CHNC`. `Not charging` is reported when `CHNC` has any flag set (for example `CHNC_NOAC_CH0J` bit 53, `CHNC_NOAC_CH0I` bit 54, `CHNC_NOCHG_CH0C` bit 14, `CHNC_NOCHG_CH0B_CH0K` bit 15).
- The `Elec Cause` text is firmware (`aceElec.cpp`), so its bits are **not defined in the kernel**. A web search for the string and for the keys `CH0J`, `CH0K`, `CH0R`, `CHNC` found nothing documented, and the Asahi SMC page lists none of them. Everything below about the bits is my inference.
- Inference: `0x20` is bit 5. The driver's `CH0R` register also has bit 5 as `CH0R_NOAC_CH0J` ("AC not usable because of CH0J"). `0x8000` is bit 15, and `CHNC` bit 15 is `CHNC_NOCHG_CH0B_CH0K`. These matches may be chance. If they are real, `0x20` would mean "adapter input inhibited by CH0J" and `0x8000` "charging inhibited by CH0B/CH0K". **Unconfirmed.** `0x200000` (bit 21) and `0x1000` (bit 12) match nothing in the driver.
- The pattern fits a charger or Type-C power-contract problem more than a battery problem: the same `0x20` follows every plug while the dongle is attached and the value is `0x0` once the dongle is gone.

**Can Linux see or reset the state?**

| Question | Answer |
|---|---|
| See AC online, per-port source state, Type-C roles | **Yes.** `macsmc-ac/online`, `tps6598x-source-psy-*/online`, `/sys/class/typec/port*` (`power_role`, `power_operation_mode`) |
| See why the SMC refuses charging | **Partly.** `status` and `charge_behaviour` are derived from the keys. The raw `CH0R`, `CHNC`, `CHIS`, `CH0J` values are **not exposed**. There is no SMC key debugfs on this kernel (debugfs shows only `macsmc-hwmon`) |
| See the `Elec Cause` value | **Only in the kernel log**, as firmware text |
| Reset the inhibitors | **Partly.** `echo auto > /sys/class/power_supply/macsmc-battery/charge_behaviour` (root) writes `CH0I`, `CHTE` and `CH0C` to 0. Loading the driver (probe) also writes `CH0K` and `CH0B` to 0. **Nothing in Linux writes `CH0J`**, the key that matches bit 5 |
| Force a reset of the adapter | **Not found.** Unplug and replug the charger (what the user did). Whether a driver reload (`modprobe -r macsmc_power; modprobe macsmc_power`) clears the state is **untested** and could drop battery reporting for a moment |

**What to do next time it happens (before replugging)**

1. Save `cat /sys/class/power_supply/macsmc-ac/online`, `cat /sys/class/power_supply/macsmc-battery/{status,charge_behaviour}`, `for d in /sys/class/power_supply/tps6598x-*; do echo $d $(cat $d/online); done`, and `for p in /sys/class/typec/port*; do echo $p $(cat $p/power_role $p/power_operation_mode); done`.
2. Save `journalctl -k -b --since "-15min" | grep -E "Elec Cause|charger.cpp|tipd|typec|usb "`.
3. Try `echo auto > charge_behaviour` as root and read `status` again. If this fixes it, the cause was an inhibitor Linux can clear.
4. Ask the GPU session for a small read-only patch: a debugfs file in `macsmc-power` that prints `CHIS`, `CH0R`, `CHNC`, `CH0J`, `CH0K`, `CH0I`, `AC-i`, `ACPW`, `CHCE`, `CHCC`. This turns the guesses above into facts.
5. Note the load at the time. Use a charger rated for the machine (the user says the same charger works on another machine), and note whether the dongle was drawing power from the Mac (the M3 was the power source on that port).

**Status:** cause **not found**. Open: what raised `0x20` at 08:51:52 with no plug event, and why the state lasted 30 minutes.

## Wi-Fi recovery hook: installed 2026-10-27 12:32, logic test passed, real test open

**Status (2026-10-27 12:43):**

- Installed by the coordinator session, which acted for the user. Command: `sudo ~/sleep-wifi-hook.sh install` (a copy of `tools/sleep-wifi-hook.sh` from commit `5eadf75`). File: `/usr/lib/systemd/system-sleep/90-agx-wifi-recover`, root, mode 0755, SELinux type `bin_t`, 738 bytes. I did not run the install.
- I checked the file on the M3 (read-only): its SHA-256 starts with `22404245d7f53c57`, the same as the output of `tools/sleep-wifi-hook.sh print` in the repo. It survived the 12:42 reboot (up since 12:43:11, kernel `7.2.11-m3gpu+`).
- Logic test at 12:33, relayed by the coordinator and confirmed by the journal line `agx-wifi-recover: suspend failed (fail count 0 -> 1); restarting the Wi-Fi radio` at 12:33:19: with a fake stats folder, `pre` and `post` with no failure did nothing. With the fail count going 0 to 1 the hook restarted the radio, and Wi-Fi was enabled and `wld0` connected 25 seconds later. **Pass.**
- Side finding (coordinator): the radio restart makes the driver log `add iface p2p-dev-wld0 ... err=-52` again. It is the same harmless error as after every resume.
- **Not done:** the real test with a USB-C display attached and the suspend key (it needs the user, and the coordinator's sleep inhibitor released). Until it runs, it is not proven that the radio toggle fixes the drop after a real refused suspend.
- **Undo:** `sudo ~/sleep-wifi-hook.sh undo` (or `sudo tools/sleep-wifi-hook.sh undo` from the repo). It removes the one file.

The original plan follows. Steps 2 and 3 are done.

The hook (`tools/sleep-wifi-hook.sh`) writes one file under `/usr/lib/systemd/system-sleep/`. That is a lasting system change. Steps:

1. **Show it.** On the M3, in the repo copy: `tools/sleep-wifi-hook.sh print`. Nothing is written.
2. **Install (user types the password in the own Terminal tab):** `sudo tools/sleep-wifi-hook.sh install`. It runs a syntax check first, then writes `/usr/lib/systemd/system-sleep/90-agx-wifi-recover` (mode 0755, root). Check: `tools/sleep-wifi-hook.sh status` prints `installed`.
3. **Logic test without a suspend (user at the Mac).** Wi-Fi drops for about 10 seconds, so SSH over Wi-Fi drops too. Run `d=$(mktemp -d); echo 0 > $d/fail; export AGX_SUSPEND_STATS=$d AGX_SLEEP_SAVE=$d/save; sudo -E /usr/lib/systemd/system-sleep/90-agx-wifi-recover pre suspend; echo 2 > $d/fail; sudo -E /usr/lib/systemd/system-sleep/90-agx-wifi-recover post suspend`. Expect: a journal line `agx-wifi-recover: suspend failed (fail count 0 -> 2)` and Wi-Fi back within 15 seconds (`nmcli -t -f DEVICE,STATE d`).
4. **Real test (user at the Mac, USB-C display attached).** The coordinator's root sleep inhibitor blocks the suspend key, so it must be released first. Press the suspend key. Expect the kernel to log `refusing system sleep: a USB-C display is attached`, then the journal line from the hook and Wi-Fi back within 30 seconds. Check with `journalctl -b | grep -E "agx-wifi-recover|refusing system sleep"`.
5. **Pass criteria:** Wi-Fi and Tailscale are back within 30 seconds after the failed suspend, and a normal suspend (no display attached) still works and logs no `agx-wifi-recover` line.
6. **Undo:** `sudo tools/sleep-wifi-hook.sh undo` removes the file. `tools/sleep-wifi-hook.sh status` then prints `not installed`. No other file, setting or service is touched.
7. **Risk:** low. The hook always exits 0, acts only when `suspend_stats/fail` grew, and only switches the Wi-Fi radio off and on. If the radio toggle does not fix the drop, change the hook to restart NetworkManager or reload `brcmfmac`, and test again.

## Battery-life test plan (user at the M3, charger out)

Goal: real hours of use on battery on this kernel, from measured watts. Formula: hours = 93.0 Wh (measured full capacity) divided by average watts, then compare with the 97.8 Wh design value. Use `battery-sampler.sh` from the shared notes folder (61 samples, 10 s apart, aborts if AC stays online).

Before every run: close all GPU, LLM and build jobs (an out-of-memory event hit on the last long run), release the coordinator's sleep inhibitor if a sleep step is included, set the brightness by hand and **write it down**, keep the lid open, give no input, and record `uname -r`, `tuned-adm active`, `iw dev wld0 get power_save`, Bluetooth on or off, and whether the memory floor is on.

| Run | Condition | Length | Result to record |
|---|---|---|---|
| A | Idle desktop, brightness fixed at one value (for example 30%), Wi-Fi on | 10 min | Mean W and hours. This is the baseline |
| B | Same, screen off by DPMS (lock the screen and wait) | 10 min | Mean W. The difference to A is the panel cost |
| C | Lid closed, sleep (needs no display and no cable) | 10 min | Energy drop in Wh from `energy_now` before and after, as W. Check `suspend_stats` |
| D | Light use: a browser with one page and a video, same brightness | 10 min | Mean W and hours. No hardware video decode on this machine, so video decode runs on the CPU |
| E (optional, needs a reboot) | Run A with `pmp_report.memory_floor=0` or on stock 7.1.13 | 10 min | The cost of the memory floor in W |

Each run starts with a full charge note (`capacity`) and ends with a replug. Report mean, minimum and maximum W per run, the `capacity` drop, and the estimated hours. Earlier data point only: about 6.0 W for 50 seconds at brightness 26 (not a result). Do not compare with macOS numbers unless macOS is measured the same way.

## Overall answer

- **Sleep: works on this kernel in the logs.** Three s2idle suspends, 0 failures, and one 79 s sleep that came back by itself. The GPU session later reported 3 more key-wake cycles that passed (relayed, not run by me). This is better than the Asahi status file says ("no sleep"). The status file may describe the stock kernel. Not tested on stock.
- **Sleep is refused with a USB-C display attached** (see the bug section) and Wi-Fi does not recover by itself afterwards. This is the main open bug.
- **Lid: suspends, does not power off.** This contradicts the press line in the status file.
- **Not proven:** that the screen comes back correctly (user report open), a long sleep (minutes or hours), battery drain while asleep, and what happens with no HDMI cable attached.
- **Battery reporting: works** (percent, health, cycles, voltage, power). **Idle battery life: not measured.**
- **Power profiles: none.** CPU frequency scaling works.

## Next steps

1. User: say what the screen and keyboard light did on close and on open (black on close? picture back on open? flicker? login screen or desktop?). This decides whether the sleep row becomes "Works". The only screen report so far is the black panel at 21:29 (see the table), which came from idle screen-off and not from a suspend.
1a. Confirm the idle screen-off and wake once with a log: the user reports a black screen after 10 minutes idle and a mouse move wakes it. Check that a key press wakes it too, and that a panel behind the lock screen wakes the same way. If any case stays black, the DCP or KWin DPMS path needs a fix.
2. User, at the Mac: lid close for 10 minutes with no HDMI or USB cable attached, on battery. Then read `upower` energy before and after to get the sleep drain in W.
3. User: unplug the charger and leave the desktop idle for 10 minutes, lid open, no keyboard use. I rerun the sampler (a small script: 10 s samples of `power_now`, `current_now`, frequency, load, brightness).
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
