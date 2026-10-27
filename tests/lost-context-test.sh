#!/bin/bash
# Test for patches/mesa-asahi-lost-context-noop.patch. Runs Wayland GL clients with
# tests/lost-context-inject.c (LD_PRELOAD): after LOST_AFTER_S seconds, VM_BIND, GEM_CREATE and
# SUBMIT fail with EIO, as after a real GPU fault. Each client runs once with the installed Mesa
# and once with the patched Mesa prefix. A client passes when it is still running at the end
# (timeout exit 124), and fails when it dies (SIGSEGV 139, SIGABRT 134, other).
# Usage: lost-context-test.sh <patched prefix> [seconds per run]   (run as the desktop user)
#   INJECT  path to lost-context-inject.so (default: built from ~/m3gpu/lost-context-inject.c)
set -u

NEW=${1:?patched Mesa prefix}
T=${2:-30}
OLD=${OLD:-/opt/mesa-m3}
LOST_AFTER_S=${LOST_AFTER_S:-5}
OUT=$HOME/gpu-perf/lost-context-$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}

INJECT=${INJECT:-$OUT/lost-context-inject.so}
if [ ! -f "$INJECT" ]; then
	gcc -O2 -shared -fPIC -I "$HOME/m3gpu/src/mesa/include/drm-uapi" -o "$INJECT" \
		"$HOME/m3gpu/lost-context-inject.c" -ldl || exit 1
fi

run() {
	local mesa=$1 label=$2 name=$3; shift 3
	local log="$OUT/$name-$label.log"
	LD_LIBRARY_PATH=$mesa/lib64 LIBGL_DRIVERS_PATH=$mesa/lib64/dri GBM_BACKENDS_PATH=$mesa/lib64/gbm \
		VK_DRIVER_FILES=$mesa/share/vulkan/icd.d/asahi_icd.aarch64.json \
		LD_PRELOAD=$INJECT LOST_AFTER_S=$LOST_AFTER_S timeout "$T" "$@" >"$log" 2>&1
	local rc=$?
	local verdict=FAIL
	[ $rc = 124 ] && verdict=PASS
	printf '%-10s %-8s rc=%-3s %s  (injected: %s, BO failures: %s)\n' "$name" "$label" "$rc" "$verdict" \
		"$(grep -c 'lost-context-inject' "$log")" "$(grep -c 'failed' "$log")" | tee -a "$OUT/summary.txt"
	sleep 2
}

for mesa in "$OLD installed" "$NEW patched"; do
	set -- $mesa
	run "$1" "$2" es2gears es2gears_wayland
	run "$1" "$2" glmark2 glmark2-wayland --run-forever --size 640x480
	run "$1" "$2" vkcube vkcube --wsi wayland
done
echo "output $OUT"
