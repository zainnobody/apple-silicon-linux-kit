#!/usr/bin/env bash
# Undo touchid-boot.sh before (or after) the test boot: put the base boot.bin back and remove the restore unit.
# boot.bin.sep stays in the ESP (harmless). Needs sudo -n. Never reboots.
set -euo pipefail
say() { echo "[touchid-disarm] $*"; }
if sudo -n test -f /usr/local/lib/m3gpu/touchid-restore.env; then
	sudo -n /usr/local/sbin/m3-touchid-restore
	say "restore helper ran"
else
	say "nothing armed (no restore state file)"
fi
sudo -n /usr/local/sbin/m3gpu-boot status 2>&1 | sed -n 1,12p
