# File sharing between the M3 and an iPhone or Mac: options

Date 2026-10-30. Choose one or more. Nothing here is installed or started by this page. Details of the AirDrop build are in `airdrop.md`.

## Short answer

- Only AirDrop shows the M3 in the iPhone share sheet with no app on the phone. It is built and tested. It is OFF until the Wi-Fi tests T6a and T6b pass.
- LocalSend is the best second option. It needs an app on each device, but it uses the normal Wi-Fi and cannot touch the firmware that AirDrop uses.
- Recommendation: finish AirDrop (it is what you asked for), and add LocalSend as the safe fallback that is always on.

## Overview

"Works" below means: proven on the M3 in this project (tested), or taken from public documentation (docs only, not tested here).

| Option | iPhone to M3 | M3 to iPhone | Mac to M3 | M3 to Mac | Wi-Fi risk |
|---|---|---|---|---|---|
| AirDrop (OpenDrop on awdl0) | works (tested) | works (tested) | works (tested) | works in the tool but blocked by the standing rule (nothing goes from the M3 to this Mac; the Mac refuses the fixed port the tool uses) | medium until T6 passes |
| LocalSend | works (docs only) | works (docs only) | works (docs only) | allowed by the app; blocked by the same standing rule | none |
| KDE Connect | works, with iOS limits (docs only) | works, with iOS limits (docs only) | no Mac client in the standard set | not applicable | none |
| Tailscale Taildrop | works (docs only) | works (docs only) | works (docs only) | allowed by the tool; blocked by the standing rule | none |
| Web drop page | works in Safari (design only) | works in Safari (design only) | works in a browser (design only) | allowed; blocked by the standing rule | none |

You said you do not want Taildrop. It stays in the table only so the choice is complete.

## 1. AirDrop (OpenDrop on the built-in Broadcom chip)

What it is: the real AirDrop. The M3 shows in the iPhone and Mac share sheet. The radio part is the firmware's own AWDL engine, shown as `awdl0`.

| Item | State |
|---|---|
| Receive modes | **Off** (default, no `awdl0` use). **Everyone for 10 Minutes** (a window opened by the AirDrop on button, 10 minutes by default). **Contacts Only is not possible**: it needs an identity that Apple signs. The iPhone refuses the M3 in that mode |
| Send | Right-click a file in Dolphin, then "Send via AirDrop". It opens a window if none is open, lists devices, asks which one, sends. Built, not yet run on the M3 |
| Tray or panel toggle | "AirDrop on" and "AirDrop off" launchers. Pin them to the panel. A tray widget is the design session's work |
| Notification on receive | Built. A user service follows the receiver log and runs `notify-send`. A test showed no pop-up on the M3 screen. Open question: why |
| Received files | `~/Downloads` |
| Needs on the phone | nothing |
| Needs on the M3 | the root part (done 2026-10-27), the user part and the buttons (not yet), no extra download |
| Needs sudo | one sudo window for the firewall binding (see `airdrop.md`, "One session at the M3") |

Limits you will notice:

- The iPhone must be on "Everyone for 10 Minutes" and the share sheet must be open. iOS turns this off by itself after 10 minutes.
- During a window the radio leaves the home channel. Wi-Fi gets slower for that time.
- A few tries are normal. The iPhone listens in bursts.
- After the first window in a boot, `awdl0` stays until reboot. The design blocks sleep and the suspend key while it exists (see risk).

Wi-Fi risk: on 2026-10-27 the Wi-Fi dropped after a suspend key press. The proven cause is a refused suspend (USB-C display attached) followed by `wpa_supplicant` failing to re-create its P2P device. `awdl0` was present then, and it is a likely contributor, but a later test without `awdl0` gave a similar P2P error. Tests T6a and T6b decide. Recovery from a wedged firmware needs the console.

Recommendation: yes, finish it. Keep it off by default. Use it for iPhone and Mac transfers you want in the share sheet.

## 2. LocalSend

Open source app for Linux, macOS, iOS, Android and Windows. Devices on the same Wi-Fi find each other and send files over HTTPS. No cloud, no account. It does not use AWDL, so it cannot affect the firmware.

| Item | State |
|---|---|
| Receive modes | the app receives while it runs; "Quick Save" settings choose ask or auto-accept; no 10-minute limit |
| Send from the M3 | the app window; a Dolphin right-click entry is possible but not built |
| Tray toggle | the Linux app has a tray icon (docs only) |
| Notifications | the app shows them (docs only, not tested here) |
| Needs on the phone | the LocalSend app from the App Store |
| Needs on the Mac | the LocalSend app, or none if you only send from the phone |
| Needs on the M3 | one package download: the Flatpak (`org.localsend.localsend_app`) or a build from GitHub. Fedora has no stock RPM. Open TCP and UDP 53317 in firewalld |
| Needs sudo | the firewall port; the Flatpak itself can be a user install |
| Wi-Fi risk | none. Both devices must be on the same network. A VPN or guest Wi-Fi with client isolation breaks discovery |
| Not in the share sheet as "M3" | the iPhone uses the LocalSend share extension instead |

Recommendation: yes, as the fallback. It works when AirDrop is off and has no 10-minute timer.

## 3. KDE Connect

Pairs a phone with a Linux desktop (clipboard, notifications, files).

- The iPhone app exists but has fewer features than the Android one (docs only).
- File transfer from the iPhone works. Files land in the app's own folder in the Files app, not in Photos or Downloads. The app must stay open and the screen unlocked during a transfer. There are no iOS notifications.
- Sending from the M3 to the iPhone is available in the desktop app. Reports of problems exist (docs only).
- No macOS client is in the standard package set, so it does not serve the Mac.
- Needs on the M3: `kdeconnect-kde` is a Fedora package (a dnf install). It is probably already part of the KDE desktop. Check with `rpm -q kdeconnect-kde` (read-only).
- Wi-Fi risk: none.

Recommendation: no. LocalSend does the same job with fewer iOS limits and also covers the Mac.

## 4. Tailscale Taildrop

The M3 already runs Tailscale (the same network you use for SSH). Taildrop sends files between your own devices through it, with `tailscale file cp` and `tailscale file get` on Linux, and the Tailscale app share sheet on iPhone and Mac (docs only, not tested here).

- Needs on the phone: the Tailscale app, signed in to the same tailnet.
- Needs on the M3: nothing new. Files wait until `tailscale file get` runs, so a small user service is needed for a hands-off receive.
- Works over any network, also away from home. Traffic is encrypted by Tailscale.
- Wi-Fi risk: none.
- You said you do not want it.

Recommendation: not now. Keep it as the way to send files when you are not on the same Wi-Fi.

## 5. A simple web drop page

A tiny web server on the M3 (Python standard library, no download). Open the page in Safari on the iPhone or in a browser on the Mac. Upload sends a file to `~/Downloads`. Download lists a shared folder.

- Needs on the phone: nothing, only a browser.
- Needs on the M3: a small user service, a firewall port, and a choice of network. Bind it to the Tailscale address only, so no one on the local Wi-Fi reaches it.
- No share sheet entry, no notification unless built. iPhone uploads go through the file picker.
- Wi-Fi risk: none.
- Status: design only. Nothing was built.

Recommendation: only if you want a zero-install option for guests. Otherwise LocalSend is better.

## What I need from you

| Decision | Why |
|---|---|
| Keep AirDrop and finish it (yes or no) | the steps are in `airdrop.md`, "One session at the M3" |
| Add LocalSend (yes or no) | one package download and one firewall port |
| Move the router to channel 44 or 149 (yes or no, optional) | stops AWDL from hopping channels; less Wi-Fi slowdown during a window |
| Accept sleep blocked after the first AirDrop window until reboot (yes or no) | stopgap until T6a and T6b show it is not needed |

## Decision 2026-10-30 and the plan

The user chose: finish AirDrop, and add LocalSend. Router channel change: skipped for now. Taildrop, KDE Connect and the web page: not built.

### LocalSend install (user install, no root)

Read on 2026-10-30 from Flathub and GitHub. Nothing was downloaded to the M3.

| Item | Value |
|---|---|
| Source | Flathub, app id `org.localsend.localsend_app`, stable 1.18.2, licence Apache-2.0, builds for `x86_64` and `aarch64` |
| App size | about 23 MB download, 58 MB installed (the Flathub summary shows the `x86_64` build; the `aarch64` figure was not read) |
| Runtime | `org.freedesktop.Platform` 26.08: about 283 MB download, 724 MB installed. `org.freedesktop.Platform.GL.default` 26.08: about 150 MB download, 470 MB installed. Same `x86_64` caveat. Each is skipped if the M3 already has it |
| Worst case | about 456 MB download, about 1.2 GB on disk. M3 free space not checked (the M3 was offline) |
| Sandbox | network, Wayland, GPU device, the Downloads folder only. Received files go to `~/Downloads` |
| Command | `flatpak --user remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo`, then `flatpak --user install flathub org.localsend.localsend_app` |
| Undo | `flatpak --user uninstall --delete-data org.localsend.localsend_app` |
| Light alternative | the arm64 tarball `LocalSend-1.18.2-linux-arm-64.tar.gz` from the project's GitHub release, 32 MB, extract to `~/.local/opt`. No sandbox, no runtime download, but it needs system GTK3 libraries (not checked) |
| Untested risk | the Flatpak runtime carries its own Mesa, which may not support the M3 GPU. A small app then runs with software drawing, or does not draw. Test after install. The tarball uses the system Mesa |

Firewall: LocalSend needs TCP and UDP 53317. The Wi-Fi interface is in zone `FedoraWorkstation`. The step queries the zone first. If 53317 is already open there, nothing is added. If it is closed, add TCP and UDP 53317 to that zone only (permanent), so the Tailscale interface and `awdl0` (zone `work`) are not changed. The zone ports were not re-read on 2026-10-30 because the M3 was offline.

### The user's list at the M3

1. Run the one sudo window (below).
2. Install the LocalSend app on the iPhone (App Store) and on the Mac if you want it there.
3. Press the suspend key on the console (test T6a).
4. Click AirDrop on, run the file tests, click AirDrop off.
5. Open LocalSend on the M3 and on the iPhone, on the same Wi-Fi, and send one file each way.

### The one sudo window (two commands)

```bash
sudo ~/omdrop-test/airdrop-persist.sh root
zone=$(firewall-cmd --get-zone-of-interface=wld0); firewall-cmd --zone="$zone" --query-port=53317/tcp; firewall-cmd --zone="$zone" --query-port=53317/udp
```

Only if a query prints `no`:

```bash
sudo firewall-cmd --permanent --zone="$zone" --add-port=53317/tcp --add-port=53317/udp && sudo firewall-cmd --reload
```

Undo: `sudo firewall-cmd --permanent --zone="$zone" --remove-port=53317/tcp --remove-port=53317/udp && sudo firewall-cmd --reload` and `sudo ~/omdrop-test/airdrop-persist.sh remove`. The Flatpak install needs no sudo.
