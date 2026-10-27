#!/usr/bin/env bash
# Rollback for gpu-boot.sh: clears a pending one-time boot and removes the tgt_util 50 entry.
# Safe to run at any time, also after the test boot. Run with sudo.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }
for f in /boot/loader/entries/*-7.2.11-m3gpu+-tgt50.conf; do
	[ -e "$f" ] || continue
	grub2-editenv list | grep -q "^next_entry=$(basename "$f" .conf)$" && grub2-editenv - unset next_entry
	rm -f "$f"; echo "removed $f"
done
grub2-editenv list
echo "GPU_ROLLBACK_DONE"
