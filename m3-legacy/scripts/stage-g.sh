#!/usr/bin/env bash
# Stage G: desktop on native Mesa. Installs root-owned copies of
#   m3gpu-mesa-select (+ service): linker cache entry only when asahi-g15 is bound
#   60-m3gpu-native-mesa: user environment generator, same condition
#   m3gpu-boot + sudoers: adds the no-password actions mesa-select and restart-login
# Then selects Mesa for this boot and restarts the login screen. Run with sudo.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }
SRC=/home/user/m3gpu/scripts

install -o root -g root -m 0755 "$SRC/m3gpu-mesa-select" /usr/local/sbin/m3gpu-mesa-select
install -o root -g root -m 0644 "$SRC/m3gpu-mesa-select.service" /etc/systemd/system/m3gpu-mesa-select.service
install -D -o root -g root -m 0755 "$SRC/60-m3gpu-native-mesa" /etc/systemd/user-environment-generators/60-m3gpu-native-mesa
rm -f /etc/profile.d/m3gpu-native-mesa.sh
install -o root -g root -m 0755 "$SRC/m3gpu-boot" /usr/local/sbin/m3gpu-boot

install -o root -g root -m 0440 "$SRC/m3gpu.sudoers" /etc/sudoers.d/m3gpu.new
if visudo -cf /etc/sudoers.d/m3gpu.new; then
	mv -f /etc/sudoers.d/m3gpu.new /etc/sudoers.d/m3gpu
else
	rm -f /etc/sudoers.d/m3gpu.new
	echo "sudoers rule failed validation; old rule kept" >&2
	exit 1
fi
restorecon -RF /usr/local/sbin /etc/systemd/system/m3gpu-mesa-select.service \
	/etc/systemd/user-environment-generators /etc/sudoers.d/m3gpu
systemctl daemon-reload
systemctl enable m3gpu-mesa-select.service
systemctl start m3gpu-mesa-select.service
/usr/local/sbin/m3gpu-boot mesa-select
/usr/local/sbin/m3gpu-boot restart-login
echo STAGE_G_DONE
