#!/bin/bash
# Restart-loop test for a sensor that sees a finger only in the first ~250 ms after a fresh capture start.
# Each cycle is a complete new verify (sensor power-up, the 1.8 s pause, arm, the finger-detect window), cancelled after
# LOOP_CYCLE_S seconds. The USER holds ONE finger on the sensor for the whole run. Stops at the first MATCH or NO MATCH.
#   loopverify.sh [CYCLES]        default 12 cycles of 4 s (about 55 s). Needs apple_sep loaded (touchid-3b.sh load).
# A cycle must be longer than the pause (1.8 s) plus the bring-up (about 0.7 s) plus the window (0.3 s), or the cancel lands
# before the sensor arms and the cycle tests nothing. A cancelled cycle without a frame writes nothing to the xART store;
# only the final MATCH or NO MATCH writes (like any verify). The alarm check runs at the end.
set -u
N="${1:-12}"; T="${LOOP_CYCLE_S:-4}"
out=~/window/loop.out; : > "$out"
say() { echo "$*" | tee -a "$out"; }
[ "$(id -u)" != 0 ] || { say "STOP: run as the user, not with sudo"; exit 1; }
if [ -z "${LOOP_TEST:-}" ]; then
	sudo -n true 2>/dev/null || { say "STOP: sudo -n does not work (the sudo window is closed)"; exit 1; }
	lsmod | grep -q '^apple_sep' || { say "STOP: apple_sep is not loaded (run touchid-3b.sh load and open first)"; exit 1; }
	[ -e /dev/sep-bio ] || { say "STOP: /dev/sep-bio does not exist"; exit 1; }
fi
case "$N$T" in *[!0-9]*|"") say "STOP: cycles and LOOP_CYCLE_S must be whole numbers"; exit 1;; esac
[ "$T" -ge 3 ] || { say "STOP: LOOP_CYCLE_S below 3 s cancels before the sensor arms"; exit 1; }
say "loop start $(date +%T), $N cycles of $T s, hold one finger on the sensor now"
bad=0; res=none
for i in $(seq 1 "$N"); do
	o=$(sudo -n env SEPBIO_VERIFY_TIMEOUT="$T" python3 -I ~/window/touchid/sepbio.py verify 2>&1)
	r=$(printf '%s\n' "$o" | grep -E '^VERIFY' | tail -1)
	echo "$(date +%T) cycle $i: ${r:-<no VERIFY line: $(printf '%s' "$o" | tail -n 1 | cut -c1-100)>}" >> "$out"
	case "$r" in
		"VERIFY: MATCH"*) res=MATCH; break;;
		"VERIFY: NO MATCH"*) res="NO MATCH"; break;;
		"VERIFY: no result"*) bad=0;;
		*) bad=$((bad + 1)); [ "$bad" -ge 2 ] && { res="STOPPED: two errors in a row"; break; };;
	esac
	sleep 0.5
done
say "loop end $(date +%T): result $res after $i cycles"
[ -n "${LOOP_TEST:-}" ] || "$HOME/window/touchid-3b.sh" alarm 2>&1 | tail -n 12 | tee -a "$out"
