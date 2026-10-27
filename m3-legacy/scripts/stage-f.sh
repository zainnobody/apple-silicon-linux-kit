#!/usr/bin/env bash
# Stage F: replace the 7.2.11-m3gpu+ test kernel with the rebuild that carries
# the J516S B1 firmware pin. Backs up the old test kernel first. Does not touch
# boot.bin, /boot/dtb, the DTBs, Mesa or the default GRUB entry. Does not reboot.
# Run with sudo.
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }

OUT=/home/user/m3gpu/out
KREL="$(cat "$OUT/kernel-release")"
KSTAGE="$OUT/kernel-$KREL"
PIN_SHA="$(cat "$OUT/pinned-image.sha256")"
BACKUP="/root/m3gpu-backup/$(date +%Y%m%d-%H%M%S)-pre-pin"

[ "$KREL" = "7.2.11-m3gpu+" ] || { echo "Unexpected kernel release $KREL" >&2; exit 1; }
[ "$(uname -r)" != "$KREL" ] || { echo "Boot the Fedora kernel before replacing $KREL" >&2; exit 1; }
[ "$(sha256sum "$KSTAGE/boot/vmlinuz-$KREL" | cut -d' ' -f1)" = "$PIN_SHA" ] || { echo "Staged image hash mismatch" >&2; exit 1; }
[ -e "/usr/lib/modules/$KREL" ] || { echo "No installed $KREL to replace" >&2; exit 1; }

DEFAULT_BEFORE="$(grub2-editenv list | grep '^saved_entry=' || true)"
BOOTBIN_BEFORE="$(sha256sum /boot/efi/m1n1/boot.bin | cut -d' ' -f1)"
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
echo "Image sha: $(sha256sum "/boot/vmlinuz-$KREL" | cut -d' ' -f1)"
echo "Default unchanged: $([ "$(grub2-editenv list | grep '^saved_entry=' || true)" = "$DEFAULT_BEFORE" ] && echo yes || echo NO)"
echo "boot.bin unchanged: $([ "$(sha256sum /boot/efi/m1n1/boot.bin | cut -d' ' -f1)" = "$BOOTBIN_BEFORE" ] && echo yes || echo NO)"
echo "/boot/dtb unchanged: $([ "$(readlink /boot/dtb)" = "$DTBLINK_BEFORE" ] && echo yes || echo NO)"
df -h /boot | tail -1
echo STAGE_F_DONE
