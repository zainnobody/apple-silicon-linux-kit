#!/usr/bin/env bash
# Installs the DART load-order fix: a dracut rule that loads apple_dart early in the initramfs and
# modprobe softdeps for its late consumers, then rebuilds the initramfs of the running kernel.
# Does not reboot. Run with sudo. Undo: install-dart-order.sh --undo (then the same dracut step).
# Check after the next boot (no root): journalctl -k -b | grep -c "late IOMMU probe" gives 0.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }
D=$(dirname "$(readlink -f "$0")")
KREL=$(uname -r)
if [ "${1:-}" = --undo ]; then
	rm -f /etc/dracut.conf.d/m3-apple-dart.conf /etc/modprobe.d/m3-apple-dart-softdep.conf
else
	grep -q "apple,t6030\|apple,j516s" /proc/device-tree/compatible || { echo "Not an M3 Pro" >&2; exit 1; }
	modinfo apple_dart > /dev/null || { echo "apple_dart is not a module here; nothing to do" >&2; exit 1; }
	cp -a "/boot/initramfs-$KREL.img" "/boot/initramfs-$KREL.img.pre-dart-order"
	install -m 0644 "$D/m3-apple-dart.conf" /etc/dracut.conf.d/m3-apple-dart.conf
	install -m 0644 "$D/m3-apple-dart-softdep.conf" /etc/modprobe.d/m3-apple-dart-softdep.conf
fi
dracut -f "/boot/initramfs-$KREL.img" "$KREL"
lsinitrd "/boot/initramfs-$KREL.img" | grep -E "apple-dart|apple_dart|m3-apple-dart" || true
echo "DART_ORDER_DONE${1:+ ($1)} (reboot is a separate step; backup /boot/initramfs-$KREL.img.pre-dart-order)"
