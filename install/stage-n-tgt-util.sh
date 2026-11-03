#!/usr/bin/env bash
# Stage N: install the 7.2.11-m3gpu+ build with patches/g15-perf-tgt-util.patch and set
# asahi.g15_perf_tgt_util=50 on the GPU boot entry for one test boot. Does not reboot. Run with sudo.
# The parameter lowers the firmware DVFS target utilization from the template's 80 % to 50 %, so the
# GPU keeps a higher clock in stop-and-go loads (docs/performance.md, "What limits this test").
# Without the parameter the new image behaves as the installed one. The stock entry is not changed.
# Undo: cp -a <backup>/boot files back to /boot, rsync -a --delete <backup>/modules/ to the modules folder,
#       grubby --update-kernel=/boot/vmlinuz-7.2.11-m3gpu+ --remove-args=asahi.g15_perf_tgt_util=50
set -euo pipefail
. "$(dirname "$0")/lib.sh"
[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }
KREL=7.2.11-m3gpu+
ARG=asahi.g15_perf_tgt_util=50
STAGE=$OUT/kernel-$KREL-tgt-util
WANT="${AGX_IMAGE_SHA:-3f032b51e79df0e26cd81a5646f41f7d60054bc8ffb7fe3719789b76c5c112ea}"
MODS=/usr/lib/modules/$KREL
BACKUP="/root/m3gpu-backup/$(date +%Y%m%d-%H%M%S)-pre-tgt-util"

# Checks before any change.
grep -q "apple,j516s" /proc/device-tree/compatible || { echo "Not a J516S" >&2; exit 1; }
[ "$(sha256sum "$STAGE/boot/vmlinuz-$KREL" | cut -d' ' -f1)" = "$WANT" ] || { echo "Staged image hash differs" >&2; exit 1; }
# grep -c reads all input: grep -q would end strings with SIGPIPE under pipefail.
strings "$STAGE/boot/vmlinuz-$KREL" | grep -c g15_perf_tgt_util > /dev/null || { echo "Parameter missing in the image" >&2; exit 1; }
diff <(grep -v '^#' "/boot/config-$KREL" | sort) <(grep -v '^#' "$STAGE/boot/config-$KREL" | sort) \
	| grep '^[<>]' | grep -vx '> CONFIG_USB4_APPLE_SOC=m' && { echo "Config differs beyond USB4_APPLE_SOC" >&2; exit 1; }
[ -d "$STAGE/lib/modules/$KREL/kernel" ] || { echo "Staged modules missing" >&2; exit 1; }

# Backup.
mkdir -p "$BACKUP/boot"
cp -a "/boot/vmlinuz-$KREL" "/boot/config-$KREL" "/boot/System.map-$KREL" "$BACKUP/boot/"
cp -a "$MODS" "$BACKUP/modules"
grubby --info="/boot/vmlinuz-$KREL" > "$BACKUP/grubby-info.txt"
echo "backup: $BACKUP"

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

# Boot argument, GPU entry only.
grubby --update-kernel="/boot/vmlinuz-$KREL" --args="$ARG"
grubby --info="/boot/vmlinuz-$KREL" | grep -q "$ARG" || { echo "Argument not set" >&2; exit 1; }
grubby --info=ALL | grep -E '^(kernel|args)='
echo "STAGE_N_DONE (reboot is a separate step)"
