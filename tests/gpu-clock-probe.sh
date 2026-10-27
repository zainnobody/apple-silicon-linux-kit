#!/bin/bash
# One command: GPU clock state during the stop-and-go pattern. Runs vk-stress with a CPU check
# every CHECK frames (default 10) for SECONDS (default 60) while tests/gpu-pstate.py samples
# the GPU clock state every 2 ms (root via sudo -n) and tests/heat-guard.sh watches the heat.
# Prints the throughput, the time share of each clock state and PROBE_DONE. Changes nothing.
# Usage: gpu-clock-probe.sh [seconds] [check every]   (desktop user; sudo -n must work)
#   PREFIX  command to run vk-stress under, for example PREFIX="uclampset -m 1024 taskset -c 7"
set -u
T=${1:-60}; CHECK=${2:-10}
D=$(dirname "$(readlink -f "$0")")
for f in gpu-pstate.py heat-guard.sh; do [ -e "$D/$f" ] || { echo "missing $D/$f"; exit 2; }; done
MESA=${MESA:-/opt/mesa-m3}
export LD_LIBRARY_PATH=$MESA/lib64 VK_DRIVER_FILES=$MESA/share/vulkan/icd.d/asahi_icd.aarch64.json
VK=${VK:-$HOME/vktest}
OUT=$HOME/gpu-perf/clock-probe-$(date +%Y%m%d-%H%M%S); mkdir -p "$OUT"
sudo -n true || { echo "sudo -n does not work"; exit 2; }
echo "clock probe $(date +%T), kernel $(uname -r), check every $CHECK, $T s, prefix "${PREFIX:-none}", $(cat /sys/class/power_supply/macsmc-battery/status), output $OUT"
# 3 s of idle first, so the log shows the state before the load
sudo -n python3 -I "$D/gpu-pstate.py" "$OUT/pstate.csv" "$((T + 6))" 2 > "$OUT/pstate.txt" & P=$!
sleep 3
(cd "$VK" && VK_STRESS_CHECK_EVERY=$CHECK ${PREFIX:-} stdbuf -oL ./vk-stress "$T") > "$OUT/vk.txt" 2>&1 & V=$!
"$D/heat-guard.sh" "$OUT/guard.log" "$V" > /dev/null 2>&1 &
wait "$V"
wait "$P"
grep -o 'frames .*Gpix-iter/s)' "$OUT/vk.txt"; grep -o 'CPU check time [0-9.]* ms' "$OUT/vk.txt"; grep -o 'STRESS_[A-Z]*' "$OUT/vk.txt"
cat "$OUT/pstate.txt"
grep STOP "$OUT/guard.log" 2>/dev/null
echo "PROBE_DONE"
