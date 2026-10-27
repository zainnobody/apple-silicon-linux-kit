#!/usr/bin/env bash
# One-time setup (needs the password): install the root-owned m3gpu-boot tool,
# a root-owned copy of the m1n1 binary, and the limited sudoers rule.
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }
SRC=/home/user/m3gpu
M1N1_SHA=3118c16f20ee32dba8c8eee14e00fd37c31ab6ab200d12c7cad6c1e60500a710

install -d -o root -g root -m 0755 /usr/local/lib/m3gpu /var/log/m3gpu
install -o root -g root -m 0644 "$SRC/out/m1n1/m1n1-aca1258c2d7daad7db7079d4f89bb8217659f7ac.bin" /usr/local/lib/m3gpu/m1n1-aca1258.bin
[ "$(sha256sum /usr/local/lib/m3gpu/m1n1-aca1258.bin | cut -d' ' -f1)" = "$M1N1_SHA" ] || { echo "m1n1 hash mismatch" >&2; exit 1; }
install -o root -g root -m 0755 "$SRC/scripts/m3gpu-boot" /usr/local/sbin/m3gpu-boot

# Validate the rule before it goes live; a broken sudoers file can lock out sudo.
install -o root -g root -m 0440 "$SRC/scripts/m3gpu.sudoers" /etc/sudoers.d/m3gpu.new
if visudo -cf /etc/sudoers.d/m3gpu.new; then
	mv -f /etc/sudoers.d/m3gpu.new /etc/sudoers.d/m3gpu
else
	rm -f /etc/sudoers.d/m3gpu.new
	echo "sudoers rule failed validation; nothing installed" >&2
	exit 1
fi
visudo -c
restorecon -RF /usr/local/sbin/m3gpu-boot /usr/local/lib/m3gpu /var/log/m3gpu /etc/sudoers.d/m3gpu

ls -la /usr/local/sbin/m3gpu-boot /usr/local/lib/m3gpu /etc/sudoers.d/m3gpu
echo SETUP_DONE
