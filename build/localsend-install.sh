#!/usr/bin/env bash
# LocalSend on the M3 (Fedora Asahi Remix, aarch64): the official GitHub release tarball, user install, no root.
# Pinned: github.com/localsend/localsend v1.18.2. The sha256 is the digest GitHub shows for the asset (read 2026-10-30).
# Runs on the M3. Each step is its own subcommand. Nothing runs without a subcommand.
#   fetch    download the tarball into $DL and check size and sha256 (no install)
#   list     show the tarball contents (read-only)
#   install  extract to ~/.local/opt, link the binary, write the .desktop entry, check missing libraries
#   status   read-only
#   undo     remove everything this script wrote (the downloaded tarball too)
# The firewall port (TCP and UDP 53317) is a separate sudo step: see docs/features/airdrop-options.md.
set -u
VER=1.18.2
NAME=LocalSend-$VER-linux-arm-64.tar.gz
URL=https://github.com/localsend/localsend/releases/download/v$VER/$NAME
SIZE=32354331
SHA=dd61f74f1ce3f4e25aca41cd3ce650d6a99353d7baba81a8139807275b88e606
DL=${LOCALSEND_DL:-$HOME/localsend-dl}
OPT=$HOME/.local/opt/localsend-$VER
BIN=$HOME/.local/bin/localsend
DESK=$HOME/.local/share/applications/localsend.desktop
ok()  { echo "ok:   $*"; }
bad() { echo "FAIL: $*"; exit 1; }

check() {
	[ -f "$DL/$NAME" ] || bad "no $DL/$NAME (run fetch)"
	[ "$(stat -c %s "$DL/$NAME")" = "$SIZE" ] || bad "size differs from $SIZE"
	[ "$(sha256sum "$DL/$NAME" | cut -d' ' -f1)" = "$SHA" ] || bad "sha256 differs from the pinned value"
}

case "${1:-}" in
fetch)
	mkdir -p "$DL"
	[ -f "$DL/$NAME" ] || curl -fL --proto '=https' --tlsv1.2 -o "$DL/$NAME" "$URL" || bad "download"
	check && ok "$NAME, $SIZE bytes, sha256 matches"
	;;
list)
	check; tar -tzf "$DL/$NAME" | head -60
	;;
install)
	check
	# Refuse paths that leave the target folder.
	tar -tzf "$DL/$NAME" | grep -E '(^/|(^|/)\.\.(/|$))' && bad "unsafe path in the tarball"
	mkdir -p "$OPT" "$(dirname "$BIN")" "$(dirname "$DESK")"
	tar -xzf "$DL/$NAME" -C "$OPT" || bad "extract"
	exe=$(find "$OPT" -maxdepth 2 -type f -name localsend_app | head -1)
	[ -n "$exe" ] || bad "no localsend_app in $OPT (check: list)"
	chmod +x "$exe"
	ln -sfn "$exe" "$BIN"
	icon=$(find "$OPT" -maxdepth 4 -type f \( -name 'localsend*.png' -o -name 'localsend*.svg' \) | head -1)
	cat > "$DESK" <<DESKTOP
[Desktop Entry]
Type=Application
Name=LocalSend
Comment=Share files with nearby devices on the same Wi-Fi
Exec=$BIN
Icon=${icon:-emblem-shared}
Terminal=false
Categories=Network;FileTransfer;
StartupWMClass=localsend_app
DESKTOP
	kbuildsycoca6 >/dev/null 2>&1 || true
	missing=$(ldd "$exe" 2>&1 | grep 'not found' || true)
	if [ -n "$missing" ]; then
		echo "missing libraries:"; echo "$missing"
		bad "install the missing libraries (dnf, needs root) or use the Flatpak"
	fi
	ok "installed: $exe; no missing libraries"
	;;
status)
	ls -la "$DL/$NAME" 2>&1; ls -la "$BIN" "$DESK" 2>&1; pgrep -a localsend_app || echo "not running"
	ss -tulpn 2>/dev/null | grep 53317 || echo "nothing listens on 53317"
	;;
undo)
	pkill -x localsend_app 2>/dev/null
	rm -rf "$OPT" "$BIN" "$DESK" "$DL"
	rm -rf "$HOME/.local/share/org.localsend.localsend_app" 2>/dev/null
	ok "removed (settings under ~/.local/share/org.localsend.localsend_app removed if present)"
	;;
*)
	sed -n '2,10p' "$0"
	;;
esac
