#!/usr/bin/env bash
# GPU clock test boot, one time only: adds a boot entry "7.2.11-m3gpu+ tgt_util 50" (a copy of the
# stage O entry with asahi.g15_perf_tgt_util=50) and selects it for the NEXT boot only
# (grub2-reboot sets next_entry; GRUB clears it when it boots, so the boot after is the normal
# saved entry). Does not reboot. Run with sudo. Rollback: gpu-rollback.sh.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }
KREL=7.2.11-m3gpu+
WANT=c6224575f2a72dd2fa140ea6a7c93dff6b052b6dea2dc61bf82f9c8654d2ca91
ARG=asahi.g15_perf_tgt_util=50
E=/boot/loader/entries
SRC=$(ls "$E"/*-"$KREL".conf)
ID=$(basename "$SRC" .conf)-tgt50
DST=$E/$ID.conf

grep -q "apple,j516s" /proc/device-tree/compatible || { echo "Not a J516S" >&2; exit 1; }
[ "$(sha256sum "/boot/vmlinuz-$KREL" | cut -d' ' -f1)" = "$WANT" ] || { echo "Installed image is not stage O" >&2; exit 1; }
strings "/boot/vmlinuz-$KREL" | grep -c g15_perf_tgt_util > /dev/null || { echo "Parameter missing in the image" >&2; exit 1; }
grep -q '^options ' "$SRC" || { echo "No options line in $SRC" >&2; exit 1; }

sed -e "s/^title .*/& tgt_util 50 (one-time GPU clock test)/" -e "s/^options .*/& $ARG/" "$SRC" > "$DST"
chmod --reference="$SRC" "$DST"
grep -q "$ARG" "$DST" || { echo "Argument not in $DST" >&2; exit 1; }
grub2-reboot "$ID"
grub2-editenv list | grep -q "^next_entry=$ID$" || { echo "next_entry not set" >&2; exit 1; }
echo "entry: $DST"
grep -E '^(title|linux|options)' "$DST"
grub2-editenv list
echo "GPU_BOOT_SET (next boot only; reboot is a separate step)"
