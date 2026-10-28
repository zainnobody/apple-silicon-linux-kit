#!/bin/sh
# Installed as /usr/local/sbin/m3-touchid-restore (root). Runs once from m3-touchid-restore.service.
# If boot.bin is still the Touch ID test file, put the base boot.bin back. Then remove itself.
ENV=/usr/local/lib/m3gpu/touchid-restore.env
ESP=/boot/efi/m1n1
LOG=/var/log/m3gpu/actions.log
[ -f "$ENV" ] || exit 0
. "$ENV"
cur=$(sha256sum $ESP/boot.bin | cut -d' ' -f1)
if [ "$cur" = "$SEP_SHA" ]; then
	if cp -f "$ESP/boot.bin.$BASE" "$ESP/boot.bin.new" && sync && mv -f "$ESP/boot.bin.new" "$ESP/boot.bin" && sync; then
		echo "$(date '+%F %T') touchid restore: boot.bin is now $BASE $(sha256sum $ESP/boot.bin | cut -d' ' -f1)" >> "$LOG"
	else
		echo "$(date '+%F %T') touchid restore: FAILED to restore $BASE" >> "$LOG"; exit 1
	fi
else
	echo "$(date '+%F %T') touchid restore: skipped, boot.bin is $cur (not the test file)" >> "$LOG"
fi
systemctl disable m3-touchid-restore.service >/dev/null 2>&1
rm -f /etc/systemd/system/m3-touchid-restore.service "$ENV"
systemctl daemon-reload
rm -f /usr/local/sbin/m3-touchid-restore
exit 0
