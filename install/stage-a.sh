#!/usr/bin/env bash
# Stage A: back up the boot files and pause automatic boot.bin rebuilds.
# Changes no boot behaviour. Usage: sudo install/stage-a.sh
. "$(dirname "$0")/lib.sh"
need_root; need_machine

ESP_BIN="$ESP_M1N1/boot.bin"
STAMP="$(date +%Y%m%d-%H%M%S)"
BK="/root/m3gpu-backup/$STAMP"
USER_BK="$M3_ROOT/backup"

mkdir -p "$BK" "$USER_BK"

# 1. boot.bin copy on the ESP (never overwrite an existing stock copy).
if [ -e "$ESP_BIN.stock" ]; then
	echo "boot.bin.stock already exists; leaving it as is"
else
	cp --preserve=timestamps "$ESP_BIN" "$ESP_BIN.stock"
fi
sync

# 2. boot.bin copies in /root and for the user (copy it to another computer).
cp --preserve=timestamps "$ESP_BIN" "$BK/boot.bin.stock"
cp --preserve=timestamps "$ESP_BIN" "$USER_BK/boot.bin.stock"
chown "$M3_USER:" "$USER_BK" "$USER_BK/boot.bin.stock"

# 3. Boot configuration.
cp -a /etc/m1n1.conf /etc/sysconfig/update-m1n1 "$BK/"
cp -a /boot/loader/entries "$BK/loader-entries"
cp -a /boot/grub2/grubenv "$BK/grubenv"
ls -la /boot/efi "$ESP_M1N1" > "$BK/esp-listing.txt"
grub2-editenv list > "$BK/grubenv.txt" 2>/dev/null || true

# 4. Pause automatic boot.bin rebuilds during the test.
if grep -q '^M1N1_UPDATE_DISABLED=' /etc/sysconfig/update-m1n1; then
	echo "M1N1_UPDATE_DISABLED already set"
else
	printf '\n# m3gpu test (%s): pause boot.bin rebuilds. Remove after testing.\nM1N1_UPDATE_DISABLED=1\n' "$(date +%F)" >> /etc/sysconfig/update-m1n1
fi

echo "=== Results"
sha256sum "$ESP_BIN" "$ESP_BIN.stock" "$BK/boot.bin.stock" "$USER_BK/boot.bin.stock"
ls -la "$ESP_M1N1"
echo "Backup folder: $BK"
ls -la "$BK"
grep -n M1N1_UPDATE_DISABLED /etc/sysconfig/update-m1n1
echo "Default entry: $(grub2-editenv list 2>/dev/null | grep saved_entry || echo none)"
echo STAGE_A_DONE
