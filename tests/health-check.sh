#!/usr/bin/env bash
# Read-only health check after a boot into the stage K default (J516S, 7.2.11-m3gpu+). Changes nothing.
# Short GPU and memory tests (about 1 minute). Uses sudo -n only to read devices_deferred.
# Test programs: tests/build-tests.sh output, found in $AGX_TESTS (default ~/vktest).
set -u   # no pipefail: grep -q ends pipes early on purpose
KREL=7.2.11-m3gpu+
T="${AGX_TESTS:-$HOME/vktest}"
export VK_DRIVER_FILES=/opt/mesa-m3/share/vulkan/icd.d/asahi_icd.aarch64.json
fail=0
ok()  { echo "ok:   $*"; }
bad() { echo "FAIL: $*"; fail=1; }
# Read the kernel log once: grep -q on a live journalctl pipe fails under pipefail.
KLOG="$(journalctl -k -b --no-pager 2>/dev/null)"
klog() { printf '%s\n' "$KLOG"; }

echo "== Boot"
[ "$(uname -r)" = "$KREL" ] && ok "kernel $KREL" || bad "kernel is $(uname -r)"
echo "cmdline: $(cat /proc/cmdline)"
echo "uptime: $(uptime)"
tr -d '\0' < /proc/device-tree/chosen/asahi,m1n1-stage2-version 2>/dev/null | sed 's/^/m1n1: /'; echo

echo "== GPU"
ls /dev/dri/renderD* >/dev/null 2>&1 && ok "render node present" || bad "no render node"
klog | grep -qiE "G15|asahi" && ok "GPU driver messages present" || bad "no GPU driver messages"
n="$(klog | grep -ciE 'firmware halt|GPU fault|submit failed|rejecting CDM|fw.*refus')"
[ "$n" = 0 ] && ok "no GPU fault, halt or refused submit" || { bad "$n GPU fault/halt/refusal lines"; klog | grep -iE 'firmware halt|GPU fault|submit failed|rejecting CDM|fw.*refus' | tail -5; }
cd "$T" 2>/dev/null || bad "no test folder $T"
if [ -x "$T/vk-compute" ]; then
	"$T/vk-compute" 2>&1 | tail -2 | grep -q VK_COMPUTE_PASS && ok "Vulkan compute test passes" || bad "Vulkan compute test failed"
else bad "no $T/vk-compute"; fi

echo "== Memory floor"
klog | grep -E "memory floor try" | tail -1
klog | grep -qE "memory floor try [0-9]+: .* -> " && ! klog | grep -q "memory floor not confirmed" && ok "PMP accepted the memory floor" || bad "memory floor not confirmed"
if [ -x "$T/cpu-bw" ]; then
	# The cpufreq policy with the higher maximum is the P cluster.
	p_cpus="$(for pol in /sys/devices/system/cpu/cpufreq/policy*; do echo "$(cat "$pol/cpuinfo_max_freq") $(tr ' ' ',' < "$pol/related_cpus" | sed 's/,$//')"; done | sort -n | tail -1 | cut -d' ' -f2)"
	bw="$(OMP_NUM_THREADS=6 taskset -c "$p_cpus" "$T/cpu-bw" 8 2>/dev/null | tail -1)"; echo "CPU P cores ($p_cpus): $bw"
	echo "$bw" | grep -oE 'best [0-9.]+' | grep -oE '[0-9.]+' | awk '{exit !($1 > 80)}' && ok "CPU bandwidth above 80 GB/s" || bad "CPU bandwidth low"
else bad "no $T/cpu-bw"; fi
if [ -x "$T/vk-bandwidth" ]; then
	gbw="$("$T/vk-bandwidth" 512 60 16 2>/dev/null | grep "GB/s")"; echo "GPU: $gbw"
	echo "$gbw" | grep -oE 'best [0-9.]+' | grep -oE '[0-9.]+' | awk '{exit !($1 > 80)}' && ok "GPU bandwidth above 80 GB/s" || bad "GPU bandwidth low"
else bad "no $T/vk-bandwidth"; fi

echo "== USB4 and Bluetooth modules"
lsmod | grep -q '^thunderbolt_apple ' && bad "thunderbolt_apple is loaded (should stay blocked until the manual test)" || ok "thunderbolt_apple not loaded (blocked as planned)"
modinfo -n thunderbolt_apple >/dev/null 2>&1 && ok "thunderbolt_apple module available" || bad "thunderbolt_apple module not found"
lsmod | grep -q '^hci_bcm4377 ' && ok "hci_bcm4377 loaded" || bad "hci_bcm4377 not loaded"
[ "$(strings "$(modinfo -n hci_bcm4377)" | grep -c j516s)" -ge 1 ] && ok "patched hci_bcm4377 in use" || bad "unpatched hci_bcm4377"
# bluetoothd powers the controller some seconds after boot.
for i in 1 2 3 4 5 6; do bluetoothctl show 2>/dev/null | grep -q "Powered: yes" && break; sleep 5; done
bluetoothctl show 2>/dev/null | grep -q "Powered: yes" && ok "Bluetooth powered" || bad "Bluetooth not powered after 30 s"
t="$(klog | grep -c 'hci0: command .* tx timeout')"
[ "$t" = 0 ] && ok "no hci0 command timeouts" || bad "$t hci0 command timeouts"

echo "== Kernel log"
echo "error-level lines this boot: $(journalctl -k -b -p err --no-pager -q 2>/dev/null | wc -l)"
journalctl -k -b -p err --no-pager -q 2>/dev/null | sed -E 's/^.*kernel: //' | sort | uniq -c | sort -rn | head -12
if sudo -n true 2>/dev/null; then
	echo "devices_deferred:"; sudo -n cat /sys/kernel/debug/devices_deferred 2>/dev/null | sed 's/^/  /'
else echo "devices_deferred: SKIP (needs sudo)"; fi

[ "$fail" = 0 ] && echo HEALTH_OK || echo HEALTH_NOT_OK
