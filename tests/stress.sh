#!/usr/bin/env bash
# Desktop GPU stress run inside the logged-in Wayland session (needs a desktop
# login on a GPU boot): glmark2, vkcube, es2gears, 5 readback runs, kernel check.
# Needs: glmark2 (dnf install glmark2), vulkan-tools, mesa-demos.
# Run:  systemd-run --user --unit=m3gpu-stress tests/stress.sh
# Result: $LOGS/stress-<HHMM>/summary (last line STRESS_DONE)
set -uo pipefail
. "$(dirname "$0")/../config.sh"

L="$LOGS/stress-$(date +%H%M)"
mkdir -p "$L"
while IFS= read -r kv; do export "${kv?}"; done < <(systemctl --user show-environment \
	| grep -E '^(WAYLAND_DISPLAY|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS|LD_LIBRARY_PATH|LIBGL_DRIVERS_PATH|GBM_BACKENDS_PATH|VK_DRIVER_FILES|VK_ICD_FILENAMES|VK_LOADER_LAYERS_DISABLE)=')
T0=$(date '+%F %T')
S="$L/summary"
echo "start $T0" > "$S"
timeout 900 glmark2-es2-wayland -s 1280x800 > "$L/glmark2.txt" 2>&1; echo "glmark2 exit=$?" >> "$S"
timeout 70 vkcube --wsi wayland --c 3000 > "$L/vkcube.txt" 2>&1; echo "vkcube exit=$?" >> "$S"
timeout 70 es2gears_wayland > "$L/es2gears.txt" 2>&1; echo "es2gears exit=$? (124 = stopped by timeout, normal)" >> "$S"
for _ in 1 2 3 4 5; do timeout 30 "$OUT/gles-readback" | tail -1; done > "$L/readback.txt" 2>&1
echo "readback: $(grep -c READBACK_PASS "$L/readback.txt")/5 pass" >> "$S"
journalctl -k --no-pager --since "$T0" | grep asahi-g15 \
	| grep -i -E 'fault|halt|crash|timeout|submit failed|error' > "$L/kernel-problems.txt"
echo "kernel GPU problems: $(wc -l < "$L/kernel-problems.txt")" >> "$S"
grep -E "glmark2 Score" "$L/glmark2.txt" >> "$S"
echo "end $(date '+%F %T')" >> "$S"
echo STRESS_DONE >> "$S"
