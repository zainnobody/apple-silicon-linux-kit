#!/bin/bash
# Safety guard for load tests: every 2 s reads all macsmc_hwmon, macsmc_soc_die, apple_pmp and
# apple_pmp_hotspot temperatures and both fans. Stops the load (vk-stress, 7z, heat-soak.sh,
# llama-bench) when any sensor reaches 100 C, or when the hottest sensor stays above 95 C for
# 60 s while both fans read 0 rpm. Ends by itself when heat-soak.sh is no longer running.
# Usage: heat-guard.sh [log]
set -u
LOG=${1:-$HOME/gpu-perf/heat-guard.log}
SENS=(); FANS=()
for h in /sys/class/hwmon/hwmon*; do
	case $(cat "$h/name") in macsmc_hwmon | macsmc_soc_die | apple_pmp | apple_pmp_hotspot) ;; *) continue ;; esac
	for f in "$h"/temp*_input; do cat "$f" > /dev/null 2>&1 && SENS+=("$f"); done
	for f in "$h"/fan*_input; do [ -r "$f" ] && FANS+=("$f"); done
done
hot=0
stop() { echo "$(date +%T) STOP: $*" | tee -a "$LOG"; pkill -f "heat-soa[k].sh"; pkill -x vk-stress; pkill -x 7z; pkill -x llama-bench; exit 3; }
echo "$(date +%T) guard start, ${#SENS[@]} sensors, ${#FANS[@]} fans" >> "$LOG"
while pgrep -f "heat-soa[k].sh" > /dev/null; do
	max=0; who=
	for f in "${SENS[@]}"; do v=$(cat "$f" 2>/dev/null) || continue; [ "$v" -gt "$max" ] && { max=$v; who=$f; }; done
	fans=0; for f in "${FANS[@]}"; do v=$(cat "$f" 2>/dev/null); fans=$((fans + ${v%.*})); done
	[ "$max" -ge 100000 ] && stop "sensor $who at $((max / 1000)) C"
	if [ "$max" -gt 95000 ] && [ "$fans" = 0 ]; then hot=$((hot + 2)); else hot=0; fi
	[ "$hot" -ge 60 ] && stop "above 95 C for 60 s with fans at 0 rpm (now $((max / 1000)) C at $who)"
	sleep 2
done
echo "$(date +%T) guard end, no stop" >> "$LOG"
