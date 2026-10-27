#!/bin/bash
# Fan curve for the MacBook Pro M3 Pro under Linux.
# Under Linux the SMC keeps both fans at target 0 (off), even at a 100 C hotspot,
# because no OS service asks it for cooling (macOS has thermalmonitord).
# Needs macsmc_hwmon with patches/macsmc-hwmon-ftst-unlock.patch, loaded with fan_control=1.
#
# Input: the hotter of the SoC die zone and (PMP hotspot - 10 C), smoothed.
# Output: the same target on both fans, clamped to each fan's min and max.
# A step up is at once; a step down waits HOLD readings, because the hotspot is spiky.
# Below the first step the fans go back to SMC auto mode (target 0).
# On any exit, error or unreadable sensor, the fans go back to auto.
set -u

INTERVAL=2        # seconds between readings
HYST=3            # C a reading must fall below a step before the fans slow down
HOLD=15           # readings (30 s) a lower step must hold before the fans slow down
# temperature (C) : fan target (rpm); 0 = SMC auto
STEPS=(
	"62:1500"
	"70:2200"
	"78:3000"
	"86:4000"
	"92:5000"
)

hw() { grep -l "^$1\$" /sys/class/hwmon/hwmon*/name 2>/dev/null | head -1 | xargs -r dirname; }
FAN=$(hw macsmc_hwmon)
DIE=$(hw macsmc_soc_die)
HOT=$(hw apple_pmp_hotspot)
[ -n "$FAN" ] && [ -w "$FAN/fan1_target" ] || { echo "fan targets not writable: load macsmc_hwmon with fan_control=1" >&2; exit 1; }

set_all() { # returns 1 if a write failed (the unlock can take more than the driver's 10 s)
	local want=$1 f min max v rc=0
	for f in 1 2; do
		[ -e "$FAN/fan${f}_target" ] || continue
		v=$want
		if [ "$v" -gt 0 ]; then
			min=$(cat "$FAN/fan${f}_min"); max=$(cat "$FAN/fan${f}_max")
			[ "$v" -lt "$min" ] && v=$min
			[ "$v" -gt "$max" ] && v=$max
		fi
		echo "$v" > "$FAN/fan${f}_target" 2>/dev/null || rc=1
	done
	return $rc
}
to_auto() { set_all 0; echo "fans back to SMC auto"; }
trap 'to_auto; exit 0' TERM INT
trap to_auto EXIT

read_c() { local raw; raw=$(cat "$1" 2>/dev/null) || return 1; [ -n "$raw" ] || return 1; echo $(( raw / 1000 )); }

# level -2 = unknown, so the first reading always writes the fans (after a restart they can be in manual mode)
ema=0; cur=0; level=-2; low=0
while :; do
	d=$(read_c "$DIE/temp1_input") || { echo "SoC die sensor unreadable" >&2; set_all 0; level=-2; sleep "$INTERVAL"; continue; }
	t=$d
	if [ -n "$HOT" ] && h=$(read_c "$HOT/temp1_input"); then
		[ $(( h - 10 )) -gt "$t" ] && t=$(( h - 10 ))
	fi
	# EMA with alpha 0.4 on whole degrees; a rise counts at once, a fall slowly
	if [ "$ema" -eq 0 ] || [ "$t" -gt "$ema" ]; then ema=$t; else ema=$(( (ema * 6 + t * 4) / 10 )); fi

	new=-1
	for i in "${!STEPS[@]}"; do
		th=${STEPS[$i]%%:*}
		if [ "$i" -le "$level" ]; then th=$(( th - HYST )); fi
		[ "$ema" -ge "$th" ] && new=$i
	done
	if [ "$new" -lt "$level" ]; then
		low=$(( low + 1 ))
		[ "$low" -lt "$HOLD" ] && new=$level
	else
		low=0
	fi
	if [ "$new" -ne "$level" ]; then
		if [ "$new" -lt 0 ]; then want=0; else want=${STEPS[$new]##*:}; fi
		if set_all "$want"; then
			level=$new; low=0; cur=$want
			echo "$(date +%T) temp ${ema} C (die ${d} C) -> fans ${cur} rpm"
		else
			echo "$(date +%T) fan write failed for ${want} rpm, will retry" >&2
		fi
	fi
	sleep "$INTERVAL"
done
