#!/bin/bash
# Restart-loop test for a sensor that sees a finger only in certain moments after a fresh capture start.
# Each cycle is a complete new verify (sensor power-up, the 1.8 s pause, arm, the finger-detect window), cancelled after
# LOOP_CYCLE_S seconds. The USER holds ONE finger on the sensor, or touches it on request. Stops at the first MATCH or NO MATCH.
#   loopverify.sh [CYCLES]        default 12 cycles of 4 s (about 55 s). Needs apple_sep loaded (touchid-3b.sh load, open).
#   loopverify.sh --marks         touch-timing run: 24 cycles of 7 s (about 3 min), keeps going after a result and stops after
#                                 6 results (LOOP_MAX_RESULTS), saves the kernel log and, if touch marks exist, prints the report.
#                                 Start touchmark.py in a second terminal tab first. See docs/features/touchid-3f-test-plan.md.
# A cycle must be longer than the pause (1.8 s) plus the bring-up (about 0.7 s) plus the window (0.3 s), or the cancel lands
# before the sensor arms and the cycle tests nothing. A cancelled cycle without a frame writes nothing to the xART store;
# every MATCH or NO MATCH writes (like any verify). The alarm check runs at the end.
set -u
KEEP="${LOOP_KEEP_GOING:-0}"; MAXRES="${LOOP_MAX_RESULTS:-6}"; T="${LOOP_CYCLE_S:-4}"
if [ "${1:-}" = "--marks" ]; then N=24; T="${LOOP_CYCLE_S:-7}"; KEEP=1; else N="${1:-12}"; fi
out=~/window/loop.out; : > "$out"
say() { echo "$*" | tee -a "$out"; }
[ "$(id -u)" != 0 ] || { say "STOP: run as the user, not with sudo"; exit 1; }
if [ -z "${LOOP_TEST:-}" ]; then
	sudo -n true 2>/dev/null || { say "STOP: sudo -n does not work (the sudo window is closed)"; exit 1; }
	lsmod | grep -q '^apple_sep' || { say "STOP: apple_sep is not loaded (run touchid-3b.sh load and open first)"; exit 1; }
	[ -e /dev/sep-bio ] || { say "STOP: /dev/sep-bio does not exist"; exit 1; }
fi
case "$N$T$MAXRES" in *[!0-9]*|"") say "STOP: cycles, LOOP_CYCLE_S and LOOP_MAX_RESULTS must be whole numbers"; exit 1;; esac
[ "$T" -ge 3 ] || { say "STOP: LOOP_CYCLE_S below 3 s cancels before the sensor arms"; exit 1; }
start_epoch=$(date +%s)
say "loop start $(date +%T), $N cycles of $T s$([ "$KEEP" = 1 ] && echo ", keeps going, at most $MAXRES results")"
bad=0; res=none; results=0; i=0
for i in $(seq 1 "$N"); do
	o=$(sudo -n env SEPBIO_VERIFY_TIMEOUT="$T" python3 -I ~/window/touchid/sepbio.py verify 2>&1)
	r=$(printf '%s\n' "$o" | grep -E '^VERIFY' | tail -1)
	echo "$(date +%T) cycle $i: ${r:-<no VERIFY line: $(printf '%s' "$o" | tail -n 1 | cut -c1-100)>}" >> "$out"
	case "$r" in
		"VERIFY: MATCH"*|"VERIFY: NO MATCH"*)
			results=$((results + 1)); res="${r%%,*}"; res="${res%% (*}"; bad=0
			if [ "$KEEP" != 1 ] || [ "$results" -ge "$MAXRES" ]; then break; fi;;
		"VERIFY: no result"*) bad=0;;
		*) bad=$((bad + 1)); [ "$bad" -ge 2 ] && { res="STOPPED: two errors in a row"; break; };;
	esac
	sleep 0.5
done
say "loop end $(date +%T): last result $res, $results results in $i cycles"
if [ -z "${LOOP_TEST:-}" ]; then
	stamp=$(date +%Y%m%d-%H%M%S); jf=~/window/loop-$stamp.journal
	sudo -n journalctl -k -o short-unix --since "@$start_epoch" --no-pager > "$jf" 2>/dev/null && say "kernel log saved: $jf"
	if [ -s ~/window/touch.marks ] && [ -f ~/window/touchmark-report.py ]; then
		awk -v s="$start_epoch" '/^[0-9]/ && $1 >= s - 5 { print }' ~/window/touch.marks > "$jf.marks"
		if [ -s "$jf.marks" ]; then python3 -I ~/window/touchmark-report.py "$jf" "$jf.marks" "$T" 2>&1 | tee -a "$out"; fi
	fi
	"$HOME/window/touchid-3b.sh" alarm 2>&1 | tail -n 12 | tee -a "$out"
fi
