#!/usr/bin/env bash
# Stage P: install the 7.2.11-m3gpu+ build with patches/g15-perf-boost-base.patch (module parameters
# asahi.g15_perf_boost_min, g15_perf_boost_step and g15_perf_base_pstate, default 0: no change) on top
# of the stage O patches (recovery drain fix, tgt_util). Plan: docs/gpu-boost-test-plan.md. No boot
# argument change. Does not reboot. Run with sudo. Mesa is not changed.
# The GPU driver is built into the image (CONFIG_DRM_ASAHI=y).
# Undo: cp -a <backup>/boot files back to /boot, rsync -a --delete <backup>/modules/ to the modules
#       folder, depmod -a 7.2.11-m3gpu+, dracut -f; or roll back the snapper snapshot.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }
KREL=7.2.11-m3gpu+
STAGE=/home/user/m3gpu/out/kernel-$KREL-boost
WANT=e576affa234a19d3f930bc288206e28ddb51fc7f9b69058bc4ebc3a480df5ed0
MODS=/usr/lib/modules/$KREL
BACKUP="/root/m3gpu-backup/$(date +%Y%m%d-%H%M%S)-pre-boost"

# Checks before any change.
grep -q "apple,j516s" /proc/device-tree/compatible || { echo "Not a J516S" >&2; exit 1; }
[ "$(sha256sum "$STAGE/boot/vmlinuz-$KREL" | cut -d' ' -f1)" = "$WANT" ] || { echo "Staged image hash differs" >&2; exit 1; }
[ "$(strings "$STAGE/boot/vmlinuz-$KREL" | grep -c 'recovery step')" -ge 4 ] || { echo "Recovery fix missing in the image" >&2; exit 1; }
# grep -c reads all input: grep -q would end strings with SIGPIPE under pipefail.
strings "$STAGE/boot/vmlinuz-$KREL" | grep -c g15_perf_tgt_util > /dev/null || { echo "tgt_util parameter missing in the image" >&2; exit 1; }
[ "$(strings "$STAGE/boot/vmlinuz-$KREL" | grep -c 'g15_perf_boost_min\|g15_perf_boost_step\|g15_perf_base_pstate')" -ge 3 ] || { echo "Boost parameters missing in the image" >&2; exit 1; }
diff <(grep -v '^#' "/boot/config-$KREL" | sort) <(grep -v '^#' "$STAGE/boot/config-$KREL" | sort) \
	| grep '^[<>]' | grep -vx '> CONFIG_USB4_APPLE_SOC=m' && { echo "Config differs beyond USB4_APPLE_SOC" >&2; exit 1; }
[ -d "$STAGE/lib/modules/$KREL/kernel" ] || { echo "Staged modules missing" >&2; exit 1; }

# Snapshot and backup.
snapper -c root create --type single --cleanup-algorithm number --print-number \
	--description "pre stage P: G15 DVFS boost parameters" | sed 's/^/snapper snapshot: /'
mkdir -p "$BACKUP/boot"
cp -a "/boot/vmlinuz-$KREL" "/boot/config-$KREL" "/boot/System.map-$KREL" "$BACKUP/boot/"
[ -f "/boot/initramfs-$KREL.img" ] && cp -a "/boot/initramfs-$KREL.img" "$BACKUP/boot/"
cp -a "$MODS" "$BACKUP/modules"
grubby --info="/boot/vmlinuz-$KREL" > "$BACKUP/grubby-info.txt"
sha256sum "$BACKUP/boot/"* > "$BACKUP/sha256.txt"
echo "backup: $BACKUP"
echo "old image: $(sha256sum "/boot/vmlinuz-$KREL" | cut -d' ' -f1)"

# Image and modules. Keep the stage L extras (thunderbolt_apple, patched hci_bcm4377): both are in
# the staged tree too, built from the same source.
install -m 0755 "$STAGE/boot/vmlinuz-$KREL" "/boot/vmlinuz-$KREL"
install -m 0644 "$STAGE/boot/config-$KREL" "/boot/config-$KREL"
install -m 0644 "$STAGE/boot/System.map-$KREL" "/boot/System.map-$KREL"
rsync -a --exclude build --exclude source "$STAGE/lib/modules/$KREL/" "$MODS/"
depmod -a "$KREL"
[ "$(sha256sum "/boot/vmlinuz-$KREL" | cut -d' ' -f1)" = "$WANT" ]
echo "image installed: ${WANT:0:16}"
command -v dracut >/dev/null && dracut -f "/boot/initramfs-$KREL.img" "$KREL"
echo "initramfs: $(sha256sum "/boot/initramfs-$KREL.img" | cut -d' ' -f1)"

# The boot entries are not changed: show them for the record.
grubby --info=ALL | grep -E '^(kernel|args)='
echo "STAGE_P_DONE (reboot is a separate step)"
