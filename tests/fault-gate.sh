#!/bin/bash
# Fault gate: causes real GPU faults on purpose while a desktop-like client set runs, then checks
# that only the faulting client failed. Run it after every kernel or Mesa change, before any
# other test. It FAULTS THE GPU: only with the coordinator's go (docs/gpu-fault-2026-10-26.md).
#
# Triggers (llama.cpp test switches, ane-linux/llm/llama-vk-honeykrisp-test-switches.patch):
#   tiles   GGML_VK_HK_TILES=s, pp512 (the 08:39 fault)
#   bk64    GGML_VK_HK_MWARP=128,128,64,64,64,32,2,4,4,1,32 GGML_VK_HK_NOROLL=1, pp512 (the 08:52 fault)
# Clients during the triggers: vkcube, glmark2-wayland (windowed), es2gears_wayland,
# robust-reset-test (LOSE_CONTEXT_ON_RESET, surfaceless). kwin_wayland and plasmashell are watched.
#
# Usage: fault-gate.sh [tiles runs] [bk64 runs]   (default 5 and 3; as the desktop user, no root)
# PASS when, over the whole run:
#   - kwin_wayland, plasmashell and every client keep their PIDs,
#   - no core dump except llama-bench,
#   - no fail-stop line, every recovery ends with halted=0,
#   - every trigger run ends with an error exit (the faulting client sees a clean error),
#   - the kernel logs one "GPU fault" or more per trigger run.
set -u
TILES_RUNS=${1:-5}
BK64_RUNS=${2:-3}
LLAMA=${LLAMA:-$HOME/llm-work/llama.cpp/build/bin/llama-bench}
MODEL=${MODEL:-$HOME/llm-work/models/Meta-Llama-3.1-8B-Instruct-Q4_0-requant.gguf}
ROBUST=${ROBUST:-$HOME/m3gpu/robust-reset-test}
MESA=${MESA:-/opt/mesa-m3}
OUT=$HOME/gpu-fault-gate/$(date +%Y%m%d-%H%M%S)
mkdir -p "$OUT"
export LD_LIBRARY_PATH=$MESA/lib64 LIBGL_DRIVERS_PATH=$MESA/lib64/dri GBM_BACKENDS_PATH=$MESA/lib64/gbm
export VK_DRIVER_FILES=$MESA/share/vulkan/icd.d/asahi_icd.aarch64.json
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}

# Heat sampling (tests/heat-sample.sh, next to this script or in ~/m3gpu): max temps and fan rpm.
HEAT=${HEAT:-$(dirname "$(readlink -f "$0")")/heat-sample.sh}
[ -x "$HEAT" ] || HEAT=$HOME/m3gpu/heat-sample.sh
HEAT_PID=
heat_start() { [ -x "$HEAT" ] && { "$HEAT" "$1" > "${1%.csv}.txt" & HEAT_PID=$!; }; }
# heat_stop polls until the sampler is gone: wait alone does not work when heat_stop runs in a pipeline.
heat_stop() {
	[ -n "$HEAT_PID" ] || return 0
	kill "$HEAT_PID" 2>/dev/null
	while kill -0 "$HEAT_PID" 2>/dev/null; do sleep 0.1; done
	wait "$HEAT_PID" 2>/dev/null
	HEAT_PID=
	cat "${1%.csv}.txt" 2>/dev/null
}

say() { echo "$*" | tee -a "$OUT/summary.txt"; }
FAIL=0
fail() { say "FAIL: $*"; FAIL=1; }

[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] || { echo "no Wayland socket"; exit 2; }
for f in "$LLAMA" "$MODEL" "$ROBUST"; do [ -e "$f" ] || { echo "missing $f"; exit 2; }; done
grep -q Charging /sys/class/power_supply/macsmc-battery/status ||
	grep -q Full /sys/class/power_supply/macsmc-battery/status || { echo "not on the charger"; exit 2; }

START=$(date '+%Y-%m-%d %H:%M:%S')
say "fault gate: start $START, tiles $TILES_RUNS, bk64 $BK64_RUNS, kernel $(uname -r), output $OUT"
heat_start "$OUT/heat.csv"

declare -A PID
PID[kwin_wayland]=$(pgrep -u "$(id -u)" -x kwin_wayland | head -1)
PID[plasmashell]=$(pgrep -u "$(id -u)" -x plasmashell | head -1)
vkcube --wsi wayland > "$OUT/vkcube.log" 2>&1 & PID[vkcube]=$!
glmark2-wayland --run-forever --size 640x400 > "$OUT/glmark2.log" 2>&1 & PID[glmark2]=$!
es2gears_wayland > "$OUT/es2gears.log" 2>&1 & PID[es2gears]=$!
"$ROBUST" 100000 > "$OUT/robust.log" 2>&1 & PID[robust]=$!
CLIENTS="vkcube glmark2 es2gears robust"
cleanup() {
	for c in $CLIENTS; do kill "${PID[$c]}" 2>/dev/null; done
	heat_stop "$OUT/heat.csv" > /dev/null
}
trap cleanup EXIT INT TERM
sleep 5
for n in "${!PID[@]}"; do say "pid $n ${PID[$n]:-none}"; done

alive() {
	local n bad=0
	for n in "${!PID[@]}"; do
		if [ -z "${PID[$n]}" ] || ! kill -0 "${PID[$n]}" 2>/dev/null; then
			fail "after $1: $n (pid ${PID[$n]:-none}) is gone"
			bad=1
		fi
	done
	return $bad
}

trigger() {
	local name=$1 run=$2; shift 2
	local log="$OUT/$name-$run.log" before after rc
	before=$(journalctl -k --since "$START" --no-pager | grep -c 'GPU fault')
	env "$@" timeout 300 "$LLAMA" -m "$MODEL" -p 512 -n 0 -fa 1 -ngl 99 -r 1 > "$log" 2>&1
	rc=$?
	sleep 3
	after=$(journalctl -k --since "$START" --no-pager | grep -c 'GPU fault')
	say "$name run $run: exit $rc, GPU faults +$((after - before)), $(grep -o 'DeviceLost[A-Za-z]*\|ErrorDeviceLost\|device lost' "$log" | head -1)"
	[ "$rc" = 0 ] && fail "$name run $run: llama-bench exit 0 (no clean error seen)"
	[ "$rc" = 124 ] && fail "$name run $run: llama-bench timed out"
	[ $((after - before)) -ge 1 ] || say "note: $name run $run caused no GPU fault"
	alive "$name run $run"
}

for r in $(seq 1 "$TILES_RUNS"); do trigger tiles "$r" GGML_VK_HK_TILES=s; done
for r in $(seq 1 "$BK64_RUNS"); do
	trigger bk64 "$r" GGML_VK_HK_MWARP=128,128,64,64,64,32,2,4,4,1,32 GGML_VK_HK_NOROLL=1
done
sleep 5
alive "the last run"

journalctl -k --since "$START" --no-pager > "$OUT/kernel.log"
faults=$(grep -c 'GPU fault' "$OUT/kernel.log")
failstop=$(grep -c 'fail-stop' "$OUT/kernel.log")
unanswered=$(grep -c 'further halt not answered\|not drained\|resume not consumed\|did not halt' "$OUT/kernel.log")
lostdev=$(grep -c 'the client sees a lost device' "$OUT/kernel.log")
resumed_bad=$(grep 'recovery resumed:' "$OUT/kernel.log" | grep -vc 'halted=0')
say "kernel: GPU faults $faults, fail-stop $failstop, handshake failures $unanswered, lost-device lines $lostdev, resumed with halted=1: $resumed_bad"
say "halts answered per recovery: $(grep -o 'further halt [0-9]* seen' "$OUT/kernel.log" | awk '{print $3}' | sort | uniq -c | tr '\n' ' ')"
[ "$failstop" = 0 ] || fail "fail-stop in the kernel log"
[ "$unanswered" = 0 ] || fail "recovery handshake failure lines"
[ "$resumed_bad" = 0 ] || fail "a recovery resumed with halted=1"
[ "$faults" -ge 1 ] || fail "no GPU fault at all: the triggers did not test anything"

coredumpctl list --since "$START" --no-pager --no-legend 2>/dev/null > "$OUT/coredumps.txt"
others=$(grep -v 'llama-bench' "$OUT/coredumps.txt" | grep -c .)
say "core dumps: $(grep -c . "$OUT/coredumps.txt") (other than llama-bench: $others)"
[ "$others" = 0 ] || { fail "core dumps of other processes"; cat "$OUT/coredumps.txt" | tee -a "$OUT/summary.txt"; }
grep -q 'reset seen' "$OUT/robust.log" && fail "the robust client saw a reset (an innocent context was hit)"

heat_stop "$OUT/heat.csv" | tee -a "$OUT/summary.txt"
if [ "$FAIL" = 0 ]; then say "FAULT_GATE_PASS"; else say "FAULT_GATE_FAIL"; fi
exit $FAIL
