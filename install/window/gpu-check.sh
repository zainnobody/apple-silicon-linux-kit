#!/usr/bin/env bash
# After the GPU clock test boot: checks that asahi.g15_perf_tgt_util=50 took effect, then runs a
# short GPU check. Changes nothing. Run as the desktop user (no root). About 3.5 min.
# PASS: the parameter is on the boot line and the driver logged it, the stop-and-go pattern
#       (vk-stress, CPU check every 10th frame) is at least 70 G, 10 % above the stage O value (63-64 G
#       default, 81 G with uclamp; target 120 G or more), the no-wait run stays at 250 G or more,
#       0 wrong samples, and no GPU fault or fail-stop in this boot.
set -u
MESA=${MESA:-/opt/mesa-m3}
export LD_LIBRARY_PATH=$MESA/lib64 VK_DRIVER_FILES=$MESA/share/vulkan/icd.d/asahi_icd.aarch64.json
VK=${VK:-$HOME/vktest}
HEAT=$HOME/m3gpu/heat-sample.sh
OUT=$HOME/gpu-perf/gpu-check-$(date +%Y%m%d-%H%M%S); mkdir -p "$OUT"
FAIL=0
say() { echo "$*" | tee -a "$OUT/summary.txt"; }
fail() { say "FAIL: $*"; FAIL=1; }

say "gpu-check $(date +%T), kernel $(uname -r), $(cat /sys/class/power_supply/macsmc-battery/status)"
grep -qw asahi.g15_perf_tgt_util=50 /proc/cmdline && say "boot line: asahi.g15_perf_tgt_util=50" || fail "parameter not on the boot line"
line=$(journalctl -k -b --no-pager | grep -m1 "DVFS target utilization")
[ -n "$line" ] && say "driver: ${line#*gpu: }" || fail "the driver did not log the DVFS target"
echo "$line" | grep -q "utilization 50 %" || fail "DVFS target is not 50 %"

[ -x "$HEAT" ] && { "$HEAT" "$OUT/heat.csv" > "$OUT/heat.txt" & H=$!; }
run() { # name, check-every, seconds
	local r
	r=$(cd "$VK" && VK_STRESS_CHECK_EVERY=$2 ./vk-stress "$3" 2>&1 | tee "$OUT/$1.txt")
	say "$1: $(echo "$r" | grep -o '[0-9.]* Gpix-iter/s'), $(echo "$r" | grep -o 'CPU check time [0-9.]* ms' || true), $(echo "$r" | grep -o 'wrong samples [0-9]*')"
	echo "$r" | grep -q STRESS_PASS || fail "$1: STRESS_PASS missing"
}
run check10 10 60
# the same pattern with the CPU help from G1 (P core 7, uclamp.min 1024)
r=$(cd "$VK" && VK_STRESS_CHECK_EVERY=10 uclampset -m 1024 taskset -c 7 ./vk-stress 60 2>&1 | tee "$OUT/check10-uclamp.txt")
say "check10 uclamp P core: $(echo "$r" | grep -o '[0-9.]* Gpix-iter/s'), $(echo "$r" | grep -o 'CPU check time [0-9.]* ms' || true)"
run nowait 0 30
[ -n "${H:-}" ] && { kill "$H"; while kill -0 "$H" 2>/dev/null; do sleep 0.1; done; cat "$OUT/heat.txt" | tee -a "$OUT/summary.txt"; }

g10=$(grep -o '[0-9.]* Gpix-iter/s' "$OUT/check10.txt" | cut -d' ' -f1)
g0=$(grep -o '[0-9.]* Gpix-iter/s' "$OUT/nowait.txt" | cut -d' ' -f1)
awk -v a="${g10:-0}" 'BEGIN { exit !(a >= 70) }' || fail "check10 ${g10:-none} G is not 10 % above the stage O default (63-64 G)"
awk -v a="${g10:-0}" 'BEGIN { exit !(a >= 120) }' && say "target: check10 ${g10} G reaches 120 G" || say "target: check10 ${g10:-none} G is below 120 G"
awk -v a="${g0:-0}" 'BEGIN { exit !(a >= 250) }' || fail "no-wait ${g0:-none} G is below 250 G"
f=$(journalctl -k -b --no-pager | grep -c "GPU fault\|fail-stop")
[ "$f" = 0 ] || fail "$f GPU fault or fail-stop lines in this boot"
say "next boot: $(sudo -n grub2-editenv list 2>/dev/null | grep -E 'next_entry|saved_entry' | tr '\n' ' ' || echo 'not readable without root')"
[ "$FAIL" = 0 ] && say "GPU_CHECK_PASS" || say "GPU_CHECK_FAIL"
say "output $OUT"
exit $FAIL
