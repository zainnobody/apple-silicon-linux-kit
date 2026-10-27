#!/usr/bin/env bash
# Make /boot/efi/m1n1/boot.bin a copy of boot.bin.<stage> (stock, stageC, ...).
# Usage: sudo use-bootbin.sh <stage>
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }
SRC="/boot/efi/m1n1/boot.bin.$1"
DST=/boot/efi/m1n1/boot.bin
[ -f "$SRC" ] || { echo "No $SRC" >&2; exit 1; }
[ -f /boot/efi/m1n1/boot.bin.stock ] || { echo "No boot.bin.stock backup; refusing" >&2; exit 1; }

cp -f "$SRC" "$DST.new"
sync
mv -f "$DST.new" "$DST"
sync
echo "boot.bin is now $1:"
sha256sum "$DST" "$SRC"
