#!/usr/bin/env bash
# Stage J: install the test kernel image with the T6030 PMP memory floor call
# (patches/t6030-pmp-memory-floor.patch, on top of the stage I masked-identity image).
# Image, System.map and config only. Modules and initramfs are unchanged (checked here).
# Backs up the installed files first. Does not touch boot.bin, DTBs, Mesa or the default
# GRUB entry. Does not reboot. Run with sudo.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }
KREL=7.2.11-m3gpu+
KSTAGE=/home/user/m3gpu/out/kernel-$KREL-memfloor
BACKUP="/root/m3gpu-backup/$(date +%Y%m%d-%H%M%S)-pre-memfloor"
[ -f "$KSTAGE/boot/vmlinuz-$KREL" ] || { echo "No staged image in $KSTAGE" >&2; exit 1; }
grep -q " apple_pmp_t6030_floor_work$" "$KSTAGE/boot/System.map-$KREL" || { echo "Staged image lacks the memory floor" >&2; exit 1; }
modsum() { (cd "$1" && find . -name "*.ko*" | sort | xargs sha256sum | sha256sum | cut -d" " -f1); }
[ "$(modsum "$KSTAGE/lib/modules/$KREL")" = "$(modsum "/usr/lib/modules/$KREL")" ] || { echo "Modules differ from the installed ones; not installing" >&2; exit 1; }
DEFAULT_BEFORE="$(grub2-editenv list | grep "^saved_entry=" || true)"
BOOTBIN_BEFORE="$(sha256sum /boot/efi/m1n1/boot.bin | cut -d" " -f1)"
mkdir -p "$BACKUP"
cp -a "/boot/vmlinuz-$KREL" "/boot/System.map-$KREL" "/boot/config-$KREL" "$BACKUP/"
install -m 0755 "$KSTAGE/boot/vmlinuz-$KREL" "/boot/vmlinuz-$KREL"
install -m 0644 "$KSTAGE/boot/config-$KREL" "/boot/config-$KREL"
install -m 0644 "$KSTAGE/boot/System.map-$KREL" "/boot/System.map-$KREL"
restorecon -F "/boot/vmlinuz-$KREL" "/boot/config-$KREL" "/boot/System.map-$KREL"
echo "=== Results"
echo "Backup: $BACKUP (restore: cp -a it back over /boot)"
echo "Image sha: $(sha256sum "/boot/vmlinuz-$KREL" | cut -d" " -f1)"
echo "Default unchanged: $([ "$(grub2-editenv list | grep "^saved_entry=" || true)" = "$DEFAULT_BEFORE" ] && echo yes || echo NO)"
echo "boot.bin unchanged: $([ "$(sha256sum /boot/efi/m1n1/boot.bin | cut -d" " -f1)" = "$BOOTBIN_BEFORE" ] && echo yes || echo NO)"
echo STAGE_J_DONE
