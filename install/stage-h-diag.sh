#!/usr/bin/env bash
# Stage H: install the J516S firmware-digest diagnostic kernel image (the cd05af6a pin plus the
# fwdiag: log lines). Image, System.map and config only. Modules and initramfs are unchanged:
# the module hash list of the staged tree equals the installed one (checked here). Backs up
# the installed files first. Does not touch boot.bin, DTBs, Mesa or the default GRUB entry.
# Does not reboot. Run with sudo.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }

KREL=7.2.11-m3gpu+
OUT=/home/user/m3gpu/out
KSTAGE="$OUT/kernel-$KREL"
WANT=43dd38328000fdc75a65d31c688f705cfb81dd6a9a7568ef8c59bd5e75130e92
BACKUP="/root/m3gpu-backup/$(date +%Y%m%d-%H%M%S)-pre-diag"

[ "$(sha256sum "$KSTAGE/boot/vmlinuz-$KREL" | cut -d' ' -f1)" = "$WANT" ] || { echo "Staged image hash mismatch" >&2; exit 1; }
modsum() { (cd "$1" && find . -name '*.ko*' | sort | xargs sha256sum | sha256sum | cut -d' ' -f1); }
[ "$(modsum "$KSTAGE/lib/modules/$KREL")" = "$(modsum "/usr/lib/modules/$KREL")" ] || { echo "Modules differ, use stage-f.sh flow" >&2; exit 1; }

DEFAULT_BEFORE="$(grub2-editenv list | grep '^saved_entry=' || true)"
BOOTBIN_BEFORE="$(sha256sum /boot/efi/m1n1/boot.bin | cut -d' ' -f1)"

mkdir -p "$BACKUP"
cp -a "/boot/vmlinuz-$KREL" "/boot/System.map-$KREL" "/boot/config-$KREL" "$BACKUP/"

install -m 0755 "$KSTAGE/boot/vmlinuz-$KREL" "/boot/vmlinuz-$KREL"
install -m 0644 "$KSTAGE/boot/config-$KREL" "/boot/config-$KREL"
install -m 0644 "$KSTAGE/boot/System.map-$KREL" "/boot/System.map-$KREL"
restorecon -F "/boot/vmlinuz-$KREL" "/boot/config-$KREL" "/boot/System.map-$KREL"

echo "=== Results"
echo "Backup: $BACKUP (restore: cp -a it back over /boot)"
echo "Image sha: $(sha256sum "/boot/vmlinuz-$KREL" | cut -d' ' -f1)"
echo "Default unchanged: $([ "$(grub2-editenv list | grep '^saved_entry=' || true)" = "$DEFAULT_BEFORE" ] && echo yes || echo NO)"
echo "boot.bin unchanged: $([ "$(sha256sum /boot/efi/m1n1/boot.bin | cut -d' ' -f1)" = "$BOOTBIN_BEFORE" ] && echo yes || echo NO)"
echo STAGE_H_DONE
