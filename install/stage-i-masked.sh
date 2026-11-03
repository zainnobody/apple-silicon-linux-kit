#!/usr/bin/env bash
# Stage I: install the J516S masked-identity kernel image (UUID plus patchbay-masked digest, plus the
# fwdiag: log lines). Image, System.map and config only. Modules and initramfs are unchanged:
# the module hash list of the staged tree equals the installed one (checked here). Backs up
# the installed files first. Does not touch boot.bin, DTBs, Mesa or the default GRUB entry.
# Does not reboot. Run with sudo.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }

KREL=7.2.11-m3gpu+
KSTAGE="$OUT/kernel-$KREL"
WANT="${AGX_IMAGE_SHA:-66eae5b9c8006bf035d76a1412d0864a15afa00aedccc3c89f28f8f7ed77a30f}"
BACKUP="/root/m3gpu-backup/$(date +%Y%m%d-%H%M%S)-pre-masked"

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
echo STAGE_I_DONE
