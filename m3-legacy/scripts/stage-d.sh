#!/usr/bin/env bash
# Stage D: new m1n1 + the test kernel's DTBs (t6030-j516s.dtb identical to
# SiliconForest's) + Fedora U-Boot, no new options. GPU stays off (dry run).
# Then reboot once into the test kernel. Reboots only if every step succeeded.
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }
S=/home/user/m3gpu/scripts
M1N1=/home/user/m3gpu/out/m1n1/m1n1-aca1258c2d7daad7db7079d4f89bb8217659f7ac.bin
KREL=7.2.11-m3gpu+
DTBDIR="/boot/dtb-$KREL"
LOG=/home/user/m3gpu/logs/stage-d.log
WANT_DTB=18baac96873fabed31c1eca3a2495dd2ea534067120dddf71d373f1345acd47c

{
	[ "$(sha256sum "$DTBDIR/apple/t6030-j516s.dtb" | cut -d' ' -f1)" = "$WANT_DTB" ] \
		|| { echo "t6030-j516s.dtb hash is not the SiliconForest one" >&2; exit 1; }
	"$S/make-bootbin.sh" stageD "$M1N1" "$DTBDIR"
	"$S/use-bootbin.sh" stageD
	ENTRY="$(basename "$(grep -l "^linux /vmlinuz-$KREL\$" /boot/loader/entries/*.conf)" .conf)"
	grub2-reboot "$ENTRY"
	echo "GRUB: $(grub2-editenv list | grep -E 'saved_entry|next_entry' | tr '\n' ' ')"
	echo "STAGE_D_READY $(date)"
} 2>&1 | tee "$LOG"

echo "Rebooting in 5 seconds into the test kernel (once) with the j516s DTB..."
sleep 5
systemctl reboot
