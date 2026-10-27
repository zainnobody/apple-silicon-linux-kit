#!/bin/bash
# GPU performance suite for the Linux against macOS comparison (docs/performance.md).
# Runs each test alone, one after the other. Run as the desktop user, no root.
# Usage: gpu-perf-suite.sh [seconds per stress test]   (default 60)
#   BIN  folder with vk-stress, vk-stress.spv, vk-bandwidth, vk-bandwidth.spv (default ~/vktest)
#   GLES path to gles-stress (default ~/m3gpu/out/gles-stress)
#   SKIP_GLMARK=1 skips the glmark2 window run.
# Output: ~/gpu-perf/<time>/summary.txt. Close other GPU programs first for clean numbers.
set -u

T=${1:-60}
BIN=${BIN:-$HOME/vktest}
GLES=${GLES:-$HOME/m3gpu/out/gles-stress}
OUT=$HOME/gpu-perf/$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
MESA=${MESA:-/opt/mesa-m3}
export LD_LIBRARY_PATH=$MESA/lib64 LIBGL_DRIVERS_PATH=$MESA/lib64/dri GBM_BACKENDS_PATH=$MESA/lib64/gbm
export VK_DRIVER_FILES=$MESA/share/vulkan/icd.d/asahi_icd.aarch64.json
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}
START=$(date '+%Y-%m-%d %H:%M:%S')
# Heat sampling (tests/heat-sample.sh, next to this script or in ~/m3gpu): max temps and fan rpm.
HEAT=${HEAT:-$(dirname "$(readlink -f "$0")")/heat-sample.sh}
[ -x "$HEAT" ] || HEAT=$HOME/m3gpu/heat-sample.sh
HEAT_PID=
heat_start() { [ -x "$HEAT" ] && { "$HEAT" "$1" > "${1%.csv}.txt" & HEAT_PID=$!; }; }
heat_stop() { [ -n "$HEAT_PID" ] || return 0; kill "$HEAT_PID" 2>/dev/null; wait "$HEAT_PID" 2>/dev/null; HEAT_PID=; cat "${1%.csv}.txt" 2>/dev/null; }
heat_start "$OUT/heat.csv"

say() { echo "$*" | tee -a "$OUT/summary.txt"; }
run() {
	local name=$1; shift
	(cd "$BIN" && "$@") >"$OUT/$name.log" 2>&1
	say "$name: $(grep -E 'Gpix|GB/s|Score|check time' "$OUT/$name.log" | tr '\n' ' ')"
	sleep 5
}

say "GPU suite $START, $T s per stress test, $(uname -r)"
say "GPU clients now: $(ls -l /proc/[0-9]*/fd 2>/dev/null | grep -c 'renderD\|card1')"

# Compute: as metal-stress (wait and CPU check every 10th frame), then never waiting.
run vk-stress-check10 ./vk-stress "$T"
VK_STRESS_CHECK_EVERY=0 run vk-stress-nowait ./vk-stress "$T"
VK_STRESS_CHECK_EVERY=100 run vk-stress-check100 ./vk-stress "$T"

# Compute with a small render client that keeps the GPU awake (es2gears, about 60 frames/s).
timeout $((T + 10)) es2gears_wayland >/dev/null 2>&1 &
sleep 3
run vk-stress-check10-keepawake ./vk-stress "$T"
wait

# Fragment shader version of the same math.
[ -x "$GLES" ] && run gles-stress "$GLES" "$T"

# Memory read.
run vk-bandwidth ./vk-bandwidth 512 20 16

# Real 3D scenes in a window.
if [ "${SKIP_GLMARK:-0}" != 1 ]; then
	glmark2-wayland --size 1920x1080 >"$OUT/glmark2.log" 2>&1
	say "glmark2 1920x1080: $(grep 'glmark2 Score' "$OUT/glmark2.log")"
fi

say "kernel GPU faults since start: $(journalctl -k --since "$START" --no-pager | grep -c 'GPU fault')"
heat_stop "$OUT/heat.csv" | tee -a "$OUT/summary.txt"
say "output $OUT"
