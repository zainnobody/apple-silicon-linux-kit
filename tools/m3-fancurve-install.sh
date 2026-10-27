#!/bin/bash
# Install or remove the M3 fan curve service. Run as root on the M3.
#   m3-fancurve-install.sh <patched macsmc-hwmon.ko>   install
#   m3-fancurve-install.sh --undo                      remove; next boot has the stock module and no fan control
# The module goes to /lib/modules/<running kernel>/updates/, so it only applies to that kernel.
# The service reloads the module with fan_control=1; the initramfs and /etc/modprobe.d stay unchanged.
# A new kernel build must carry patches/macsmc-hwmon-ftst-unlock.patch itself.
set -eu
HERE=$(dirname "$(readlink -f "$0")")
KV=$(uname -r)
UPD=/lib/modules/$KV/updates/macsmc-hwmon.ko

if [ "${1:-}" = --undo ]; then
	systemctl disable --now m3-fancurve.service 2>/dev/null || true
	rm -f /etc/systemd/system/m3-fancurve.service /usr/local/sbin/m3-fancurve.sh "$UPD"
	systemctl daemon-reload
	depmod "$KV"
	for f in /sys/class/hwmon/hwmon*/fan*_target; do echo 0 > "$f"; done 2>/dev/null || true
	echo "removed; the stock module loads at the next boot"
	exit 0
fi

KO=${1:?usage: $0 <patched macsmc-hwmon.ko> | --undo}
modinfo -F vermagic "$KO" | grep -q "^$KV " || { echo "$KO is not built for $KV" >&2; exit 1; }
install -D -m 644 "$KO" "$UPD"
restorecon "$UPD" 2>/dev/null || true
depmod "$KV"
install -m 755 "$HERE/m3-fancurve.sh" /usr/local/sbin/m3-fancurve.sh
install -m 644 "$HERE/m3-fancurve.service" /etc/systemd/system/m3-fancurve.service
restorecon /usr/local/sbin/m3-fancurve.sh /etc/systemd/system/m3-fancurve.service 2>/dev/null || true
systemctl daemon-reload
systemctl enable m3-fancurve.service
systemctl start m3-fancurve.service
echo "installed for $KV and started"
