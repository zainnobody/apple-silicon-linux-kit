#!/usr/bin/env bash
# Stage D: new m1n1 + the test kernel's DTBs + Fedora U-Boot, no new options.
# The GPU stays off (m1n1 only does a dry run). Then reboot once into the test
# kernel. Reboots only if every step succeeded.
# Usage: sudo install/stage-d.sh
. "$(dirname "$0")/lib.sh"
need_root; need_machine; need_krel

D="$(dirname "$0")"
DTBDIR="/boot/dtb-$AGX_KREL"
BUILT_DTB="$OUT/kernel-$AGX_KREL/dtb/apple/$AGX_DTB_NAME"
LOG="$LOGS/stage-d.log"
set -o pipefail
{
	# The installed board DTB must be the one this build produced.
	[ "$(sha "$DTBDIR/apple/$AGX_DTB_NAME")" = "$(sha "$BUILT_DTB")" ] \
		|| { echo "$AGX_DTB_NAME in $DTBDIR differs from the build output" >&2; exit 1; }
	"$D/make-bootbin.sh" stageD "$M1N1_BIN" "$DTBDIR"
	"$D/use-bootbin.sh" stageD
	ENTRY="$(basename "$(grep -l "^linux /vmlinuz-$AGX_KREL\$" /boot/loader/entries/*.conf)" .conf)"
	grub2-reboot "$ENTRY"
	echo "GRUB: $(grub2-editenv list | grep -E 'saved_entry|next_entry' | tr '\n' ' ')"
	echo "STAGE_D_READY $(date)"
} 2>&1 | tee "$LOG"

echo "Rebooting in 5 seconds into the test kernel (once) with its DTBs..."
sleep 5
systemctl reboot
