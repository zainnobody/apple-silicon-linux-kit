#!/usr/bin/env bash
# Stage E: boot.bin with the native GPU and display options ($AGX_M1N1_OPTIONS),
# then reboot once into the test kernel. The default entry stays the Fedora
# kernel, so the next normal boot is the stock kernel (with the same boot.bin).
# Run install/setup-nopasswd.sh first to do this later without a password:
#   sudo -n /usr/local/sbin/agx-boot build-stageE
#   sudo -n /usr/local/sbin/agx-boot use-stageE
#   sudo -n /usr/local/sbin/agx-boot test-once
#   sudo -n systemctl reboot
# Usage: sudo install/stage-e.sh
. "$(dirname "$0")/lib.sh"
need_root; need_machine; need_krel

D="$(dirname "$0")"
LOG="$LOGS/stage-e.log"
set -o pipefail
{
	# shellcheck disable=SC2086 # the options are separate words on purpose
	"$D/make-bootbin.sh" stageE "$M1N1_BIN" "/boot/dtb-$AGX_KREL" $AGX_M1N1_OPTIONS
	"$D/use-bootbin.sh" stageE
	ENTRY="$(basename "$(grep -l "^linux /vmlinuz-$AGX_KREL\$" /boot/loader/entries/*.conf)" .conf)"
	grub2-reboot "$ENTRY"
	echo "STAGE_E_READY $(date)"
} 2>&1 | tee "$LOG"

echo "Rebooting in 5 seconds into the test kernel (once) with the GPU on..."
sleep 5
systemctl reboot
