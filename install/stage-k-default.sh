#!/usr/bin/env bash
# Stage K: make the GPU test kernel (with the PMP memory floor) the default boot.
# - boot.bin becomes stageE (GPU and display options on). The stock kernel also boots with stageE (tested 13:43).
# - The default GRUB entry becomes 7.2.11-m3gpu+. The stock 7.1.13 entry stays in the menu as the fallback.
# - The GRUB menu shows for 5 seconds on every boot, so the stock entry can be picked by hand.
# - Kernel updates no longer change the default entry (UPDATEDEFAULT=no).
# - Installs /usr/local/sbin/m3gpu-default (status, gpu, stock) with a no-password sudo rule.
# Backs up first. Does not reboot. Run with sudo.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }
KREL=7.2.11-m3gpu+
IMG_SHA=65798c912f6b14c382cef3a818d66584d644604224694ee298182a39d962c113
STAGEE_SHA=f3197272d588f4b0a037c5f81f0cfb2c36dfc6c7398a4205910ed8b9cbaa0725
ESP=/boot/efi/m1n1
USER_NAME=user
BACKUP="/root/m3gpu-backup/$(date +%Y%m%d-%H%M%S)-pre-default"

# Checks before any change.
grep -q "apple,j516s" /proc/device-tree/compatible || { echo "Not a J516S" >&2; exit 1; }
[ "$(sha256sum "/boot/vmlinuz-$KREL" | cut -d" " -f1)" = "$IMG_SHA" ] || { echo "Kernel image is not the stage J memfloor image" >&2; exit 1; }
[ "$(sha256sum "$ESP/boot.bin.stageE" | cut -d" " -f1)" = "$STAGEE_SHA" ] || { echo "boot.bin.stageE hash differs" >&2; exit 1; }
[ -f "$ESP/boot.bin.stageD" ] && [ -f "$ESP/boot.bin.stock" ] || { echo "Missing boot.bin.stageD or boot.bin.stock" >&2; exit 1; }
grep -q '^M1N1_UPDATE_DISABLED=1' /etc/sysconfig/update-m1n1 || { echo "m1n1 updates are not paused; a rebuild would drop the GPU options" >&2; exit 1; }
GPU_ENTRY="$(basename "$(grep -l "^linux /vmlinuz-$KREL\$" /boot/loader/entries/*.conf)" .conf)"
STOCK_ENTRY="$(grub2-editenv list | sed -n 's/^saved_entry=//p')"
[ -n "$GPU_ENTRY" ] && [ -f "/boot/loader/entries/$GPU_ENTRY.conf" ] || { echo "No GRUB entry for $KREL" >&2; exit 1; }
[ -f "/boot/loader/entries/$STOCK_ENTRY.conf" ] || { echo "Current default entry $STOCK_ENTRY not found" >&2; exit 1; }
case "$STOCK_ENTRY" in *m3gpu*) echo "The default is already the GPU kernel" >&2; exit 1 ;; esac

# Backup.
mkdir -p "$BACKUP"
cp -a /boot/grub2/grubenv /etc/sysconfig/kernel "$ESP/boot.bin" "$BACKUP/"
echo "$STOCK_ENTRY" > "$BACKUP/stock-entry"

# Switch tool with a fixed stock entry name.
cat > /usr/local/sbin/m3gpu-default.new <<EOF
#!/usr/bin/env bash
# m3gpu-default: choose the default boot (installed by stage K).
#   gpu    boot.bin stageE + GRUB default $GPU_ENTRY
#   stock  boot.bin stageD + GRUB default $STOCK_ENTRY (the state before stage K)
set -euo pipefail
[ "\$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }
case "\${1:-}" in
status)
	grub2-editenv list | grep -E '^(saved_entry|next_entry|menu_auto_hide)=' || true
	sha256sum /boot/efi/m1n1/boot.bin ;;
gpu)
	/usr/local/sbin/m3gpu-boot use-stageE
	grub2-set-default "$GPU_ENTRY"
	echo "\$(date '+%F %T') default is now gpu ($GPU_ENTRY)" | tee -a /var/log/m3gpu/actions.log ;;
stock)
	/usr/local/sbin/m3gpu-boot use-stageD
	grub2-set-default "$STOCK_ENTRY"
	echo "\$(date '+%F %T') default is now stock ($STOCK_ENTRY)" | tee -a /var/log/m3gpu/actions.log ;;
*) echo "usage: m3gpu-default status | gpu | stock" >&2; exit 2 ;;
esac
EOF
install -m 0755 -o root -g root /usr/local/sbin/m3gpu-default.new /usr/local/sbin/m3gpu-default
rm -f /usr/local/sbin/m3gpu-default.new

cat > /root/m3gpu-default.sudoers <<EOF
# Installed by stage K (m3gpu default boot switch)
Cmnd_Alias M3GPU_DEFAULT = /usr/local/sbin/m3gpu-default status, /usr/local/sbin/m3gpu-default gpu, /usr/local/sbin/m3gpu-default stock
$USER_NAME ALL=(root) NOPASSWD: M3GPU_DEFAULT
EOF
visudo -cf /root/m3gpu-default.sudoers
install -m 0440 -o root -g root /root/m3gpu-default.sudoers /etc/sudoers.d/m3gpu-default
rm -f /root/m3gpu-default.sudoers
visudo -c >/dev/null

# Kernel updates must not move the default back to a stock kernel.
sed -i 's/^UPDATEDEFAULT=yes$/UPDATEDEFAULT=no/' /etc/sysconfig/kernel
# Always show the GRUB menu (5 s), so the stock entry can be picked by hand.
grub2-editenv - unset menu_auto_hide

/usr/local/sbin/m3gpu-default gpu

echo "=== Results"
echo "Backup: $BACKUP"
echo "GPU entry:   $GPU_ENTRY"
echo "Stock entry: $STOCK_ENTRY (fallback in the GRUB menu)"
/usr/local/sbin/m3gpu-default status
grep '^UPDATEDEFAULT=' /etc/sysconfig/kernel
echo "Undo without a password: sudo -n /usr/local/sbin/m3gpu-default stock"
echo STAGE_K_DONE
