#!/bin/bash
# Heat sampler for load tests: every 2 s, writes the SoC, PMP and SMC temperatures and both fan
# speeds to a CSV, and prints the maximum of each column when it stops.
# Usage:
#   heat-sample.sh <csv> &                  start before the load, then kill it after the load
#   heat-sample.sh <csv> -- <command...>    run the command with sampling, keep its exit code
# Sensors: macsmc_hwmon (SoC die, NAND, battery, charger, Wi-Fi temps; Fan 1, Fan 2),
# macsmc_soc_die, apple_pmp (temp1 PMP CPU hotspot), apple_pmp_hotspot. Temps in deg C, fans in rpm.
set -u
OUT=${1:?csv path}; shift
INTERVAL=${HEAT_INTERVAL:-2}

# Column list: "label path" pairs, found by hwmon name (hwmon numbers change between boots).
COLS=()
for h in /sys/class/hwmon/hwmon*; do
	name=$(cat "$h/name" 2>/dev/null) || continue
	case $name in
	macsmc_hwmon | macsmc_soc_die | apple_pmp | apple_pmp_hotspot) ;;
	*) continue ;;
	esac
	for f in "$h"/temp*_input "$h"/fan*_input; do
		[ -r "$f" ] && cat "$f" > /dev/null 2>&1 || continue
		label=$(cat "${f%_input}_label" 2>/dev/null)
		label=${label:-$name}
		[ "$name" = apple_pmp ] && [ "$label" != "PMP CPU hotspot" ] && continue
		COLS+=("${label// /_}" "$f")
	done
done

{
	printf 'time'
	for ((i = 0; i < ${#COLS[@]}; i += 2)); do printf ',%s' "${COLS[i]}"; done
	echo
} > "$OUT"

sample() {
	printf '%s' "$(date +%T)"
	for ((i = 1; i < ${#COLS[@]}; i += 2)); do
		v=$(cat "${COLS[i]}" 2>/dev/null) || v=
		case ${COLS[i]} in
		*fan*) printf ',%s' "${v%.*}" ;;
		*) [ -n "$v" ] && printf ',%.1f' "$(echo "$v / 1000" | bc -l)" || printf ',' ;;
		esac
	done
	echo
}

summary() {
	awk -F, 'NR == 1 { for (i = 2; i <= NF; i++) h[i] = $i; n = NF; next }
		{ rows++; for (i = 2; i <= NF; i++) if ($i != "" && (m[i] == "" || $i + 0 > m[i] + 0)) m[i] = $i }
		END {
			printf "heat: %d samples\n", rows
			for (i = 2; i <= n; i++) {
				if (h[i] ~ /SoC_die|hotspot|macsmc_soc_die|PMP/) t = t sprintf(" %s=%s", h[i], m[i])
				else if (h[i] ~ /Fan/) f = f sprintf(" %s=%s", h[i], m[i])
				else o = o sprintf(" %s=%s", h[i], m[i])
			}
			print "heat max SoC (C):" t; print "heat max other (C):" o; print "heat max fan (rpm):" f
		}' "$OUT"
}

if [ "${1:-}" = -- ]; then
	shift
	( while :; do sample >> "$OUT"; sleep "$INTERVAL"; done ) &
	SAMPLER=$!
	"$@"
	rc=$?
	kill "$SAMPLER" 2> /dev/null
	wait "$SAMPLER" 2> /dev/null
	sample >> "$OUT"
	summary
	exit $rc
fi

trap 'sample >> "$OUT"; summary; exit 0' TERM INT
while :; do
	sample >> "$OUT"
	sleep "$INTERVAL" &
	wait $!
done
