#!/usr/bin/env bash
# One-time setup (needs the password): install the root-owned agx-boot tool,
# a root-owned copy of the m1n1 binary, and the limited sudoers rule.
# Run again after a kernel or m1n1 rebuild, so the pinned hashes match.
# Usage: sudo install/setup-nopasswd.sh
. "$(dirname "$0")/lib.sh"
need_root; need_machine; need_krel

[ -f "$M1N1_BIN" ] || { echo "No m1n1 at $M1N1_BIN; run build/build-m1n1.sh" >&2; exit 1; }
[ -f "/boot/dtb-$AGX_KREL/apple/$AGX_DTB_NAME" ] || { echo "Test kernel DTBs not installed; run stage B" >&2; exit 1; }

migrate_legacy

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
render "$REPO_DIR/system/agx-boot.in" "$TMP/agx-boot"
render "$REPO_DIR/system/agx.sudoers.in" "$TMP/agx.sudoers"
bash -n "$TMP/agx-boot"

install -d -o root -g root -m 0755 /usr/local/lib/agx /var/log/agx
install -o root -g root -m 0644 "$M1N1_BIN" /usr/local/lib/agx/m1n1.bin
install -o root -g root -m 0755 "$TMP/agx-boot" /usr/local/sbin/agx-boot

# Validate the rule before it goes live; a broken sudoers file can lock out sudo.
install -o root -g root -m 0440 "$TMP/agx.sudoers" /etc/sudoers.d/agx.new
if visudo -cf /etc/sudoers.d/agx.new; then
	mv -f /etc/sudoers.d/agx.new /etc/sudoers.d/agx
else
	rm -f /etc/sudoers.d/agx.new
	echo "sudoers rule failed validation; nothing changed" >&2
	exit 1
fi
visudo -c
restorecon -RF /usr/local/sbin/agx-boot /usr/local/lib/agx /var/log/agx /etc/sudoers.d/agx

ls -la /usr/local/sbin/agx-boot /usr/local/lib/agx /etc/sudoers.d/agx
echo SETUP_DONE
