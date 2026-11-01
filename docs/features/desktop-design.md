# Desktop design: a flat macOS look for the M3

Status (2026-10-31): all three parts are done and tested on the M3. The user confirmed Meta+Space and the Overview swipe. Limits are listed at the end.
Style: macOS Sonoma and Sequoia. Flat. No blur, no see-through panels, no glass, no shadow on the pages.

## Part 1: KDE Plasma desktop (Fedora Asahi Remix 44, Plasma 6.7.5, Wayland)

Scripts: `distro-pack/desktop/` (see its README). Everything works at user level. No root, no package, no login screen change, no reboot.
Pictures are in `docs/features/desktop-design/` (before and after, scaled to 1728 px wide).

| Item | Result | Picture |
|---|---|---|
| Backups | One dated tarball and one undo script per stage in `~/desktop-design-backups/` on the M3 | none |
| Themes | WhiteSur-kde `cf4df59c`, WhiteSur-icon-theme `73d8040d`, WhiteSur-cursors `e190baf6` (GPL-3.0, the user approved the download). Only flat parts are installed. No upstream script was run. | none |
| Fonts | Adwaita Sans (Inter-based) and Hack. Both are on Fedora already. No download. | all |
| Window style | Opaque WhiteSur decoration. Close, minimize and zoom on the left, title in the middle. | after-apps |
| Top bar | 30 px bar: launcher, global menu (File, Edit, ...), tray, clock. The menu shows when an app has focus. | after-desktop, after-apps |
| Dock | Floating, centred, icons only, Trash at the end. It joins the screen edge while a window is maximized. | after-desktop |
| Search | Meta+Space opens KRunner in the middle of the screen (binding checked in kglobalaccel, key press confirmed by the user). | after-krunner |
| Overview | Overview works (toggled over D-Bus, no crash). Blur is off and unloaded. | overview |
| Dolphin | Details list, icon-only toolbar, menu in the top bar | before-apps, after-apps |
| Konsole | Basic (light) and Pro (dark) looks, Hack 11 pt, block cursor | before-apps, after-apps, after-dark |
| Notifications | Banners at the top right. AirDrop banner with the flat icon. | after-airdrop-notice |
| Light and dark | `m3-appearance light` or `m3-appearance dark`. Both work. Apps need a restart to change. | after-dark |

How to undo: run `~/desktop-design-backups/<date>-<stage>-undo.sh` of the last stage over SSH, then log in again.
`undo-10-themes.sh` removes the downloaded themes. The baseline backup `20261030-025513-00-baseline` holds the state before any change.

Checks made on 2026-10-31 (uptime 5 to 9 min, no charger, load below 0.7):
plasmashell and kwin kept running through every stage. No kwin crash. Blur, contrast, wobbly windows and magic lamp are not loaded.
The blur effect needed `unloadEffect` over D-Bus, because a config reload did not unload it. Stage 40 now does this.

Limits and open items:

- The user tried Meta+Space and the swipe gesture on the M3 on 2026-10-31 and reported "Works". The user did not say how many fingers
  the swipe needs. KWin binds its own swipe gesture to Overview. Meta+W also opens Overview.
- The top bar and dock stay dark in light mode. The solid WhiteSur Plasma theme has a dark panel. A light bar needs a custom theme.
- The Konsole toolbar stays on. Konsole ignored the hidden-toolbar setting. Use Settings, Show Toolbars, or leave it.
- Apps started from a plain SSH shell lack the Qt platform theme and show wrong colours. `session-shot.sh` starts them with the session environment.
- Dolphin has no column view. Cmd to Ctrl key remap needs root (keyd or kinto). The login screen is not changed.

## Part 4: input like macOS (applied 2026-10-31 17:01)

The user asked for a pointer, scroll and keyboard feel like macOS. Stage 70 (`distro-pack/desktop/70-input.sh`) wrote the settings to
`~/.config/kcminputrc` and `~/.config/kdeglobals`, so they survive a reboot. The tool `m3-input` shows and tunes the live values.
Backup and undo: `~/desktop-design-backups/20261031-170155-70-input` (tarball and `-undo.sh`).

Reference values were read on a Mac with an M5 chip (macOS 26.7, all defaults) with `ioreg -c IOHIDSystem` on 2026-10-31:

| macOS default | Value | Linux setting |
|---|---|---|
| Delay until key repeat | 500 ms | `RepeatDelay=500` in kcminputrc |
| Key repeat interval | 83 ms (12 per second) | `RepeatRate=12` |
| Double-click time | 500 ms | `DoubleClickInterval=500`, and double click to open files (`SingleClick=false`) |
| Tracking speed | 0.6875 of the slider, accelerated | adaptive profile, `PointerAcceleration=0.6` (the value already on the M3) |
| Tap to click | off on a Mac, but the user wants it | `TapToClick=true`, tap and drag off, drag lock off |
| Secondary click | two-finger click or tap | click method "click finger", two-finger tap is a right click |
| Scroll direction | natural | `NaturalScroll=true` for the trackpad. A mouse stays off. |
| Scroll speed | accelerated | `ScrollFactor=1.5` as a start. This is a feel setting. Tune it: `m3-input scroll 1.2`. |
| Palm rejection | on | `DisableWhileTyping=true` |
| Mouse | adaptive | `m3-input mouse` sets natural scrolling off and speed 0.3 for each mouse found |

Cursor size stays at the current value. The WhiteSur cursor at size 24 already looks like the macOS pointer at this screen scale.

Checked on the M3 (2026-10-31 17:02): all 14 touchpad properties exist in KWin D-Bus and take the values above. KWin reloaded the
config file by itself after the write (tap to click and scroll factor changed without a restart), so the key names are right and the
values persist. Key repeat 500 ms and 12 per second are in the file. The key press feel and the scroll feel are not measured. They
need a person at the keyboard and trackpad. The scroll factor 1.5 is a first guess.

Options that need the user, root or both:

- Cmd key as Ctrl (copy, paste, save): needs the keyd package and a root file. Draft: `distro-pack/desktop/root-options/keyd-cmd-as-ctrl.conf`. Not tested.
- Two-finger swipe between pages: KDE has no system setting. Each app decides (Firefox and Chromium have their own options).
- Three-finger drag (a Mac accessibility option) is off, as on a Mac by default.

## Part 2: status pages

`status/BOARD.html`, `status/COMPARE.html` and `agx-linux-kit/TEST-LOG.html` use one flat Apple style.

- Shared tokens and base rules: `status/apple.css`. The copy `agx-linux-kit/log/apple.css` must be the same file.
  `python3 -I status/build.py` warns when the copy differs.
- Light and dark follow the system setting. The system font stack is used (SF Pro where it exists, else Inter, Adwaita Sans, Cantarell).
  No web font is loaded, so the pages work offline.
- All text and surface pairs are at least 4.5 to 1 (checked with the contrast script). Focus rings are 3 px.
- Checked at 375 px: no sideways scroll. Filters and detail panel work with the keyboard and the mouse.
- The data files `status/data/*.json` are not changed. `python3 -I status/build.py` and `python3 -I agx-linux-kit/log/build-log.py` still work.
  `build.py` also refreshes the shared style block in `COMPARE.html`, which stays a hand-edited page.

## Part 3: AirDrop look

Look only. The AirDrop session owns how AirDrop works.

- Notification text is short and plain: "AirDrop is on", "AirDrop is off", "File received", "Sent", "Not sent", "No device found".
- The device picker has the title "AirDrop" and the text "Choose a device".
- New flat icon `build/airdrop-ui/m3-airdrop.svg` (own drawing, not the Apple logo). Install it with `build/airdrop-ui/install-icon.sh`.
  The scripts pass the icon as a file path (a name did not resolve in the notification). They use the old theme icon when the file is missing.
- Tested on the M3: a banner with the new text and icon (`after-airdrop-notice.png`). The AirDrop scripts themselves were not run, because
  they need the root part that the AirDrop session owns. They pass `bash -n`.

## Part 5: lock screen

Status 2026-11-01: built and checked in test windows. Not installed yet. No real lock was done with it.

| | Before (stock Breeze) | After (flat) |
|---|---|---|
| Screenshot | `desktop-design/before-lockscreen.png` | `desktop-design/after-lockscreen.png` |
| Wallpaper | Blurred picture (blur radius 50) | One flat colour, `#0b3d91` |
| Clock | Shadow behind the digits | No shadow |
| Fingerprint | No hint | Hint: "Touch ID: rest your finger on the power key" |
| Fade in and out | Wallpaper blur and colour shader | Opacity only, 100 ms or less |

Text contrast: light text `#eff0f1` on `#0b3d91` is 8.8:1. The limit for normal text is 4.5:1.

- **How it works.** In Plasma 6.7 the lock screen QML is part of the shell package `org.kde.plasma.desktop`. Script `distro-pack/desktop/80-lockscreen.sh install`
  puts a user copy of that package in `~/.local/share/plasma/shells`. Only the `lockscreen` folder differs. Plasma takes the user copy first.
- **Changes in the QML.** The `Qt5Compat.GraphicalEffects` import, the blur wallpaper fader and the clock shadow are gone. A new `FlatFader.qml` shows the wallpaper as it is.
  The hint label sits under the password field.
- **What it does not touch.** PAM (`kde`, `kde-fingerprint`), fprintd, the apple_sep module, powerdevil and logind stay as they are.
  Fingerprint unlock still runs in parallel through PAM. The hint is only text.
- **Safety.** Every change makes a backup in `~/desktop-design-backups/`. A guard script in `~/.config/plasma-workspace/env` removes the copy at login when
  the system shell package has changed (a Plasma update). If the QML does not load, Plasma uses its built-in locker. `80-lockscreen.sh remove` restores the stock lock screen.
- **How it was tested.** `80-lockscreen.sh test stock|flat` runs `kscreenlocker_greet --testing` in a window, with `PLASMA_DEFAULT_SHELL` set to a test package.
  The test package keeps the password prompt on screen. This Plasma version has no `--theme` option. A locked session gives blank screenshots, so the session must be unlocked.
- **Login screen.** The Plasma Login Manager is not changed. `distro-pack/desktop/root-options/plasmalogin-flat.sh` sets the same flat colour. It needs root. It is a draft and is not tested.
  The login greeter QML is compiled into the program, so the pack cannot restyle more than the wallpaper.
