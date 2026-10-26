#!/usr/bin/env bash
# Stage B: install Mesa into $MESA_PREFIX and the test kernel as an extra,
# non-default GRUB entry, then select it for the next boot only.
# Does not touch boot.bin, /boot/dtb or the default entry. Does not reboot.
# Usage: sudo install/stage-b.sh
. "$(dirname "$0")/lib.sh"
need_root; need_machine; need_krel

KREL="$M3_KREL"
KSTAGE="$OUT/kernel-$KREL"
MSTAGE="$OUT/mesa-stage$MESA_PREFIX"
ENTRIES=/boot/loader/entries
FEDORA_KREL="$(uname -r)"

case "$KREL" in *"$LOCALVERSION"*) ;; *) echo "Unexpected kernel release $KREL" >&2; exit 1 ;; esac
[ "$FEDORA_KREL" != "$KREL" ] || { echo "Boot the Fedora kernel first" >&2; exit 1; }
[ ! -e "/usr/lib/modules/$KREL" ] || { echo "/usr/lib/modules/$KREL already exists (use stage F to replace it)" >&2; exit 1; }
[ ! -e "$MESA_PREFIX" ] || { echo "$MESA_PREFIX already exists" >&2; exit 1; }

DEFAULT_BEFORE="$(grub2-editenv list | grep '^saved_entry=' || true)"
BOOTBIN_BEFORE="$(sha "$ESP_M1N1/boot.bin")"
DTBLINK_BEFORE="$(readlink /boot/dtb)"

# 1. Mesa
cp -a "$MSTAGE" "$MESA_PREFIX"
chown -R root:root "$MESA_PREFIX"
restorecon -RF "$MESA_PREFIX"

# 2. Kernel modules, image, config, System.map, DTBs (Apple only)
cp -a "$KSTAGE/lib/modules/$KREL" "/usr/lib/modules/$KREL"
chown -R root:root "/usr/lib/modules/$KREL"
rm -f "/usr/lib/modules/$KREL/build" "/usr/lib/modules/$KREL/source"
depmod -a "$KREL"
install -m 0755 "$KSTAGE/boot/vmlinuz-$KREL" "/boot/vmlinuz-$KREL"
install -m 0644 "$KSTAGE/boot/config-$KREL" "/boot/config-$KREL"
install -m 0644 "$KSTAGE/boot/System.map-$KREL" "/boot/System.map-$KREL"
mkdir -p "/boot/dtb-$KREL"
cp -a "$KSTAGE/dtb/apple" "/boot/dtb-$KREL/apple"
restorecon -RF "/usr/lib/modules/$KREL" "/boot/vmlinuz-$KREL" "/boot/config-$KREL" \
	"/boot/System.map-$KREL" "/boot/dtb-$KREL"

# 3. Initramfs
dracut --force --kver "$KREL" "/boot/initramfs-$KREL.img"
restorecon -F "/boot/initramfs-$KREL.img"

# 4. GRUB entry: copy the running Fedora entry and change only the version.
SRC_ENTRY="$(grep -l "^linux /vmlinuz-$FEDORA_KREL\$" "$ENTRIES"/*.conf | head -1)"
[ -n "$SRC_ENTRY" ] || { echo "No BLS entry for $FEDORA_KREL" >&2; exit 1; }
if grep -q '^devicetree' "$SRC_ENTRY"; then
	echo "Fedora entry has a devicetree line; stop and review" >&2; exit 1
fi
NEW_ID="$(basename "$SRC_ENTRY" .conf | sed "s/$FEDORA_KREL/$KREL/")"
sed -e "s/$FEDORA_KREL/$KREL/g" \
    -e "s/^title .*/title Fedora m3gpu test ($KREL)/" \
    "$SRC_ENTRY" > "$ENTRIES/$NEW_ID.conf"
restorecon -F "$ENTRIES/$NEW_ID.conf"

# 5. Boot the new kernel once on the next boot only.
grub2-reboot "$NEW_ID"

echo "=== Results"
echo "New entry: $ENTRIES/$NEW_ID.conf"
cat "$ENTRIES/$NEW_ID.conf"
ls -la "/boot/vmlinuz-$KREL" "/boot/initramfs-$KREL.img"
grub2-editenv list
echo "Default before: $DEFAULT_BEFORE"
echo "boot.bin unchanged: $([ "$(sha "$ESP_M1N1/boot.bin")" = "$BOOTBIN_BEFORE" ] && echo yes || echo NO)"
echo "/boot/dtb unchanged: $([ "$(readlink /boot/dtb)" = "$DTBLINK_BEFORE" ] && echo yes || echo NO)"
ls "$MESA_PREFIX/lib64/dri/asahi_dri.so" "$MESA_PREFIX/lib64/libvulkan_asahi.so"
df -h /boot | tail -1
echo STAGE_B_DONE
