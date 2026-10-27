#!/usr/bin/env bash
# Read-only check before a reboot into the stage K default (J516S, 7.2.11-m3gpu+). Changes nothing.
# Uses sudo -n where root is needed; a line says SKIP when sudo needs a password.
# Prints PRE_REBOOT_OK only when every check passes.
set -uo pipefail
KREL=7.2.11-m3gpu+
IMG_SHA=65798c912f6b14c382cef3a818d66584d644604224694ee298182a39d962c113
STAGEE_SHA=f3197272d588f4b0a037c5f81f0cfb2c36dfc6c7398a4205910ed8b9cbaa0725
fail=0
ok()   { echo "ok:   $*"; }
bad()  { echo "FAIL: $*"; fail=1; }
skip() { echo "SKIP: $*"; }
root() { sudo -n "$@" 2>/dev/null; }
canroot() { sudo -n true 2>/dev/null; }

[ "$(sha256sum /boot/vmlinuz-$KREL | cut -d' ' -f1)" = "$IMG_SHA" ] && ok "kernel image is the memory-floor image" || bad "kernel image sha differs"
[ "$(sha256sum /boot/efi/m1n1/boot.bin 2>/dev/null | cut -d' ' -f1)" = "$STAGEE_SHA" ] && ok "boot.bin is stageE" \
	|| { canroot && [ "$(root sha256sum /boot/efi/m1n1/boot.bin | cut -d' ' -f1)" = "$STAGEE_SHA" ] && ok "boot.bin is stageE" || bad "boot.bin is not stageE (or unreadable)"; }

if canroot; then
	env="$(root grub2-editenv list)"
	echo "$env" | grep -q "^saved_entry=.*-$KREL\$" && ok "default entry: $KREL" || bad "default entry: $(echo "$env" | grep saved_entry)"
	echo "$env" | grep -q "^next_entry=." && bad "a one-time next_entry is set: $(echo "$env" | grep next_entry)" || ok "no one-time next_entry"
	echo "$env" | grep -q "^menu_auto_hide=1" && bad "GRUB menu is hidden" || ok "GRUB menu shows (fallback can be picked)"
	entries="$(root sh -c 'grep -h "^linux " /boot/loader/entries/*.conf')"
	echo "$entries" | grep -q "vmlinuz-$KREL\$" && ok "GRUB entry for $KREL exists" || bad "no GRUB entry for $KREL"
	echo "$entries" | grep -q "vmlinuz-7.1.13" && ok "stock 7.1.13 fallback entry exists" || bad "no stock fallback entry"
	root test -f "/boot/initramfs-$KREL.img" && ok "initramfs for $KREL exists" || bad "no initramfs for $KREL"
	root grep -q '^M1N1_UPDATE_DISABLED=1' /etc/sysconfig/update-m1n1 && ok "m1n1 updates paused" || bad "m1n1 updates not paused"
	snap="$(root snapper list 2>/dev/null | tail -n 3)"
	[ -n "$snap" ] && { ok "snapper snapshots (last 3):"; echo "$snap"; } || bad "no snapper snapshot list"
	root test -f /etc/sudoers.d/m3gpu-default && ok "m3gpu-default switch installed (undo path)" || bad "no m3gpu-default sudoers rule"
else
	skip "GRUB env, entries, initramfs, m1n1 pause and snapper need sudo"
fi
grep -q '^UPDATEDEFAULT=no' /etc/sysconfig/kernel && ok "kernel updates keep the default" || bad "UPDATEDEFAULT is not no"

# Stage L state.
[ -f /usr/lib/modules/$KREL/kernel/drivers/thunderbolt/thunderbolt_apple.ko ] && ok "thunderbolt_apple.ko installed" || bad "thunderbolt_apple.ko missing (stage L not done)"
grep -qx "blacklist thunderbolt_apple" /etc/modprobe.d/m3gpu-thunderbolt-apple.conf 2>/dev/null && ok "thunderbolt_apple autoload blocked" || bad "thunderbolt_apple blacklist missing"
[ "$(strings /usr/lib/modules/$KREL/kernel/drivers/bluetooth/hci_bcm4377.ko | grep -c j516s)" -ge 1 ] && ok "patched hci_bcm4377.ko installed" || bad "hci_bcm4377.ko is not the patched one"

# Nothing that should not be cut by a reboot.
busy="$(pgrep -fa 'llama-|test-backend|soak|stress|make .*m3gpu|dnf|rpm ' | grep -v pgrep || true)"
[ -z "$busy" ] && ok "no build, benchmark, soak or package job runs" || { bad "jobs still run:"; echo "$busy"; }
echo "uptime: $(uptime)"
[ "$fail" = 0 ] && echo PRE_REBOOT_OK || echo PRE_REBOOT_NOT_OK
