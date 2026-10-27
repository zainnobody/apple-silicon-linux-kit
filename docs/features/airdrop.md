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

## Surviving a reboot (NOT applied)

A reboot removes `awdl0`, the firewalld zone binding and the receiver. Nothing here is applied; each item needs the user's go.

| Item | Why it is lost | Proposed fix |
|---|---|---|
| `awdl0` | the interface is created by `awdl-up`, which runs once | install `packaging/awdl0.service` to `/etc/systemd/system/` and `systemctl enable` it; it creates `awdl0` idle, no window |
| firewalld zone for `awdl0` and TCP 8771 | runtime only (`--change-interface`, `--add-port` without `--permanent`) | `firewall-cmd --permanent --zone=work --add-port=8771/tcp`, and a drop-in `ExecStartPost=/usr/bin/firewall-cmd --zone=work --change-interface=awdl0` on `awdl0.service` (NetworkManager does not manage `awdl0`, so a permanent interface binding is not reapplied when it reappears) |
| receiver | started by hand in a retry loop | a systemd user unit for `airdrop-serve.py` with `Restart=always`; it must wait for the link-local address on `awdl0` |
| Wi-Fi permanent MAC | NetworkManager profile setting, already permanent | nothing to do |

Windows stay a manual step: they need root, and `sudo` needs a password in this setup. The upstream project uses a polkit policy (`packaging/org.omarchy.omdrop.policy`) so that a local desktop session can open a window without a password. That policy is not installed here.
