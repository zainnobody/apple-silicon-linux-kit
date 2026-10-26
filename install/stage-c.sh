#!/usr/bin/env bash
# Stage C: new m1n1 + Fedora's DTBs and U-Boot, no new options. Then reboot
# into the default (Fedora) kernel. Reboots only if every step succeeded.
# Usage: sudo install/stage-c.sh
. "$(dirname "$0")/lib.sh"
need_root; need_machine

D="$(dirname "$0")"
LOG="$LOGS/stage-c.log"
set -o pipefail
{
	"$D/make-bootbin.sh" stageC "$M1N1_BIN" /boot/dtb
	"$D/use-bootbin.sh" stageC
	echo "GRUB: $(grub2-editenv list | grep -E 'saved_entry|next_entry' | tr '\n' ' ')"
	grub2-editenv list | grep -q 'next_entry=.' && { echo "A one-time entry is set; refusing to reboot" >&2; exit 1; }
	echo "STAGE_C_READY $(date)"
} 2>&1 | tee "$LOG"

echo "Rebooting in 5 seconds into the Fedora kernel with the new m1n1..."
sleep 5
systemctl reboot
