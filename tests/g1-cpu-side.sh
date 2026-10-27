#!/bin/bash
# G1a: vk-stress with the macOS pattern (wait and CPU check every 10th frame), 3 runs of 60 s per
# CPU setting: default scheduling, pinned to P core 7, pinned plus uclamp.min 1024 (uclampset).
# Run as the desktop user from the folder with vk-stress and vk-stress.spv. No root.
set -u
T=${1:-60}
MESA=${MESA:-/opt/mesa-m3}
export LD_LIBRARY_PATH=$MESA/lib64 VK_DRIVER_FILES=$MESA/share/vulkan/icd.d/asahi_icd.aarch64.json
# Heat sampling (tests/heat-sample.sh, next to this script or in ~/m3gpu): max temps and fan rpm.
HEAT=${HEAT:-$(dirname "$(readlink -f "$0")")/heat-sample.sh}
[ -x "$HEAT" ] || HEAT=$HOME/m3gpu/heat-sample.sh
HEAT_PID=
heat_start() { [ -x "$HEAT" ] && { "$HEAT" "$1" > "${1%.csv}.txt" & HEAT_PID=$!; }; }
heat_stop() { [ -n "$HEAT_PID" ] || return 0; kill "$HEAT_PID" 2>/dev/null; wait "$HEAT_PID" 2>/dev/null; HEAT_PID=; cat "${1%.csv}.txt" 2>/dev/null; }
HEAT_CSV=$HOME/gpu-perf/g1-heat-$(date +%Y%m%d-%H%M%S).csv
mkdir -p "$HOME/gpu-perf"
heat_start "$HEAT_CSV"
trap 'heat_stop "$HEAT_CSV"' EXIT
for mode in default pcore pcore-uclamp; do
	for r in 1 2 3; do
		case $mode in
		default) cmd=(./vk-stress "$T") ;;
		pcore) cmd=(taskset -c 7 ./vk-stress "$T") ;;
		pcore-uclamp) cmd=(uclampset -m 1024 taskset -c 7 ./vk-stress "$T") ;;
		esac
		out=$("${cmd[@]}" 2>&1)
		g=$(echo "$out" | grep -o '[0-9.]* Gpix' | cut -d' ' -f1)
		c=$(echo "$out" | grep -o 'check time [0-9.]*' | cut -d' ' -f3)
		echo "$mode run $r: $g G, check $c ms, battery $(cat /sys/class/power_supply/macsmc-battery/status)"
		sleep 5
	done
done
