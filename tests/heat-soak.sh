#!/bin/bash
# Phase 2 heat soak: 10 min GPU only (vk-stress, no wait), cool-down, then 10 min CPU plus GPU
# (7-Zip benchmark loop on all 12 cores plus vk-stress). Samples temps and fans
# (tests/heat-sample.sh) and CPU clocks every 2 s; vk-stress prints throughput every 30 s and
# each 7-Zip pass prints its total rating, so a drop over the run shows throttling.
# Usage: heat-soak.sh [seconds per phase] [cool-down seconds]   (desktop user, charger in)
# tests/heat-guard.sh runs alongside and stops the load at 100 C, or above 95 C for 60 s with the fans off.
set -u
T=${1:-600}; COOL=${2:-180}
MESA=${MESA:-/opt/mesa-m3}
export LD_LIBRARY_PATH=$MESA/lib64 VK_DRIVER_FILES=$MESA/share/vulkan/icd.d/asahi_icd.aarch64.json
VK=${VK:-$HOME/vktest}
HEAT=${HEAT:-$(dirname "$(readlink -f "$0")")/heat-sample.sh}
[ -x "$HEAT" ] || HEAT=$HOME/m3gpu/heat-sample.sh
OUT=$HOME/gpu-perf/heat-soak-$(date +%Y%m%d-%H%M%S); mkdir -p "$OUT"
GUARD=$(dirname "$(readlink -f "$0")")/heat-guard.sh
[ -x "$GUARD" ] || GUARD=$HOME/m3gpu/heat-guard.sh
"$GUARD" "$OUT/guard.log" > /dev/null 2>&1 &
KWIN=$(pgrep -u "$(id -u)" -x kwin_wayland); PLASMA=$(pgrep -u "$(id -u)" -x plasmashell)
echo "start $(date +%T), kwin $KWIN, plasmashell $PLASMA, $(cat /sys/class/power_supply/macsmc-battery/status), output $OUT"

clocks() { # CPU clocks in MHz (policy0: P cores, max 4056; policy1: E cores, max 2748) every 2 s
	echo "time,pcore_mhz,ecore_mhz" > "$1"
	while :; do
		echo "$(date +%T),$(($(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq) / 1000)),$(($(cat /sys/devices/system/cpu/cpufreq/policy1/scaling_cur_freq) / 1000))" >> "$1"
		sleep 2
	done
}
desktop() { kill -0 "$KWIN" 2>/dev/null && kill -0 "$PLASMA" 2>/dev/null; }

phase() {
	local name=$1 cpu=$2
	"$HEAT" "$OUT/$name-heat.csv" > "$OUT/$name-heat.txt" & local H=$!
	clocks "$OUT/$name-clocks.csv" & local C=$!
	local Z=
	if [ "$cpu" = 1 ]; then
		( end=$((SECONDS + T)); while [ $SECONDS -lt $end ]; do
			echo "$(date +%T) $(7z b -mmt12 -md22 2>&1 | awk '/^Tot:/ {print $NF}')"; done ) > "$OUT/$name-7z.txt" & Z=$!
	fi
	# stdbuf: vk-stress buffers its 30 s lines when stdout is a file, and a stop would lose them.
	(cd "$VK" && VK_STRESS_CHECK_EVERY=0 stdbuf -oL ./vk-stress "$T") > "$OUT/$name-vk.txt" 2>&1
	[ -n "$Z" ] && wait "$Z"
	kill "$H" "$C"; while kill -0 "$H" 2>/dev/null; do sleep 0.1; done
	echo "== $name: $(grep -o 'frames .*Gpix-iter/s)' "$OUT/$name-vk.txt"), $(tail -1 "$OUT/$name-vk.txt")"
	desktop || { echo "DESKTOP DIED during $name"; exit 3; }
}

phase gpu 0
echo "cool-down $COOL s"; sleep "$COOL"
phase cpugpu 1
echo "end $(date +%T), kwin $(pgrep -u "$(id -u)" -x kwin_wayland), plasmashell $(pgrep -u "$(id -u)" -x plasmashell), output $OUT"
