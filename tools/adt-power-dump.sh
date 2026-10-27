#!/bin/bash
# Read-only dump of the Apple device tree nodes that control memory and fabric performance
# (PMC, PMP, CLPC, DCS, AMCC, PMGR performance) and of macOS memory and power facts.
# Run in macOS on the target Mac: tools/adt-power-dump.sh > adt-power.txt
# Writes nothing on the machine. powermetrics needs sudo and is skipped without it.
set -uo pipefail
echo "# $(sw_vers -productVersion) $(sysctl -n hw.model) $(date '+%Y-%m-%d %H:%M')"
# The complete device tree, for offline search (set ADT_FULL to a file path).
[ -n "${ADT_FULL:-}" ] && ioreg -p IODeviceTree -l -w0 > "$ADT_FULL"

echo "## Device tree nodes whose name matches the power and memory controllers"
ioreg -p IODeviceTree -l -w0 | grep -E '^[ |]*\+-o ' | sed 's/^[ |]*+-o //' |
	grep -iE '^(pmc|pmp|clpc|dcs|amcc|mcc|pmgr|afr|soc-tuner|dram|memory|perf|pmu|spmi|cpm|dcsc)' |
	sed 's/  <.*//' | sort -u

for node in pmc pmp clpc amcc mcc dcs soc-tuner pmgr; do
	echo "## ioreg node: $node"
	ioreg -p IODeviceTree -n "$node" -r -l -w0 2>/dev/null | head -400
done

echo "## Properties anywhere that mention dcs, afr, fabric, dram or voter"
ioreg -p IODeviceTree -l -w0 | grep -iE '"[^"]*(dcs|afr|fabric|dram|voter|perf-floor|bw-)[^"]*" =' | head -200

echo "## IOKit services for performance control"
ioreg -l -w0 -c AppleARMPerformanceController 2>/dev/null | head -100
ioreg -w0 -l | grep -iE '"(IOClass|IONameMatched)" = "[^"]*(PMP|PMC|CLPC|DCS|AFR|Fabric)[^"]*"' | sort -u | head -50

if sudo -n true 2>/dev/null; then
	echo "## powermetrics, 3 samples"
	sudo -n powermetrics -n 3 -i 500 --samplers cpu_power,gpu_power,bandwidth 2>&1 | head -200
else
	echo "## powermetrics skipped (needs sudo)"
fi
