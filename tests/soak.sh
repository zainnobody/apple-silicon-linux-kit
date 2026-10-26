#!/usr/bin/env bash
# Headless GPU soak with no login needed. Run it on a GPU boot as the normal user:
#   1. shader stress with exact checks (STRESS_SECONDS, default 600)
#   2. 20 readback runs
#   3. idle soak (IDLE_SECONDS, default 3600), then 3 readback runs
#   4. kernel log check for GPU and display problems
# Build the tests first: tests/build-tests.sh
# Run detached:  nohup setsid tests/soak.sh >/dev/null 2>&1 < /dev/null &
# Result: $LOGS/soak-<HHMM>/summary (last line SOAK_DONE)
set -uo pipefail
. "$(dirname "$0")/../config.sh"
STRESS_SECONDS="${STRESS_SECONDS:-600}"
IDLE_SECONDS="${IDLE_SECONDS:-3600}"

L="$LOGS/soak-$(date +%H%M)"
mkdir -p "$L"
export LD_LIBRARY_PATH="$MESA_PREFIX/lib64" LIBGL_DRIVERS_PATH="$MESA_PREFIX/lib64/dri"
T0=$(date '+%F %T')
S="$L/summary"
echo "start $T0 kernel $(uname -r)" > "$S"
timeout $((STRESS_SECONDS + 100)) "$OUT/gles-stress" "$STRESS_SECONDS" > "$L/stress.txt" 2>&1
echo "stress exit=$?: $(tail -2 "$L/stress.txt" | tr '\n' ' ')" >> "$S"
for _ in $(seq 20); do timeout 30 "$OUT/gles-readback" | tail -1; done > "$L/readback.txt" 2>&1
echo "readback: $(grep -c READBACK_PASS "$L/readback.txt")/20 pass" >> "$S"
echo "idle soak start $(date +%T)" >> "$S"
sleep "$IDLE_SECONDS"
echo "idle soak end $(date +%T)" >> "$S"
for _ in $(seq 3); do timeout 30 "$OUT/gles-readback" | tail -1; done > "$L/readback-after.txt" 2>&1
echo "readback after soak: $(grep -c READBACK_PASS "$L/readback-after.txt")/3 pass" >> "$S"
journalctl -k --no-pager --since "$T0" | grep -E 'asahi-g15|apple-drm|dcp' \
	| grep -i -E 'fault|halt|crash|timeout|submit failed|error|panic' > "$L/kernel-problems.txt"
echo "kernel GPU/display problems: $(wc -l < "$L/kernel-problems.txt")" >> "$S"
echo "uptime: $(uptime)" >> "$S"
echo SOAK_DONE >> "$S"
