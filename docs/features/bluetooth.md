# Bluetooth on the M3 Pro (J516S, BCM4388)

Date: 2026-10-26. Kernel under test: 7.2.11-m3gpu+. Method: read-only (journal, sysfs, source). No reboot, no scan run by this session.

## Result

Bluetooth fails after the first suspend and resume. It does not fail at boot. The controller starts correctly at boot. After a resume, the first HCI command times out and the controller stays dead. The driver already has a recovery routine for this fault, but it is enabled only for the M2 board `apple,j493`. The fix is one condition in `hci_bcm4377.c` (patch file below).

## Test table

| Item | Test run | Result | Evidence |
|---|---|---|---|
| Hardware and driver | `lspci -nnk -s 01:00` | PASS | `01:00.1` BCM4388 Bluetooth `14e4:5f72`, driver `hci_bcm4377`. Wi-Fi is `01:00.0`, driver `brcmfmac`. |
| rfkill | `rfkill list` | PASS | `hci0` and `phy0` are not soft blocked and not hard blocked. |
| Boot start (boot 0) | `journalctl -b 0 -k` | PASS | `hci_bcm4377 0000:01:00.1: reset done`, then `hci0` is set up at 20:42:57. No timeout in the first 32 minutes. |
| Boot start (14 older boots) | Loop over `journalctl -b -14..-1` | PASS | 0 lines with `tx timeout` or `-110` in all 14 boots (7 on 7.2.11-m3gpu+, 7 on 7.1.13). |
| Suspend in older boots | `grep "PM: suspend entry"` per boot | NONE | 0 suspends in the 14 older boots. Older boots did not test resume. |
| Suspend in boot 0 | Same grep | 3 suspends | `s2idle` at 21:14:51, 21:14:56 and 21:15:02 (from the sleep session tests). |
| First failure | `journalctl -b 0 -k` | FAIL | 21:14:59: `hci0: command 0x0c01 tx timeout`, `Opcode 0x0c01 failed: -110`. It is inside the second resume (`PM: resume devices took 2.024 seconds`). |
| Second failure | Same | FAIL | 21:16:21: the same two lines inside the third resume. |
| Later failures | Same | FAIL | From 21:27:48: `Opcode 0x202d failed: -110`, `Unable to disable Address Resolution: -110`, `Opcode 0x2039 failed: -110`, more `0x0c01 tx timeout`. These match the scan and power tests. |
| Controller state | `bluetoothctl show` | FAIL | `Powered: yes`, `PowerState: off`. bluetoothd logs `Failed to set mode: Authentication Failed (0x05)` at 21:28:44. |
| Codec message | `grep "codec capab"` | HARMLESS | `Failed to read codec capabilities (-22)` 10 times at every boot, in all 15 boots, also when Bluetooth works. It is not the cause. |
| Bluetooth firmware | `ls /lib/firmware/vendor/brcm` | PASS | Board type in the device tree is `apple,jura`. Files `brcmbt4388c0-apple,jura-a.{bin,ptb}` and `jura-u.{bin,ptb}` exist. The driver loaded them (no firmware error in the log). |
| Wi-Fi firmware | `journalctl -k` | PASS | `brcmfmac4388c0-pcie`, `BCM4388/4 wl0 ... version 23.30.58.0.41.51.138`. Loaded 1 s after the Bluetooth core. |
| Wi-Fi and Bluetooth coexistence | Compare log times | NOT THE CAUSE | The `-52` Wi-Fi errors (`join_pref`, `p2p`) occur at boot (20:42) when Bluetooth works. They occur again at 21:14 with no relation to the Bluetooth timeout. The HCI timeouts happen with Wi-Fi idle. A command timeout on the host ring is not a radio sharing fault. |
| Driver recovery on this board | `grep "recovering transport"` in boot 0 | NOT RUN | No `recovering transport once after resume command timeout` line. The routine is off for this board (see root cause). |
| Stock kernel 7.1.13 | Old boot logs | NOT TESTED FOR RESUME | The stock kernel has no timeouts, but no boot on it had a suspend. The stock kernel has no resume recovery code. It very likely has the same fault. This needs one resume test on 7.1.13. |
| `/sys/kernel/debug/bluetooth` | `ls` | DENIED | Needs root. Not read. |
| Upstream reports | Web search (standard) | NO M3 REPORT FOUND | Only the 2024 boot timeout fix (BCM4388 boot needs more than 2 s; 5000 ms timeout, in kernel 6.10 and later). It is in 7.2.11. No post on M3 resume. Nothing was posted. |

## Root cause

1. `hci_bcm4377` suspends the chip with `BCM4377_BAR0_SLEEP_CONTROL_QUIESCE` and resumes it with `UNQUIESCE` (`bcm4377_suspend`, `bcm4377_resume`).
2. On J516S, the BCM4388 firmware does not answer HCI commands after this sequence. The PCI rings still work. The first command after resume (`0x0c01`) times out.
3. The driver tree has a recovery routine (`bcm4377_hci_timeout`, `bcm4377_resume_recovery_sync`). It sets `needs_reset` and does a full PCI function reset and firmware boot.
4. The routine is gated by `bcm4377_resume_recovery_supported()` in `drivers/bluetooth/hci_bcm4377.c` line 1509. It returns true only for chip `0x4378` on `apple,j493`. J516S has chip `0x4388`, so the routine never runs. The log has no `recovering transport` line.
5. `bluetoothctl power off` and `on` do not help because the ring teardown still succeeds, so `needs_reset` stays false. The next open does not reset the chip.

Confidence: high that the fault starts at resume (3 of 3 failures start inside a resume, 0 of 14 older boots fail). Medium that the existing routine fixes 0x4388, because it was written for 0x4378. Not yet proven: a fresh boot scan with a real device. No scan was run by this session.

## Fix plan

Step 1 (no rebuild, test now, needs the user): reload the module to reset the chip. Run in the user's Terminal tab:

```bash
sudo modprobe -r hci_bcm4377 && sudo modprobe hci_bcm4377
```

Then run `bluetoothctl scan on` with a phone in pairing mode. If devices appear, the chip is fine and the fault is resume only. Wi-Fi is not affected (`brcmfmac` is a separate function). Do not do this before saving work: it is a driver reload, not a reboot.

Step 2 (kernel patch): `agx-linux-kit/patches/hci-bcm4377-j516s-resume-recovery.patch`. It changes one function in `drivers/bluetooth/hci_bcm4377.c`:

```c
return (bcm4377->hw->id == 0x4378 && of_machine_is_compatible("apple,j493")) ||
       (bcm4377->hw->id == 0x4388 && of_machine_is_compatible("apple,j516s"));
```

The patch passed `patch --dry-run` on a copy of the current source. It was not built. The GPU session builds it. Only `hci_bcm4377.ko` changes, so a module-only rebuild is enough.

Step 3 (after the new module loads): suspend and resume once, then run a scan. The expected log is `recovering transport once after resume command timeout`, then `performing hardware reset recovery`, then `hardware reset recovery completed successfully`.

Step 4 (if step 3 fails): run the module reload from step 1 in a systemd sleep hook as a workaround (`/usr/lib/systemd/system-sleep/`, action `post`). This needs root and is not written here. A better route is to disable `QUIESCE` on resume for 0x4388, but this needs tests with `btmon`.

Step 5: test on the stock 7.1.13 kernel with one suspend. This tells if Asahi upstream has the fault. Post an Asahi issue only if the user agrees.

## Not done

- No pairing test (no device was in pairing mode).
- No `btmon` trace (needs root for the user channel).
- No Bluetooth scan on a fresh boot.

## Update: tests with the patched driver (same day, later boot)

Kernel 7.2.11-m3gpu+ with the patched `hci_bcm4377.ko` (patch `patches/hci-bcm4377-j516s-resume-recovery.patch`). Booted at 21:59 and again at 22:44.

| Item | Test run | Result | Evidence |
|---|---|---|---|
| Fresh-boot scan | `bluetoothctl --timeout 25 scan on`, 3 runs | PASS | 13 or more devices in run 1, 4 in run 2, 4 in run 3. No `tx timeout` and no `-110` in the kernel log. Before the patch, the same scan found 0 devices (after resume). |
| Pairing and connect | Headset in pairing mode, paired and connected from the desktop | PASS | `Paired: yes`, `Bonded: yes`, `Trusted: yes`, `Connected: yes`. No `hci0` error in the kernel log. Profiles: A2DP sink, HFP, AVRCP. |
| Audio route | `pactl list cards`, `pactl list short sinks` | PASS (routing only) | The headset is the default sink. The microphone source exists. Profiles A2DP (SBC, SBC-XQ, AAC) and HFP (CVSD, mSBC) are available. Sound quality and a call were not tested by this session. |
| Resume with the patch | 3 suspend and resume cycles (s2idle), 2026-10-27 01:15 to 01:35 | PASS | See the section "Suspend and resume test with the patch". The fault came back at resume 2 and 3, and the driver recovered by itself in about 1 s each time. |

## Suspend and resume test with the patch

Run in the combined test window on 2026-10-27 (kernel 7.2.11-m3gpu+ with the patched `hci_bcm4377.ko`). Three s2idle cycles in one boot. After each cycle: kernel log for `hci0` and `hci_bcm4377`, a 20 s scan, the headset state, and the LibrePods service.

| Cycle | Resume at | Kernel log | Scan | Headset and app | Result |
|---|---|---|---|---|---|
| 1 | 01:16:36 | No `hci0` or `hci_bcm4377` line. No timeout. | 14 devices | Connected, `librepods.service` active | PASS (no fault this time) |
| 2 | 01:25:03 | `command 0x0c01 tx timeout`, `Opcode 0x0c01 failed: -110`, `Opcode 0x0c1a failed: -110`, then the recovery lines below | 17 devices | Connected, active | PASS (recovered) |
| 3 | 01:34:32 | Same pattern as cycle 2 | 17 devices | Connected, active | PASS (recovered) |

Recovery lines, in order (cycles 2 and 3, within about 1 s):

1. `recovering transport once after resume command timeout`
2. `transport needs hardware reset on next open`
3. `device marked for reset, reinitializing hardware before open`
4. `performing hardware reset recovery`
5. `reset done`, then `hardware reset recovery completed successfully`
6. `reloading calibration and PTB after hardware reset`, then `restoring BD_ADDR ... after hardware reset` (the address is not recorded here)

What this shows:

- The original fault is confirmed. The first resume in a boot was fine, and the second and third resume lost the first HCI command (`0x0c01`). Before the patch, the controller then stayed dead until the end of the boot (0 devices in every scan).
- The patch works on J516S. The recovery routine that was limited to `apple,j493` now runs for BCM4388 on `apple,j516s`. In both faults it reset the chip, loaded the firmware again, and left Bluetooth usable. After each recovery, the controller was `Powered: yes` and `PowerState: on`, scans found devices, and the paired headset reconnected.
- The 2 timeouts per fault (`0x0c01` twice) are the trigger for the recovery. They are expected. They are not left over after the recovery.
- The 10 `Failed to read codec capabilities (-22)` lines after each reset are the same harmless lines as at every boot.
- The cause of the lost command after resume (chip firmware not answering after the `QUIESCE` and `UNQUIESCE` sequence) is not fixed. The patch hides it. An upstream fix would need a trace of the chip state at suspend. Not done.

Not tested: the stock 7.1.13 kernel (no recovery code there, so the fault is expected), a suspend with an active audio stream, a resume with the headset in the case.

## AirPods Max features with LibrePods

The kernel driver does not give Apple features (ear detection, noise control, battery). The app LibrePods does. It talks to the headphones over a private Apple channel. Build steps: `build/build-librepods.sh` (pinned source commit 89356c0, GPL v3). Two local patches: `patches/librepods-m3-aac-codec.patch` and `patches/librepods-m3-resume-playback.patch`.

Safety review: SkillSpector scan of `linux/` found 19 findings (17 MEDIUM, 2 LOW, 0 HIGH). They are `sudo` lines in the README and text in a bundled QR library. The Linux C++ code has no network code. It calls `bluetoothctl connect` and `disconnect`, and `systemctl --user restart wireplumber`. It can write an autostart entry only when the user asks. Verdict: CAUTION (young project; only the flagged parts were read in detail).

| Item | Test run | Result | Evidence |
|---|---|---|---|
| Control channel | App log (`journalctl --user -t librepods`) | PASS | The app finds the connected headset, opens the control channel and requests notifications. |
| Battery | App log | PASS | `Headset: 100%`. |
| Noise control, M3 to headset | `librepods-ctl noise:transparency`, then `noise:anc` | PASS (log) | The app writes the packet and the headset answers with the same mode. The sound change was not confirmed by ear. |
| Noise control, headset to M3 | Button on the headset | PASS | Each press arrives in the log as Off, ANC or Transparency. |
| Ear detection | Take the headset off and put it on | PASS | The log shows `NotInEar` and `InEar` events. |
| Pause on take-off | Music in Firefox, take the headset off | PASS | `Paused playback for org.mpris.MediaPlayer2.firefox...`. The user confirmed the pause. |
| Resume on put-on | Put the headset on again (with `librepods-m3-resume-playback.patch` built) | PASS | Log: `Paused playback for ...firefox...`, then `Resumed playback for ...firefox...` about 1 s after put-on at 23:46:36. The user confirmed. Before the patch there was no resume attempt: the default rule needs both ears in ear, and the check for the active sink ran before the sink came back. The patch resumes when one ear is back, after 1 s. A short pause, resume, pause chain can happen while the headset reports its ears in steps (23:46:31 to 23:46:32). |
| Pause on take-off, second cause | Video playing, headset off, headset on (service started after the video) | FAIL (found), fix built | No pause and no resume. LibrePods gates the pause on `getCurrentMediaState()`, which asks D-Bus with an empty service name and is unreliable. `librepods-m3-pause-gate.patch` removes the gate (`pause()` already reads each player) and keeps the list of paused players. Built and the service restarted. The test with this build is pending. |
| Codec | `pactl list cards` | FIXED | LibrePods forced SBC-XQ on every put-on and tried AAC last. `librepods-m3-aac-codec.patch` prefers the codec-negotiating profile `a2dp-sink` (AAC). Built and confirmed: the active profile is `a2dp-sink`. Sound was not compared by ear. |
| Audio out (A2DP) | 1 s tone to the headset sink, AAC profile | PASS (routing) | `paplay` finished with no error. Heard-by-ear not confirmed by this session. |
| Call profile (HFP) link | `pactl set-card-profile ... headset-head-unit` and `-cvsd`, `btmon` capture | PASS | `Enhanced Setup Synchronous Connection` and `Synchronous Connect Complete` with status Success, link type eSCO, air mode transparent (mSBC). Chip SCO routing is `01` (host transport), read with vendor command 0xFC1D. Read Buffer Size: SCO MTU 254, 1 packet. |
| Microphone, capture only | `parecord` 6 to 12 s from the headset source, user speaking, 4 runs (mSBC and CVSD) | FAIL | Digital silence (-90 dBFS) in every run. Source not muted, volume 100%. |
| Microphone, capture with playback open | `parecord` 8 s while `paplay` plays a silent file to the headset sink | PASS | 55 of 79 blocks above -45 dBFS, peak -22.5 dBFS: the voice was captured. So the Bluetooth chip and driver carry call audio. The silence happens when only the capture side is open. This looks like a PipeWire or BlueZ behavior, not a driver fault. Real call apps open both sides. Not tested with a real call app. |
| Microphone, real app (Firefox mic test page, 30 s recording) | The call profile switched by itself when Firefox started recording (after 36 s of waiting for the user). The page reported a paused audio track until a silent playback was also open on the headset. Then a 30 s recording was saved by the user and measured (levels only, file not moved) | PASS (with the playback condition) | Opus, 48 kHz, mono, 30 s. Speech 90th percentile -19 dBFS, peak 0 dBFS with 25 clipped samples, no dropout longer than 12 ms. 117 of 300 blocks (100 ms) are digital silence (-85 dBFS or lower): the pauses are gated, so the quiet-room hiss was not measured (the page or the headset gates it). Call quality is limited by the call profile (mono, 16 kHz). |
| Microphone, laptop array | `effect_output.j516-mic`, 12 s, user talking | UNCLEAR | Level about -74 dBFS the whole time, peak -48 dBFS, no clear speech. The audio session measured a similar low level (tone at -61 dB). Gain may be too low. Not changed by this session. |
| Popup windows | User report | OPEN | The window opens only at start (without `--hide`), on a tray click or on a `reopen` command. A user report of popups during idle is not explained. The app was restarted three times without `--hide` during tests, which may explain part of it. |
| Autostart | `install/librepods.service` as a systemd user unit, `enable --now` | PASS | `is-active` and `is-enabled` both report yes. The app starts in the tray with `--hide` and connects to the headset (battery read). Not tested across a login. |

Note on a desktop crash seen at 23:23: `plasmashell` crashed (SIGSEGV) during the GPU stress test. The stack ends in `agx_batch_init` in the Mesa AGX driver. It is a GPU driver fault, not a Bluetooth or LibrePods fault. It was sent to the GPU session.

## Left

- Popup windows. A call with a real app (Firefox or a chat app) to confirm the microphone. A capture-only recorder may get silence: test with `pw-record` and check the PipeWire and WirePlumber Bluetooth settings.
- Privacy: the app writes the headset encryption keys into the user journal. Do not share its logs.
- Optional: one resume test on the stock 7.1.13 kernel.
