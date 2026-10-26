#!/usr/bin/env bash
# Make $ESP_M1N1/boot.bin a copy of boot.bin.<stage> (stock, stageC, ...).
# Usage: sudo install/use-bootbin.sh <stage>
. "$(dirname "$0")/lib.sh"
need_root
[ $# -eq 1 ] || { echo "usage: $0 <stage>" >&2; exit 1; }

SRCBIN="$ESP_M1N1/boot.bin.$1"
DST="$ESP_M1N1/boot.bin"
[ -f "$SRCBIN" ] || { echo "No $SRCBIN" >&2; exit 1; }
[ -f "$ESP_M1N1/boot.bin.stock" ] || { echo "No boot.bin.stock backup; refusing" >&2; exit 1; }

cp -f "$SRCBIN" "$DST.new"
sync
mv -f "$DST.new" "$DST"
sync
echo "boot.bin is now $1:"
sha256sum "$DST" "$SRCBIN"
