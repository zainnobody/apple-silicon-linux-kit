# Desktop design: a flat macOS look for the M3

Status (2026-10-30): status pages and the AirDrop look are done. The desktop part is staged and waits for a user login on the M3.
Style: macOS Sonoma and Sequoia. Flat. No blur, no see-through panels, no glass, no shadow on the pages.

## Part 1: KDE Plasma desktop (Fedora Asahi Remix 44, Plasma 6.7.5, Wayland)

Scripts: `distro-pack/desktop/` (see its README). Everything works at user level. No root, no package, no login screen change.

| Item | Plan | State |
|---|---|---|
| Backup | `~/desktop-design-backups/20261030-025513-00-baseline.tar.gz` and its undo script | Done |
| Themes | WhiteSur-kde `cf4df59c`, WhiteSur-icon-theme `73d8040d`, WhiteSur-cursors `e190baf6` (GPL-3.0, user approved the download) | Installed in `~/.local/share`, not yet active |
| Fonts | Adwaita Sans (Inter-based) and Hack. Both are on Fedora already. No download. | Staged |
| Window style | Opaque WhiteSur decoration, close, minimize and zoom on the left | Staged |
| Top bar and dock | 30 px top bar with launcher, global menu, tray and clock. Floating centred dock, icons only, Trash at the end. | Staged, needs a session |
| Search | Meta+Space opens KRunner in the middle of the screen | Staged |
| Overview | Overview effect kept, background blur off. Three-finger swipe is not checked yet. | Needs a session |
| Dolphin | Details list, icon-only toolbar, no menu bar in the window | Staged |
| Konsole | Basic (light) and Pro (dark) looks, Hack 11 pt, block cursor | Staged |
| Notifications | Banners at the top right | Staged |
| Light and dark | `m3-appearance light` or `m3-appearance dark` | Staged |

The M3 sat at the login screen all day, so no screenshot exists yet. After the user logs in, the "before" screenshot comes first.
Then the scripts run one stage at a time. After each stage the "after" screenshot goes into `docs/features/desktop-design/`.

Safety rules kept: no blur, no wobbly windows, no magic lamp, no reboot, no change to kernel, GPU or Mesa.
If kwin or plasmashell crashes, run the undo script of the last stage from SSH.

Not possible without root (ask first): remap Cmd to Ctrl for shortcuts (keyd or kinto), change the login screen theme.

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
  The scripts use the old theme icon when the new one is missing.
- Not tested on the M3 yet (no desktop session).
