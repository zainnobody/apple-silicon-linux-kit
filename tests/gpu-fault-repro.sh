#!/bin/bash
# Try to reproduce the 2026-10-26 23:22 GPU render fault (docs/gpu-fault-2026-10-26.md).
# Runs vk-stress (compute) together with Wayland render clients on the logged-in desktop.
# Every render client runs with ASAHI_MESA_DEBUG=bodumpverbose, so its stderr holds a list of
# live BOs with their GPU addresses once per second. On a fault, the script looks up the
# fault address in those lists.
#
# Usage: gpu-fault-repro.sh [seconds]   (default 300; run as the desktop user, no root)
#   PLASMA=1  also restart plasmashell with the same debug option (the client that faulted).
#   VKSTRESS  path to vk-stress (default ~/vktest/vk-stress)
# Output folder: ~/gpu-fault-repro/<time>. Last line: REPRO_FAULT or REPRO_NO_FAULT.
set -u

SECONDS_RUN=${1:-300}
VKSTRESS=${VKSTRESS:-$HOME/vktest/vk-stress}
OUT=$HOME/gpu-fault-repro/$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"

export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}
# The same SiliconForest Mesa paths as the desktop session (install/m3-installed).
MESA=${MESA:-/opt/mesa-m3}
export LD_LIBRARY_PATH=$MESA/lib64 LIBGL_DRIVERS_PATH=$MESA/lib64/dri GBM_BACKENDS_PATH=$MESA/lib64/gbm
export VK_DRIVER_FILES=$MESA/share/vulkan/icd.d/asahi_icd.aarch64.json
DBG=bodumpverbose

[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] || { echo "no Wayland socket $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"; exit 1; }
[ -x "$VKSTRESS" ] || { echo "no vk-stress at $VKSTRESS"; exit 1; }

PIDS=()
cleanup() {
	for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; done
	wait 2>/dev/null
}
trap cleanup EXIT INT TERM

START=$(date '+%Y-%m-%d %H:%M:%S')
echo "start $START, $SECONDS_RUN s, output $OUT"
journalctl -k -f --since "$START" --no-pager >"$OUT/kernel.log" 2>&1 &
PIDS+=($!)

# Render clients. Each restarts when it exits, until the time is over.
client() {
	local name=$1; shift
	(
		end=$((SECONDS + SECONDS_RUN))
		while [ $SECONDS -lt $end ]; do
			ASAHI_MESA_DEBUG=$DBG timeout $((end - SECONDS)) "$@" >>"$OUT/$name.out" 2>>"$OUT/$name.err"
			echo "exit $? at $(date +%T)" >>"$OUT/$name.out"
			sleep 1
		done
	) &
	PIDS+=($!)
}
client glmark2 glmark2-wayland --run-forever --size 800x600
client es2gears es2gears_wayland
client vkcube vkcube --wsi wayland

if [ "${PLASMA:-0}" = 1 ]; then
	echo "restarting plasmashell with ASAHI_MESA_DEBUG=$DBG"
	kquitapp6 plasmashell >/dev/null 2>&1 || pkill -x plasmashell
	sleep 2
	ASAHI_MESA_DEBUG=$DBG setsid plasmashell >"$OUT/plasmashell.out" 2>"$OUT/plasmashell.err" </dev/null &
	disown
fi

sleep 10
# vk-stress loads vk-stress.spv from the current folder.
(cd "$(dirname "$VKSTRESS")" && "$VKSTRESS" "$((SECONDS_RUN - 10))") >"$OUT/vk-stress.log" 2>&1 ||
	echo "vk-stress failed, see $OUT/vk-stress.log"
sleep 3

if [ "${PLASMA:-0}" = 1 ]; then
	# Give the desktop back its normal plasmashell, without the debug output.
	kquitapp6 plasmashell >/dev/null 2>&1 || pkill -x plasmashell
	sleep 2
	setsid plasmashell >/dev/null 2>&1 </dev/null &
	disown
fi

tail -3 "$OUT/vk-stress.log"
if ! grep -q "GPU fault" "$OUT/kernel.log"; then
	echo REPRO_NO_FAULT
	exit 0
fi

grep -E "GPU fault|fault bank|recovery:|sticky" "$OUT/kernel.log" | head -20
# Kernel line: "G15: fault bank 0: status 0x.. va 0x5be305f400 (read unmapped level 0 unit 0x40 ctx 18)".
# Look up each fault address in the BO lists: "<handle>: <label> <n> KiB va=0x.. span=0x..".
for addr in $(grep -oE "fault bank [0-9]+: status 0x[0-9a-f]+ va 0x[0-9a-f]+" "$OUT/kernel.log" | awk '{print $NF}' | sort -u); do
	echo "== BOs that contain $addr"
	cat "$OUT"/*.err 2>/dev/null | awk -v a="$addr" '
		/ va=0x/ {
			for (i = 1; i <= NF; i++) {
				if ($i ~ /^va=/) va = strtonum(substr($i, 4))
				if ($i ~ /^span=/) sp = strtonum(substr($i, 6))
			}
			x = strtonum(a)
			if (va && x >= va && x < va + sp) print
		}' | sort | uniq -c | sort -rn | head -5
done
echo REPRO_FAULT
