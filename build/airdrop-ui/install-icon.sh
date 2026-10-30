#!/usr/bin/env bash
# Install the AirDrop icon for this user. No root. Undo: rm ~/.local/share/icons/hicolor/scalable/apps/m3-airdrop.svg
set -eu
here=$(cd "$(dirname "$0")" && pwd)
dst="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
mkdir -p "$dst"
install -m 0644 "$here/m3-airdrop.svg" "$dst/m3-airdrop.svg"
gtk-update-icon-cache -q -f -t "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" 2>/dev/null || true
echo "installed $dst/m3-airdrop.svg"
