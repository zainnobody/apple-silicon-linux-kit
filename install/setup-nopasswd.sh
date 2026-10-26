#!/usr/bin/env bash
# One-time setup (needs the password): install the root-owned m3gpu-boot tool,
# a root-owned copy of the m1n1 binary, and the limited sudoers rule.
# Run again after a kernel or m1n1 rebuild, so the pinned hashes match.
# Usage: sudo install/setup-nopasswd.sh
. "$(dirname "$0")/lib.sh"
need_root; need_machine; need_krel

[ -f "$M1N1_BIN" ] || { echo "No m1n1 at $M1N1_BIN; run build/build-m1n1.sh" >&2; exit 1; }
[ -f "/boot/dtb-$M3_KREL/apple/$M3_DTB_NAME" ] || { echo "Test kernel DTBs not installed; run stage B" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
render "$REPO_DIR/system/m3gpu-boot.in" "$TMP/m3gpu-boot"
render "$REPO_DIR/system/m3gpu.sudoers.in" "$TMP/m3gpu.sudoers"
bash -n "$TMP/m3gpu-boot"

install -d -o root -g root -m 0755 /usr/local/lib/m3gpu /var/log/m3gpu
install -o root -g root -m 0644 "$M1N1_BIN" /usr/local/lib/m3gpu/m1n1.bin
install -o root -g root -m 0755 "$TMP/m3gpu-boot" /usr/local/sbin/m3gpu-boot

# Validate the rule before it goes live; a broken sudoers file can lock out sudo.
install -o root -g root -m 0440 "$TMP/m3gpu.sudoers" /etc/sudoers.d/m3gpu.new
if visudo -cf /etc/sudoers.d/m3gpu.new; then
	mv -f /etc/sudoers.d/m3gpu.new /etc/sudoers.d/m3gpu
else
	rm -f /etc/sudoers.d/m3gpu.new
	echo "sudoers rule failed validation; nothing changed" >&2
	exit 1
fi
visudo -c
restorecon -RF /usr/local/sbin/m3gpu-boot /usr/local/lib/m3gpu /var/log/m3gpu /etc/sudoers.d/m3gpu

ls -la /usr/local/sbin/m3gpu-boot /usr/local/lib/m3gpu /etc/sudoers.d/m3gpu
echo SETUP_DONE
