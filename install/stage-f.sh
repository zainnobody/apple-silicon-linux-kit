#!/usr/bin/env bash
# Stage F: replace the installed test kernel with a rebuild (for example one
# that carries patches/g15-j516s-b1-pin.patch). Backs up the old test kernel
# first. Does not touch boot.bin, /boot/dtb, the DTBs, Mesa or the default GRUB
# entry. Does not reboot. Boot the Fedora kernel before running it.
# Usage: sudo install/stage-f.sh
. "$(dirname "$0")/lib.sh"
need_root; need_machine; need_krel

KREL="$M3_KREL"
KSTAGE="$OUT/kernel-$KREL"
BACKUP="/root/m3gpu-backup/$(date +%Y%m%d-%H%M%S)-pre-replace"

[ "$(uname -r)" != "$KREL" ] || { echo "Boot the Fedora kernel before replacing $KREL" >&2; exit 1; }
[ -e "/usr/lib/modules/$KREL" ] || { echo "No installed $KREL to replace (use stage B)" >&2; exit 1; }
[ -f "$KSTAGE/boot/vmlinuz-$KREL" ] || { echo "No staged kernel in $KSTAGE" >&2; exit 1; }

DEFAULT_BEFORE="$(grub2-editenv list | grep '^saved_entry=' || true)"
BOOTBIN_BEFORE="$(sha "$ESP_M1N1/boot.bin")"
DTBLINK_BEFORE="$(readlink /boot/dtb)"

# 1. Back up the current test kernel.
mkdir -p "$BACKUP"
cp -a "/boot/vmlinuz-$KREL" "/boot/System.map-$KREL" "/boot/config-$KREL" \
	"/boot/initramfs-$KREL.img" "$BACKUP/"
cp -a "/usr/lib/modules/$KREL" "$BACKUP/modules-$KREL"

# 2. Install the new image, config, System.map and modules.
install -m 0755 "$KSTAGE/boot/vmlinuz-$KREL" "/boot/vmlinuz-$KREL"
install -m 0644 "$KSTAGE/boot/config-$KREL" "/boot/config-$KREL"
install -m 0644 "$KSTAGE/boot/System.map-$KREL" "/boot/System.map-$KREL"
rm -rf "/usr/lib/modules/$KREL"
cp -a "$KSTAGE/lib/modules/$KREL" "/usr/lib/modules/$KREL"
chown -R root:root "/usr/lib/modules/$KREL"
rm -f "/usr/lib/modules/$KREL/build" "/usr/lib/modules/$KREL/source"
depmod -a "$KREL"
restorecon -RF "/usr/lib/modules/$KREL" "/boot/vmlinuz-$KREL" "/boot/config-$KREL" \
	"/boot/System.map-$KREL"

# 3. Initramfs
dracut --force --kver "$KREL" "/boot/initramfs-$KREL.img"
restorecon -F "/boot/initramfs-$KREL.img"

echo "=== Results"
echo "Backup: $BACKUP"
ls -la "/boot/vmlinuz-$KREL" "/boot/initramfs-$KREL.img"
echo "Image sha: $(sha "/boot/vmlinuz-$KREL") (staged: $(sha "$KSTAGE/boot/vmlinuz-$KREL"))"
echo "Default unchanged: $([ "$(grub2-editenv list | grep '^saved_entry=' || true)" = "$DEFAULT_BEFORE" ] && echo yes || echo NO)"
echo "boot.bin unchanged: $([ "$(sha "$ESP_M1N1/boot.bin")" = "$BOOTBIN_BEFORE" ] && echo yes || echo NO)"
echo "/boot/dtb unchanged: $([ "$(readlink /boot/dtb)" = "$DTBLINK_BEFORE" ] && echo yes || echo NO)"
df -h /boot | tail -1
echo STAGE_F_DONE
