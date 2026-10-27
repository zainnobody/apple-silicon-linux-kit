#!/usr/bin/env bash
# One-thread memory read with the P cluster on the performance governor, then back to the
# previous governor (restored on exit, also on Ctrl-C or error). Sysfs only, no reboot.
# Run with sudo: tests/governor-bw-test.sh [test dir with bw4-gcc-pt] [cpu]
set -u
D="${1:-/home/user/bwtest}"
CPU="${2:-7}"
[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }
B="$D/bw4-gcc-pt"
[ -x "$B" ] || { echo "No $B" >&2; exit 1; }
POL="$(readlink -f /sys/devices/system/cpu/cpu$CPU/cpufreq)"
OLD="$(cat "$POL/scaling_governor")"
restore() { echo "$OLD" > "$POL/scaling_governor"; echo "governor restored: $(cat "$POL/scaling_governor")"; }
trap restore EXIT

hist() { for i in $(seq 1 40); do cat "$POL/scaling_cur_freq"; sleep 0.05; done | sort -n | uniq -c | tr '\n' ' '; echo; }
run() { # <label>
	hist > /tmp/gov-hist.txt &
	local r; r="$(taskset -c "$CPU" "$B" 60)"
	wait
	echo "$1: $r"
	echo "  clock samples (count kHz): $(cat /tmp/gov-hist.txt)"
}

echo "policy $POL, cpus $(cat "$POL/related_cpus"), governor $OLD"
run "$OLD"
echo performance > "$POL/scaling_governor"
run "performance"
restore
trap - EXIT
run "$OLD again"
echo GOVERNOR_TEST_DONE
