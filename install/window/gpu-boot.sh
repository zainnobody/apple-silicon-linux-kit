#!/usr/bin/env bash
# GPU clock test boot, one time only: adds a boot entry (a copy of the 7.2.11-m3gpu+ entry with ARG,
# default asahi.g15_perf_tgt_util=50 on the stage O image WANT) and selects it for the NEXT boot only
# (grub2-reboot sets next_entry; GRUB clears it when it boots, so the boot after is the normal
# saved entry). Does not reboot. Run with sudo. Rollback: gpu-rollback.sh.
# Stage P (docs/gpu-boost-test-plan.md): sudo ARG=asahi.g15_perf_boost_min=50 WANT=e576affa234a19d3f930bc288206e28ddb51fc7f9b69058bc4ebc3a480df5ed0 TAG=p1 gpu-boot.sh
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }
KREL=7.2.11-m3gpu+
WANT=${WANT:-c6224575f2a72dd2fa140ea6a7c93dff6b052b6dea2dc61bf82f9c8654d2ca91}
ARG=${ARG:-asahi.g15_perf_tgt_util=50}
TAG=${TAG:-tgt50}
E=/boot/loader/entries
SRC=$(ls "$E"/*-"$KREL".conf)
ID=$(basename "$SRC" .conf)-$TAG
DST=$E/$ID.conf

grep -q "apple,j516s" /proc/device-tree/compatible || { echo "Not a J516S" >&2; exit 1; }
[ "$(sha256sum "/boot/vmlinuz-$KREL" | cut -d' ' -f1)" = "$WANT" ] || { echo "Installed image is not $WANT" >&2; exit 1; }
for a in $ARG; do
	case $a in asahi.g15_perf_*=[0-9]*) ;; *) echo "ARG must be asahi.g15_perf_*=<number> settings" >&2; exit 1 ;; esac
	strings "/boot/vmlinuz-$KREL" | grep -c "$(echo "${a%%=*}" | sed "s/^asahi\.//")" > /dev/null || { echo "Parameter ${a%%=*} missing in the image" >&2; exit 1; }
done
grep -q '^options ' "$SRC" || { echo "No options line in $SRC" >&2; exit 1; }

sed -e "s/^title .*/& $TAG (one-time GPU clock test)/" -e "s/^options .*/& $ARG/" "$SRC" > "$DST"
chmod --reference="$SRC" "$DST"
grep -q "$ARG" "$DST" || { echo "Argument not in $DST" >&2; exit 1; }
grub2-reboot "$ID"
grub2-editenv list | grep -q "^next_entry=$ID$" || { echo "next_entry not set" >&2; exit 1; }
echo "entry: $DST"
grep -E '^(title|linux|options)' "$DST"
grub2-editenv list
echo "GPU_BOOT_SET (next boot only; reboot is a separate step)"
