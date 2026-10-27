#!/usr/bin/env bash
# Stage C: new m1n1 + Fedora's DTBs and U-Boot, no new options. Then reboot
# into the default (Fedora) kernel. Reboots only if every step succeeded.
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }
S=/home/user/m3gpu/scripts
M1N1=/home/user/m3gpu/out/m1n1/m1n1-aca1258c2d7daad7db7079d4f89bb8217659f7ac.bin
LOG=/home/user/m3gpu/logs/stage-c.log

{
	"$S/make-bootbin.sh" stageC "$M1N1" /boot/dtb
	"$S/use-bootbin.sh" stageC
	echo "GRUB: $(grub2-editenv list | grep -E 'saved_entry|next_entry' | tr '\n' ' ')"
	grub2-editenv list | grep -q 'next_entry=.' && { echo "A one-time entry is set; refusing to reboot" >&2; exit 1; }
	echo "STAGE_C_READY $(date)"
} 2>&1 | tee "$LOG"

echo "Rebooting in 5 seconds into the Fedora kernel with the new m1n1..."
sleep 5
systemctl reboot
