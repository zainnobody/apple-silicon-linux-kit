#!/usr/bin/env bash
# Stage L: install two modules from the USB4 + Bluetooth build into the running 7.2.11-m3gpu+ kernel.
# - thunderbolt_apple.ko (new, CONFIG_USB4_APPLE_SOC=m). Automatic loading is blocked by
#   /etc/modprobe.d/m3gpu-thunderbolt-apple.conf, so it loads only by hand: sudo modprobe thunderbolt_apple
# - hci_bcm4377.ko (patches/hci-bcm4377-j516s-resume-recovery.patch). Reloaded at the end, so the
#   new code runs now. Bluetooth is off for a few seconds.
# The kernel image is not changed (the staged image must equal the installed one). Backs up first.
# Does not reboot. Run with sudo.
# Undo: cp the backup hci_bcm4377.ko back, rm the thunderbolt_apple.ko and the modprobe.d file, depmod -a 7.2.11-m3gpu+
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }
KREL=7.2.11-m3gpu+
STAGE=/home/user/m3gpu/out/kernel-$KREL-usb4-bt
SMOD="$STAGE/lib/modules/$KREL/kernel/drivers"
IMOD="/usr/lib/modules/$KREL/kernel/drivers"
BACKUP="/root/m3gpu-backup/$(date +%Y%m%d-%H%M%S)-pre-usb4-bt"
BLOCK=/etc/modprobe.d/m3gpu-thunderbolt-apple.conf

# Checks before any change.
grep -q "apple,j516s" /proc/device-tree/compatible || { echo "Not a J516S" >&2; exit 1; }
[ "$(uname -r)" = "$KREL" ] || { echo "Running kernel is not $KREL" >&2; exit 1; }
[ "$(sha256sum "$STAGE/boot/vmlinuz-$KREL" | cut -d" " -f1)" = "$(sha256sum "/boot/vmlinuz-$KREL" | cut -d" " -f1)" ] \
	|| { echo "Staged image differs from the installed image; these modules are not for it" >&2; exit 1; }
[ -f "$SMOD/thunderbolt/thunderbolt_apple.ko" ] && [ -f "$SMOD/bluetooth/hci_bcm4377.ko" ] || { echo "Staged modules missing" >&2; exit 1; }
[ ! -e "$IMOD/thunderbolt/thunderbolt_apple.ko" ] || { echo "thunderbolt_apple.ko is already installed" >&2; exit 1; }
modinfo -F vermagic "$SMOD/thunderbolt/thunderbolt_apple.ko" | grep -q "^$KREL " || { echo "Wrong vermagic" >&2; exit 1; }
modinfo -F vermagic "$SMOD/bluetooth/hci_bcm4377.ko" | grep -q "^$KREL " || { echo "Wrong vermagic" >&2; exit 1; }

# Backup.
mkdir -p "$BACKUP"
cp -a "$IMOD/bluetooth/hci_bcm4377.ko" "$BACKUP/"
cp -a /usr/lib/modules/$KREL/modules.* "$BACKUP/"

# Block automatic loading of the USB4 driver before it exists in the module tree.
printf '%s\n' "# Installed by stage L (2026-10-26). Remove to let udev load the Apple USB4 driver at boot." \
	"blacklist thunderbolt_apple" > "$BLOCK"
chmod 0644 "$BLOCK"

install -D -m 0644 -o root -g root "$SMOD/thunderbolt/thunderbolt_apple.ko" "$IMOD/thunderbolt/thunderbolt_apple.ko"
install -m 0644 -o root -g root "$SMOD/bluetooth/hci_bcm4377.ko" "$IMOD/bluetooth/hci_bcm4377.ko"
restorecon -RF "$IMOD/thunderbolt" "$IMOD/bluetooth/hci_bcm4377.ko" "$BLOCK"
depmod -a "$KREL"

# Load the new Bluetooth module now.
modprobe -r hci_bcm4377
modprobe hci_bcm4377
sleep 5

echo "=== Results"
echo "Backup: $BACKUP"
sha256sum "$IMOD/thunderbolt/thunderbolt_apple.ko" "$IMOD/bluetooth/hci_bcm4377.ko"
echo "hci_bcm4377 module file: $(modinfo -n hci_bcm4377) (j516s strings: $(strings "$(modinfo -n hci_bcm4377)" | grep -c j516s))"
echo "hci_bcm4377 loaded: $(cat /sys/module/hci_bcm4377/initstate 2>/dev/null || echo no)"
journalctl -k --since "-30 s" --no-pager | grep -iE "bcm4377|hci0" | tail -5 || true
echo "thunderbolt_apple loaded: $(lsmod | grep -q '^thunderbolt_apple ' && echo yes || echo no)"
echo "In initramfs: $(lsinitrd "/boot/initramfs-$KREL.img" 2>/dev/null | grep -cE 'hci_bcm4377|thunderbolt_apple' || true) (0 means the boot uses /usr/lib/modules)"
cat "$BLOCK"
echo STAGE_L_DONE
