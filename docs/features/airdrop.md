# AirDrop (J516S, 7.2.11-m3gpu+, Fedora Asahi Remix 44)

Status 2026-10-26: `awdl0` works on the built-in Broadcom BCM4388 with Wi-Fi staying up. Mac to M3, M3 to iPhone and iPhone to M3 transfers work. M3 to Mac is not supported (standing rule: this Mac reaches the M3, nothing goes the other way).

## Result in one paragraph

No USB Wi-Fi adapter is needed. Apple's Broadcom firmware has its own AWDL engine, and the 7.2.11-m3gpu+ `brcmfmac` already carries the omdrop-awdl patches (module parameters `awdl`, `awdl_bssid`, `awdl_trace`). Only userspace is missing: the helpers that create `awdl0`, announce the machine, and the AirDrop receiver. Owly (omdrop-owl) and MediaTek adapters are the route for other machines, not this one: the BCM4388 has no monitor mode under Linux.

## Sources, pinned

| Part | Repository | Commit |
|---|---|---|
| radio helpers | netmojo-systems/omdrop-awdl | `9c846cd598e234cf874019a868a777e85dce05fe` |
| receiver | netmojo-systems/omdrop-plugin | `48867c6d5bb6ee08eb6b7e6e4e20a8210d65fdee` |

The plugin's `omdrop` command targets Arch (pacman, ufw), so it is not used. Only `bin/airdrop-serve.py` and `share/certs/apple_root_ca.pem` are used. Review result: no hidden network calls, no obfuscation, no sudoers edits, no setuid. The root helpers send firmware commands, run `ip link`, and reload the NetworkManager config. Not read line by line: `omdrop-broadcom.sh`, `airdrop-send.py`, `awdl_identity.py`, the plugin's `bin/omdrop`, the Rust core.

## Install steps

All steps are in `build/airdrop-setup.sh`, run on the M3 in this order.

| Step | Command | What it changes | Undo |
|---|---|---|---|
| 1 | `airdrop-setup.sh fetch` | clones both projects at the pinned commits into `~/omdrop-test`; checks the Apple Root CA fingerprint | delete the folder |
| 2 | `airdrop-setup.sh deps` | dnf: `python3-ifaddr`, `python3-libarchive-c`, `python3-zeroconf` (17 MiB, Fedora repo) | `sudo dnf remove` the three |
| 3 | `airdrop-setup.sh mac` | Wi-Fi profile gets `wifi.cloned-mac-address=permanent`; Wi-Fi reconnects once | `undo` restores `stable-ssid` |
| 4 | `airdrop-setup.sh up` | `awdl-up`: creates `awdl0`, writes `/etc/NetworkManager/conf.d/99-awdl-unmanaged.conf`, reloads the NM config | `undo` |
| 5 | `airdrop-setup.sh firewall` | firewalld runtime: `awdl0` in zone `work`, TCP 8771 open | reboot, or `undo` |
| 6 | `airdrop-setup.sh receiver` | receiver in a retry loop (it exits while `awdl0` has no link-local address) | stop the loop |
| 7 | `airdrop-setup.sh window 180` | `omdrop-discoverable start 180`: makes the M3 visible for 180 s | `omdrop-discoverable stop` |
| 8 | `airdrop-setup.sh send ADDR FILE` | sends a file to a peer; no root | none |

| 9 | `airdrop-setup.sh notify` | follows the receiver log and runs `notify-send` after each upload (needs the desktop session bus) | stop the loop |

Received files go to `~/Downloads`.

Why step 3: Fedora's default is a random per-network Wi-Fi MAC (`stable-ssid`). `awdl-up` derives the AWDL address from the permanent MAC and exits with code 5 on a random one. The side effect is that the router sees the real MAC.

`awdl-up --reload` unloads `brcmfmac` and drops Wi-Fi for 15 s to minutes. Never run it by habit.

## Results (2026-10-26)

| Check | Result |
|---|---|
| `awdl-up` with the real MAC | exit 0, `awdl-if create -> OK`, kernel log "AWDL interface awdl0 created" |
| Wi-Fi during create and during a window | stayed connected; SSH over Wi-Fi stayed up |
| Data-path gate (`omdrop-discoverable start`) | 20 of 20 frame completions |
| Firmware 23.30.58 service record | the BCM4387 format is rejected (`EBADE`); the helper's length-header fallback works. Same quirk the project reports for 23.20.95 |
| Receiver | serves `<awdl0 MAC>._airdrop._tcp.local` on the link-local address, TCP 8771 |
| Mac to M3 (Finder AirDrop, Everyone) | works: the M3 shows by name in Finder; `/Discover`, `/Ask`, `/Upload` all answered 200; a 5-byte file arrived |
| Mac to M3 from the command line | works: `tests/airdrop-send-from-mac.swift` (system AirDrop service, picker click on the target); a 27-byte file arrived and the receiver logged `/Upload` 200 |
| M3 to iPhone (`airdrop-setup.sh send`) | works: the iPhone asked, the user accepted, 18-byte file arrived (`Upload ... ok`). Needs the iPhone unlocked and on "Everyone for 10 Minutes"; a few tries are normal (the iPhone listens in bursts) |
| iPhone to M3 | works: `/Discover`, `/Ask`, `/Upload` answered 200 and an 18-byte file arrived in `~/Downloads`. Three earlier windows failed because the iPhone had dropped "Everyone for 10 Minutes" (iOS reverts to Contacts Only after 10 minutes). In a failing window the iPhone is in the AWDL peer table with matching counters but sends no data frames (`datarx` flat) |
| M3 to Mac | not supported by choice. Two tries failed anyway: the Mac refuses TCP on the fixed port 8770 that `--direct` uses |

Diagnostics: `diag-window` style runs (`omdrop-discoverable peers`, `diag 5`) show whether peers are in the group and whether data frames arrive. Look at `datarx`: if it never moves while the share sheet is open, the iPhone is not talking to the M3, which so far meant the Everyone timeout.

Found on the way: with the iPhone on "Contacts Only" (iOS drops "Everyone for 10 Minutes" after 10 minutes) it answers the M3's TLS handshake with `certificate unknown`. A refused handshake therefore means: reset the iPhone to Everyone.

## Limits and open points

- `sudo` needs a terminal and a password here. A window is therefore started by the user (`ssh -t`), not by a script run over a non-interactive SSH.
- The iPhone must be on "Everyone for 10 Minutes" with the share sheet open. "Contacts Only" needs an Apple-issued identity and does not work.
- Visible windows move the radio off the home channel on a 6/44/149 schedule. Expect slower Wi-Fi during a window.
- The firewall change is runtime only. The receiver is not a service yet. Nothing starts at boot.
- Firmware 23.30.58 is newer than any version the project lists as tested. Sending is verified upstream only on the BCM4387 (M1 Pro).

## Surviving a reboot

`build/airdrop-persist.sh` has two parts. A reboot removes `awdl0`, the firewalld zone binding, the receiver and the watcher unless both parts are installed.

| Part | Command | What it installs | Status 2026-10-27 |
|---|---|---|---|
| user | `airdrop-persist.sh user` | systemd user services `airdrop-receiver` (Restart=always, log to `receiver.log`) and `airdrop-notify`, both enabled | installed and running |
| root | `sudo airdrop-persist.sh root` | copies the reviewed helpers to root-owned `/usr/lib/omdrop`, installs `awdl0.service` (NOT enabled by default, see Wi-Fi coexistence) plus a drop-in that rebinds `awdl0` to firewalld zone `work`, opens TCP 8771 permanently, installs the upstream polkit policy (a local desktop session opens a window without a password) | NOT applied: needs the user's own approval and password |
| undo root | `sudo airdrop-persist.sh remove` | removes the unit, drop-in, policy, `/usr/lib/omdrop`, the permanent port | |

Windows stay manual until the polkit policy is installed. The policy applies only to an active local session on the M3, not to SSH.

## Buttons (built, not yet deployed or tested)

`build/airdrop-persist.sh ui` installs user-level files from `build/airdrop-ui/`:

| Button | File | Does |
|---|---|---|
| AirDrop on (10 min) | `airdrop-on` + `.desktop` launcher | `pkexec omdrop-discoverable start 600`, then a notification; pin it to the panel |
| AirDrop off | `airdrop-off` + `.desktop` launcher | closes the window |
| Send via AirDrop (Dolphin right-click) | `airdrop-send` + service menu | opens a window if needed, lists devices (`send-to-peer --list --names`), asks which one with kdialog, sends, notifies |

All three need the root part (`/usr/lib/omdrop` and the polkit policy), so they work only after `sudo airdrop-persist.sh root`. They have not run on the M3 yet. The device picker parses `send-to-peer --list --names` by assuming the first field of each row is the MAC; this is untested. The picker lists every device it hears. The standing rule that nothing goes from the M3 to the user's own Mac is not enforced by the picker.

## Wi-Fi coexistence (design, 2026-10-27)

Status: AirDrop stays OFF on the M3 after the Wi-Fi comes back, until the fix below is tested. This section is research and design. Nothing in it was run on the M3.

### What happened (reported by the coordinator, from the M3 kernel log)

| Time | Event |
|---|---|
| 00:39:00 | `brcmf_cfg80211_add_iface: iface validation failed: err=-16` |
| 00:39:33 | wld0 loses the router: `Authentication ... timed out`, reason 3 |
| after | the firmware answers `-52` to `join_pref` and `interface_remove`; wld0 stays DOWN; Tailscale offline; `awdl0` stays UP and promiscuous; deleting it fails with `-52` |

The firmware is wedged and needs a `brcmfmac` reload or a reboot.

### Confirmed by reading code

1. `-16` is `-EBUSY`. Upstream `brcmf_cfg80211_add_iface()` prints "iface validation failed" when `brcmf_vif_add_validate()` fails. That function counts the existing interfaces by `wdev.iftype`, adds the requested type, and runs `cfg80211_check_combinations()`. It runs before the type switch, so it applies to station, AP, monitor and P2P adds alike.
2. The AWDL patch (`brcmf_awdl_add_vif()`, omdrop-awdl patches 0001 and 0008) registers the AWDL interface as `NL80211_IFTYPE_STATION` for cfg80211 bookkeeping. So while `awdl0` exists it holds a station slot. Whether that makes another add exceed the advertised combinations depends on the firmware's MCHAN flag (see "What the logs prove"); it is a likely contributor, not a proven cause.
3. No omdrop helper calls the nl80211 add-interface path. `awdl-up` creates `awdl0` through a firmware vendor command (`brcm_iovar.py awdl-if create`). `grep` over omdrop-awdl `userspace/` and omdrop-plugin `bin/` finds no `iw dev ... add`, no `NEW_INTERFACE`, no `ip link add`. So the `add_iface` caller at 00:39:00 is not the AirDrop code. It is something else that asked the driver for an interface.
4. The receiver (`airdrop-serve.py`) only binds a socket on `awdl0`. It never creates an interface. Its restart loop (every 5 s while `awdl0` has no link-local address) wastes CPU and fills the log, but it cannot cause `add_iface`.
5. The upstream docs and `awdl-up` comments say two other things that matter: with a PSF template loaded (after any window), `awdl=0` once hung the firmware, and a clean reconfigure needs a driver reload, which drops Wi-Fi.

### Hypotheses for the add_iface caller (resolved below by the saved logs)

| Id | Hypothesis | How to confirm from logs | Fix if true |
|---|---|---|---|
| H1 | suspend or resume (the sleep tests): the stack re-adds interfaces on resume while `awdl0` exists | `journalctl -b -g "PM:\|suspend\|resume\|Freezing"` near 00:39:00; `last -x` | destroy or never create `awdl0` before suspend; block suspend while a window is open |
| H2 | `wpa_supplicant` or NetworkManager re-creating the P2P device or a P2P group interface (an `p2p-dev-wld0` device exists) | `journalctl -b -u NetworkManager -u wpa_supplicant` 00:38 to 00:40; `nmcli device` | brcmfmac module parameter `p2pon=0` (parameter exists in `modinfo brcmfmac`) so there is no P2P interface to re-add; takes a driver reload or reboot |
| H3 | the end of a window: `awdl=0` with a template loaded hangs the firmware, and the add failure is a side effect | `omdrop-discoverable` log lines and `awdl txstatus` kernel lines before 00:39:00; window start and expiry times | never end a window with `awdl=0`; end it by removing the interface path that upstream documents, or reload the driver |
| H4 | the root part ran at about 00:38 (`firewall-cmd --reload`, `systemctl start awdl0.service`) | shell history of the user; `journalctl -b -u awdl0.service -u firewalld` | already addressed below (no boot unit) |

Evidence needed from the coordinator (read-only, saved to the shared notes folder): `journalctl -k -b` from 00:30 to 00:42, `journalctl -b -u NetworkManager -u wpa_supplicant -u awdl0.service -u firewalld` for the same time, the suspend and resume times of any sleep test, and the exact lines around the first `-16`.

### Resolved from the saved logs (private-dumps/wifi-drop-2026-10-27, read 2026-10-27)

The caller was `wpa_supplicant`, started by a suspend that did not happen. In order, all at 00:38:59 to 00:39:13:

1. `systemd-logind`: "Suspend key pressed short. The system will suspend now!" (a key press, not a sleep test script).
2. NetworkManager: "sleep requested", `wld0` deactivated with reason `sleeping`; firewalld unregisters its rules; ModemManager drops its inhibitor.
3. The kernel enters s2idle twice and refuses both times: `apple-dcp ... refusing system sleep: a USB-C display is attached` (genpd `-16`). The machine resumes within the same second (`PM: suspend exit`). USB-C ports then disconnect at 00:40:02, a separate event.
4. NetworkManager: "wake requested". `wpa_supplicant` runs `nl80211: deinit ifname=wld0`, starts `wld0` again, and tries to create `p2p-dev-wld0`: `Failed to create interface p2p-dev-wld0: -16`, then the kernel line `brcmf_cfg80211_add_iface: iface validation failed: err=-16`. `awdl0` was up at that time.
5. 00:39:13: `brcmf_c_set_joinpref_default: Set join_pref error (-52)` as NetworkManager starts to reconnect; 00:39:33: `Authentication ... timed out`, `reason=3`. The firmware no longer answers.

So H1 (suspend, here an aborted one) and H2 (`wpa_supplicant` re-creating the P2P device) are confirmed as one chain, with the aborted suspend as the proven trigger. H3 (window end) and H4 (root part) are ruled out: no `awdl0` helper, `omdrop-discoverable` or `firewall-cmd` run appears in that minute; the firewalld lines are its reaction to NetworkManager sleeping.

What the logs prove, and what they do not:

| Claim | Status |
|---|---|
| A suspend key press started a refused s2idle (display attached), NetworkManager slept and woke the radio, `wpa_supplicant` re-initialised `wld0` and its P2P add failed with `-16` | proven by the logs |
| NetworkManager woke at 00:39:00 (`wake requested`, state `CONNECTED_LOCAL`, then `CONNECTING` at 00:39:13). What stayed down afterwards was `wld0` (firmware not answering), not NetworkManager. The saved dump ends at 00:42, so it cannot show 01:04 | proven for 00:30 to 00:42 |
| `awdl0` caused the `-16` | **likely, not proven** (next row) |
| the failed P2P add, or the station going down and up, wedged the firmware | not separable from the logs |
| AirDrop code called `add_iface` | disproven: no helper uses that path |

Why `awdl0` is the likely contributor. Upstream `brcmf_setup_ifmodes()`: with P2P and without MCHAN, combination 0 allows `STATION` max 1, `P2P_DEVICE` max 1 and `P2P_CLIENT`/`P2P_GO` max 1; a second combination allows STATION 1, AP 1, P2P_CLIENT 1, P2P_DEVICE 1. STATION is 2 only when the firmware reports MCHAN. The AWDL patch registers `awdl0` as `NL80211_IFTYPE_STATION`. With `wld0` and `awdl0` both counted as stations, any new interface (here the P2P device) exceeds the limit and returns `-EBUSY`. Without `awdl0` the same add (one station plus one P2P device) fits. This is derived from code, not observed: whether the BCM4388 reports MCHAN is not checked (read-only check after release: `iw phy phy0 info`, section "valid interface combinations"), and no control run without `awdl0` exists. Test T6a (baseline without `awdl0`) and T6b (with `awdl0`) are the control experiment. Until they run, AWDL is a possible contributor and the aborted suspend is the only proven trigger.

Consequence that does not depend on the answer: a suspend key press with a USB-C display attached repeats the NetworkManager sleep and wake with no real sleep. That belongs to the sleep and display work, not to AirDrop.

### New evidence 2026-10-27 12:33 (reported by the coordinator, log not read by me)

A Wi-Fi radio restart during the sleep-hook test, with no `awdl0` on the machine (AirDrop off, driver reloaded at 01:04), gave the same family of errors: `brcmf_cfg80211_add_iface: add iface p2p-dev-wld0 type 10 failed: err=-52` and `brcmf_p2p_create_p2pdev: set p2p_disc error`. The error code differs (`-52` from the firmware, not `-16` from the host limit check) and `awdl0` was absent. So the P2P device re-creation can fail on a radio restart without any AWDL interface. This lowers the weight of the AWDL explanation: `awdl0` is not needed for the P2P add to fail. Whether `awdl0` made the 00:39 outcome worse (a wedged firmware, not only a failed add) stays open. Status of the AWDL link: possible contributor, not shown to be necessary.

### Switching the P2P device off (researched, nothing verified on the M3)

| Option | Source | Status |
|---|---|---|
| brcmfmac `p2pon=0` | module parameter list | already 0 on the M3 and does not stop the failure |
| `p2p_disabled=1` in `/etc/wpa_supplicant/wpa_supplicant.conf` | hostap list advice (2015): prevents the P2P Device interface on the main interface | a 2025 hostap post says it does not apply to interfaces NetworkManager creates later, so NetworkManager re-creating `wld0` may bring P2P back; unverified here |
| hostap patch series of October 2025 that adds and removes the P2P Device when `p2p_disabled` changes | hostap mailing list | not confirmed merged or present in the Fedora build |
| NetworkManager setting to hide P2P | searched | none found. `nmcli device set p2p-dev-wld0 managed no` would stop NetworkManager using the device but not `wpa_supplicant` creating it (untested idea) |

Read-only checks for the M3, after release: `rpm -q wpa_supplicant NetworkManager`; `grep -rn p2p /etc/wpa_supplicant /etc/NetworkManager`; `iw phy phy0 info` (interface combinations and MCHAN); `journalctl -b -u wpa_supplicant -g p2p`. A first try is `p2p_disabled=1` in the wpa_supplicant config file, with a rollback copy of the file, on the console only, followed by a radio restart and a look at `nmcli device` for `p2p-dev-wld0`.

### Design: a stable mode

Principle: AirDrop must not be able to take Wi-Fi down. Every step below is chosen to keep the infrastructure link first.

1. **No `awdl0` at boot, none outside a window.** `build/airdrop-persist.sh root` no longer enables `awdl0.service` (set `AIRDROP_BOOT_AWDL=1` to opt in). The AirDrop on button runs `omdrop-discoverable start`, which rebuilds a missing `awdl0` itself. While no window has ever run in this boot, `awdl0` does not exist and holds no station slot.
2. **The receiver runs only during a window.** The AirDrop on button starts `airdrop-receiver.service`, the off button stops it. The unit is not enabled at login. It has `Restart=on-failure`, `RestartSec=10`, and a start limit of 5 in 300 s, so it cannot loop. (The unit already deployed on the M3 is `Restart=always` with 5 s and is enabled. It must be changed with `airdrop-persist.sh user` and `systemctl --user disable --now airdrop-receiver` after the Wi-Fi is back.)
3. **Pin AWDL to the station channel.** Upstream OWL runs in shared mode only when the access point is on channel 6, 44 or 149, so AWDL never leaves the infrastructure channel. The M3's router is on channel 40. Moving the router to 44 or 149 and setting `peer-chan` to match (`/etc/omdrop/peer-chan`, `chan-shape=dense44`) removes channel hopping during a window. This is the main lever for Wi-Fi throughput and association stability. It changes the router, so it needs the user's go.
4. **No second interface while `awdl0` exists.** After H2 or H1 is confirmed, apply its fix. Until then, with `awdl0` absent by default (point 1), the `-16` cannot occur outside a window.
5. **Sleep guard.** `awdl0` cannot be removed safely after a window (see below), so "no `awdl0` outside windows" holds only until the first window of a boot. The log chain shows the real risk is a sleep or wake request while `awdl0` exists. Two measures, both needed until one is proven: (a) hold a `systemd-inhibit --what=sleep:handle-suspend-key` while `awdl0` exists (an inhibitor service tied to the AirDrop on button, released at the next boot), and (b) stop `wpa_supplicant` from creating the P2P device (no proven switch yet, see "Switching the P2P device off"). The earlier idea of `p2pon=0` is void: the coordinator measured `/sys/module/brcmfmac/parameters/p2pon` = 0 already (driver default), and the P2P device still fails, so `p2pon` controls the legacy P2P path, not the dedicated `p2p-dev-wld0` that `wpa_supplicant` asks cfg80211 for. Measure (a) removes the trigger only while `awdl0` exists; it makes sleep unavailable after any AirDrop use, so it is a stopgap.
6. **Recovery without a reboot.** The documented recovery is `awdl-up --reload` (reloads brcmfmac, 15 s to 7 min of Wi-Fi). Use it only on the console, never over SSH or Tailscale, because the link goes down with it.

Not chosen: leaving `awdl0` always present (upstream default for an always-on machine) because it keeps a station slot taken; ending windows with `awdl=0` because of the documented firmware hang.

### Test plan (run only after the Wi-Fi is back and the fix is deployed; the user is at the M3)

Pass rules: after each step, wld0 is `UP` and associated, the router still pings, no new `brcmf` error, no `-16`, no `-52`.

| Step | What | Checks |
|---|---|---|
| T0 | baseline: no `awdl0`, receiver stopped, 10 minutes idle | `ping` router every 5 s, `iw dev wld0 link`, `journalctl -k -f \| grep -E "brcmf\|awdl"` running in a second terminal |
| T1 | 1 hour of normal Wi-Fi use with AirDrop idle (no window, no `awdl0`) | no drops, no `-16`; signal and throughput steady |
| T2 | press AirDrop on; wait for the window | `ip link` shows `awdl0`; ping loss under 5 percent during the window; wld0 stays associated |
| T3 | 5 transfers: iPhone to M3 (2), Mac to M3 (2), M3 to iPhone (1), with the notification shown for each | file correct after each; wld0 up after each; router ping still answers |
| T4 | press AirDrop off | receiver stopped; window closed; wld0 up; no firmware error for 10 minutes |
| T5 | start a second Wi-Fi action while `awdl0` exists (toggle Wi-Fi from the tray) | the Wi-Fi off and on destroys the AWDL vif per upstream notes; run last, only on the console with the user present, and expect to need a driver reload afterwards |
| T6a | on the console, before any AirDrop use in the boot (no `awdl0`): press the suspend key with the USB-C display attached (the refused-suspend case) | wld0 reconnects within 30 s; `p2p-dev-wld0` is created without `-16`; this is the baseline for the log chain; the coordinator's 12:33 radio restart already shows the P2P add can fail without `awdl0` |
| T6b | only after T6a passes and the measures (a) and (b) are deployed: create `awdl0` (T2), then press the suspend key again | with (a): the key press is blocked and Wi-Fi is untouched; with (b) and no inhibitor: no `-16` and wld0 reconnects |

Stop at the first failure, save `journalctl -k -b` to the notes folder, and do not continue.
