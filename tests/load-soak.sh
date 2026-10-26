#!/usr/bin/env bash
# Sustained GPU load: shader stress with exact checks for LOAD_SECONDS
# (default 3600), then thermal readings and a kernel log check. No login needed.
# Run detached:  nohup setsid tests/load-soak.sh >/dev/null 2>&1 < /dev/null &
# Result: $LOGS/load-soak-<HHMM>/summary (last line LOAD_SOAK_DONE)
set -uo pipefail
. "$(dirname "$0")/../config.sh"
LOAD_SECONDS="${LOAD_SECONDS:-3600}"

L="$LOGS/load-soak-$(date +%H%M)"
mkdir -p "$L"
export LD_LIBRARY_PATH="$MESA_PREFIX/lib64" LIBGL_DRIVERS_PATH="$MESA_PREFIX/lib64/dri"
T0=$(date '+%F %T')
echo "start $T0 kernel $(uname -r)" > "$L/summary"
timeout $((LOAD_SECONDS + 100)) "$OUT/gles-stress" "$LOAD_SECONDS" > "$L/stress.txt" 2>&1
echo "stress exit=$?: $(tail -2 "$L/stress.txt" | tr '\n' ' ')" >> "$L/summary"
for z in /sys/class/thermal/thermal_zone*/temp; do
	[ -r "$z" ] && echo "$z $(cat "$z")"
done > "$L/thermal-end.txt" 2>/dev/null
journalctl -k --no-pager --since "$T0" | grep -E 'asahi-g15|apple-drm|dcp' \
	| grep -i -E 'fault|halt|crash|timeout|submit failed|error|panic' > "$L/kernel-problems.txt"
echo "kernel GPU/display problems: $(wc -l < "$L/kernel-problems.txt")" >> "$L/summary"
echo LOAD_SOAK_DONE >> "$L/summary"
