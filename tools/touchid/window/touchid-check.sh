#!/usr/bin/env bash
# Touch ID + camera filter window, part 2 (after the test boot).
# Usage: touchid-check.sh [--no-camera] [--no-sep] [--baseline] [--no-open]
#   --no-open   do not run part 6 (stage 3a: ONE open of /dev/sep-bio, writes off). Part 6 runs by default only when
#               the test boot was armed with touchid-boot.sh --sensor (SENSOR=1 in touchid/last-run.env).
#   --baseline  camera only: capture 5 s and record the temporal noise number (run BEFORE the test boot,
#               with the filter still off, so the later number has something to compare with).
#   --no-sep    skip the apple_sep dry load (parts 1 to 4 still run).
# Prints PASS or FAIL per part and writes a log under ~/window/touchid/logs/.
# The dry load runs LAST: the module is never unloaded (the SEP stays registered until the next reboot),
# so run no suspend or sleep test afterwards. /dev/sep-bio is opened once, in part 6 only (stage 3a).
set -uo pipefail
[ "$(id -u)" != 0 ] || { echo "run as the user, not with sudo (the script calls sudo -n itself)"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; W="$HERE/touchid"
CAM=1; SEP=1; BASELINE=0; OPEN=auto
for a in "$@"; do case "$a" in --no-camera) CAM=0;; --no-sep) SEP=0;; --baseline) BASELINE=1;; --no-open) OPEN=0;; *) echo "unknown option $a"; exit 2;; esac; done
mkdir -p "$W/logs"; TS=$(date +%Y%m%d-%H%M%S); LOG="$W/logs/check-$TS.log"
exec > >(tee -a "$LOG") 2>&1
RES=()
part() { RES+=("$1 $2: $3"); echo "$1 $2: $3"; }
echo "touchid-check $TS kernel $(uname -r) up $(uptime -p)"

camera_dev() { for v in /sys/class/video4linux/video*; do [ "$(cat "$v/name" 2>/dev/null)" = apple-isp ] && echo "/dev/$(basename "$v")" && return 0; done; return 1; }
noise_metric() { # mean luma of the frame-to-frame difference: lower = less temporal noise (static scene)
	local f="$1" t; t=$(mktemp)
	ffmpeg -nostdin -hide_banner -loglevel error -i "$f" -vf "format=gray,tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=$t" -f null - 2>/dev/null
	awk -F= '/YAVG/{s+=$2;n++} END{if(n) printf "%.3f", s/n; else printf "n/a"}' "$t"; rm -f "$t"
}
camera_capture() { # sets CAPFILE, FRAMES
	local dev; dev=$(camera_dev) || return 1
	CAPFILE="$W/logs/cam-$TS.mkv"
	local o; o=$(timeout 40 ffmpeg -nostdin -hide_banner -f v4l2 -i "$dev" -t 5 -c:v mjpeg -q:v 3 -y "$CAPFILE" 2>&1); local rc=$?
	FRAMES=$(echo "$o" | grep -o 'frame= *[0-9]*' | tail -n1 | grep -o '[0-9]*$'); FRAMES=${FRAMES:-0}
	ffmpeg -nostdin -hide_banner -loglevel error -sseof -1 -i "$CAPFILE" -frames:v 1 -y "$W/logs/cam-$TS-last.jpg" 2>/dev/null
	return $rc
}

if [ $BASELINE = 1 ]; then
	if camera_capture; then m=$(noise_metric "$CAPFILE"); echo "$m" > "$W/baseline-noise.txt"; part BASELINE PASS "frames=$FRAMES noise=$m (saved to baseline-noise.txt)"
	else part BASELINE FAIL "capture failed (frames=${FRAMES:-0})"; fi
	exit 0
fi

# ---- part 1: did m1n1 pass the SEP manifests?  (A7)
sepdir=$(ls -d /proc/device-tree/soc/sep@* 2>/dev/null | head -n1)
if [ -n "$sepdir" ] && [ -f "$sepdir/iboot-manifest" ] && [ -f "$sepdir/local-policy-manifest" ]; then
	ib=$(stat -c %s "$sepdir/iboot-manifest"); lp=$(stat -c %s "$sepdir/local-policy-manifest")
	al=$(tr -d '\0' < /proc/device-tree/aliases/sep 2>/dev/null)
	st=$(tr -d '\0' < "$sepdir/status")
	if [ "$ib" -gt 1000 ] && [ "$lp" -gt 1000 ]; then part 1-SEP-DT PASS "iboot-manifest $ib bytes, local-policy-manifest $lp bytes, alias $al, status $st, memory-region $([ -f "$sepdir/memory-region" ] && echo yes || echo no)"
	else part 1-SEP-DT FAIL "manifest sizes too small ($ib, $lp)"; fi
else part 1-SEP-DT FAIL "no SEP node or no manifest property (this boot did not use boot.bin.sep, or m1n1 did not run its sep step)"; fi

# ---- part 1b: is the SEP mailbox controller bound? (without it the driver probe defers silently)
mb=$(ls -d /sys/bus/platform/devices/*29e408000*mbox* /sys/bus/platform/devices/29e408000.* 2>/dev/null | head -n1)
if [ -n "$mb" ] && [ -e "$mb/driver" ]; then part 1b-SEP-MBOX PASS "$(basename "$mb") bound to $(basename "$(readlink "$mb/driver")")"
else part 1b-SEP-MBOX FAIL "no bound SEP mailbox device (node disabled or missing): apple_sep would defer its probe without a log line"; fi

# ---- part 2: camera property in the live DT
tf=$(od -An -tx1 /proc/device-tree/soc/isp@2c8000000/apple,temporal-filter 2>/dev/null | tr -d ' \n')
want=00000000; grep -q '^CAM=1' "$W/last-run.env" 2>/dev/null && want=00000001
[ "$tf" = "$want" ] && part 2-CAM-DT PASS "apple,temporal-filter = ${tf: -1} (as built)" || part 2-CAM-DT FAIL "apple,temporal-filter = ${tf:-missing}, expected $want"

# ---- part 3: camera runtime
if [ $CAM = 1 ]; then
	if camera_dev >/dev/null; then
		bad=$(sudo -n journalctl -k -b --no-pager 2>/dev/null | grep -E 'apple-isp|2c8000000\.isp' | grep -i -E 'fail|error|timed out|-110|-22|handshake' | head -n 3)
		if [ -n "$bad" ]; then part 3-CAM-LOG FAIL "isp errors in the kernel log: $bad"; else part 3-CAM-LOG PASS "apple-isp bound at $(camera_dev), no isp errors in the kernel log"; fi
		if camera_capture && [ "$FRAMES" -ge 20 ]; then
			m=$(noise_metric "$CAPFILE"); b=$(cat "$W/baseline-noise.txt" 2>/dev/null || echo none)
			part 3-CAM-CAPTURE PASS "5 s capture, frames=$FRAMES, noise=$m (baseline $b; lower is better). Files: $CAPFILE and cam-$TS-last.jpg. Compare the jpg with the same-light reference by eye."
		else part 3-CAM-CAPTURE FAIL "capture failed or too few frames (frames=${FRAMES:-0})"; fi
	else part 3-CAM-LOG FAIL "no apple-isp video node: the camera did not appear (firmware may reject the filter). Undo = the old boot.bin."; fi
else part 3-CAM SKIP "--no-camera"; fi

# ---- part 4: module sanity (no load yet)
# Stage 3a+ (boot armed with --probe): the module with the status-only sensor option, a separate file.
PROBE=0; grep -q '^PROBE=1' "$W/last-run.env" 2>/dev/null && PROBE=1
KON=apple-sep.ko; [ $PROBE = 1 ] && KON=apple-sep-3a.ko
KO="/lib/modules/7.2.11-m3gpu+/touchid-test/$KON"  # SELinux: home files cannot be loaded as modules
if [ ! -f "$KO" ] && [ $SEP = 1 ]; then
	sudo -n install -D -m 0644 "$W/$KON" "$KO" && sudo -n restorecon -F "$KO" 2>/dev/null
fi
cmp -s "$W/$KON" "$KO" || echo "note: $KO differs from $W/$KON"
okk=1; msg=""
( cd "$W" && sha256sum -c "$KON.sha256" >/dev/null 2>&1 ) && [ "$(sha256sum "$KO" | cut -d' ' -f1)" = "$(cut -d' ' -f1 "$W/$KON.sha256")" ] || { okk=0; msg="module file hash differs from the recorded one; "; }
[ "$(modinfo -F vermagic "$KO" 2>/dev/null | cut -d' ' -f1)" = "$(uname -r)" ] || { okk=0; msg="${msg}vermagic differs from the running kernel; "; }
nm -u "$KO" | awk '{print $2}' | sort -u > "$W/work/undef.txt"; awk '{print $3}' /proc/kallsyms | sort -u > "$W/work/ksyms.txt"
miss=$(comm -23 "$W/work/undef.txt" "$W/work/ksyms.txt" | wc -l)
[ "$miss" = 0 ] || { okk=0; msg="${msg}$miss undefined symbols missing in the running kernel; "; }
lsmod | grep -q '^apple_sep' && { okk=0; msg="${msg}apple_sep is already loaded; "; }
[ $okk = 1 ] && part 4-MODULE PASS "hash, vermagic and all $(wc -l < "$W/work/undef.txt") symbols check out" || part 4-MODULE FAIL "$msg"

# ---- part 5: dry load, LAST
if [ $SEP = 1 ] && [ "${RES[0]%% *}" != "" ] && printf '%s\n' "${RES[@]}" | grep -q '^4-MODULE PASS' && printf '%s\n' "${RES[@]}" | grep -q '^1-SEP-DT PASS' && printf '%s\n' "${RES[@]}" | grep -q '^1b-SEP-MBOX PASS'; then
	PARAMS="xart_writes=0 provision_keybag=0 xarm_trace=1"; grep -q '^SENSOR=1' "$W/last-run.env" 2>/dev/null && PARAMS="$PARAMS sensor_trace=1"
	[ $PROBE = 1 ] && PARAMS="$PARAMS sensor_probe=1"
	T0=$(date '+%Y-%m-%d %H:%M:%S'); echo "insmod $KON $PARAMS at $T0 (never rmmod; /dev/sep-bio only in part 6)"
	OBS="$W/logs/sep-observe-$TS.log"
	# Detached observer: keeps recording even if this script or its caller is killed.
	setsid nohup bash -c 'T0="$1"; OBS="$2"; : > "$OBS"
		for t in 1 3 6 10 20 40 70 100 160 240; do
			sleep $(( t - ${last:-0} )); last=$t
			{ echo "=== t+${t}s $(date +%T)"; sudo -n journalctl -k --since "$T0" --no-pager 2>/dev/null | cut -c1-260 | tail -n 40
			  for f in /sys/bus/platform/devices/*.sep/diag/*; do [ -f "$f" ] && echo "diag $(basename "$f")=$(cat "$f" 2>/dev/null)"; done
			  echo "deferred: $(sudo -n cat /sys/kernel/debug/devices_deferred 2>/dev/null | grep -i -E "sep|29e4" | tr "\n" ";")"
			  ls /dev/sep* /dev/hwrng 2>&1 | tr "\n" " "; echo; cat /sys/class/misc/hw_random/rng_current 2>/dev/null; } >> "$OBS" 2>&1
		done' _ "$T0" "$OBS" >/dev/null 2>&1 < /dev/null &
	echo "observer: $OBS (survives a kill of this script)"
	if sudo -n insmod "$KO" $PARAMS; then
		prof=0; wr=0; att=0; fail=""; start=$(date +%s)
		while [ $(( $(date +%s) - start )) -lt 100 ]; do
			k=$(sudo -n journalctl -k --since "$T0" --no-pager 2>/dev/null)
			echo "$k" | grep -q 'SEP platform profile: T6030/J516s' && prof=1
			echo "$k" | grep -q 'xART:.*writes disabled' && wr=1
			echo "$k" | grep -q 'attach: [0-9]* endpoints advertised' && att=1
			[ $att = 1 ] && break
			fail=$(echo "$k" | grep -i -E 'refusing to attach|unavailable or invalid|probe with driver .* failed|apple_sep: no |attach: .*no endpoint|timed out|panic|BUG|Oops' | head -n 3)
			[ -n "$fail" ] && break
			sleep 5
		done
		echo "--- kernel lines since the insmod ($(( $(date +%s) - start )) s)"; sudo -n journalctl -k --since "$T0" --no-pager 2>/dev/null | tail -n 60
		echo "--- diag attributes"; for f in /sys/bus/platform/devices/*.sep/diag/*; do [ -f "$f" ] && echo "$(basename "$f")=$(cat "$f" 2>/dev/null)"; done
		if [ -n "$fail" ]; then part 5-SEP-DRYLOAD FAIL "driver reported: $fail"
		elif [ $prof = 1 ] && [ $wr = 1 ] && [ $att = 1 ]; then part 5-SEP-DRYLOAD PASS "profile selected, xART read-only, SEP advertised endpoints (attach line seen) in $(( $(date +%s) - start )) s. Module stays loaded until the next reboot."
		elif [ $prof = 1 ] && [ $wr = 1 ]; then part 5-SEP-DRYLOAD PARTIAL "profile selected and xART read-only, but NO attach line (no endpoint advertised) after $(( $(date +%s) - start )) s: the mailbox exchange is unproven. See $OBS"
		else part 5-SEP-DRYLOAD FAIL "no profile or xART line within 100 s (profile=$prof, xart=$wr)"; fi
		d=$(sudo -n cat /sys/kernel/debug/devices_deferred 2>/dev/null | grep -i -E "sep|29e4"); [ -n "$d" ] && echo "NOTE: probe is DEFERRED: $d"
	else part 5-SEP-DRYLOAD FAIL "insmod failed: $(sudo -n journalctl -k -n 5 --no-pager 2>/dev/null | tail -n 3)"; fi
elif [ $SEP = 0 ]; then part 5-SEP-DRYLOAD SKIP "--no-sep"
else part 5-SEP-DRYLOAD SKIP "not run: part 1 or part 4 did not PASS"; fi

# ---- part 6 (stage 3a): ONE open of /dev/sep-bio with writes off. Expected end: sensor bound, power line taken,
#      SBIO buffers registered with the enclave (silent on success), then "no persisted identity keybag" = ENOENT. That ENOENT is the PASS.
#      The driver refuses a second open this boot (touchid_failed), so this runs once. No capture is possible (EROFS).
[ "$OPEN" = auto ] && { grep -q '^SENSOR=1' "$W/last-run.env" 2>/dev/null && OPEN=1 || OPEN=0; }
if [ "$OPEN" = 1 ]; then
	if printf '%s\n' "${RES[@]}" | grep -q '^5-SEP-DRYLOAD PASS'; then
		for i in $(seq 1 15); do [ -e /dev/sep-bio ] && break; sleep 2; done
		if [ ! -e /dev/sep-bio ]; then part 6-SENSOR-OPEN FAIL "/dev/sep-bio does not exist 30 s after the attach line"
		else
			echo "--- before the open: spi devices and diag"; ls /sys/bus/spi/devices/ 2>&1 | tr '\n' ' '; echo
			for f in /sys/bus/platform/devices/*.sep/diag/*; do [ -f "$f" ] && echo "diag $(basename "$f")=$(cat "$f" 2>/dev/null)"; done
			T1=$(date '+%Y-%m-%d %H:%M:%S'); echo "open /dev/sep-bio (O_RDWR, once) at $T1"
			oo=$(sudo -n timeout 120 python3 -I -c '
import os, time
t = time.time()
try:
    fd = os.open("/dev/sep-bio", os.O_RDWR)
    print("OPEN_OK")
    os.close(fd)
except OSError as e:
    print("OPEN_ERRNO", e.errno, os.strerror(e.errno))
print("ELAPSED %.1f" % (time.time() - t))' 2>&1); orc=$?
			echo "$oo"; echo "python rc=$orc"
			sleep 3
			k=$(sudo -n journalctl -k --since "$T1" --no-pager 2>/dev/null)
			echo "--- kernel lines since the open"; echo "$k" | cut -c1-260 | tail -n 60
			echo "--- after the open: diag, spi devices, power line"
			for f in /sys/bus/platform/devices/*.sep/diag/*; do [ -f "$f" ] && echo "diag $(basename "$f")=$(cat "$f" 2>/dev/null)"; done
			for d in /sys/bus/spi/devices/*; do [ -e "$d" ] && echo "spi $(basename "$d") driver=$(basename "$(readlink "$d/driver" 2>/dev/null)" 2>/dev/null)"; done
			sudo -n grep -i -E 'enable|mesa|sep' /sys/kernel/debug/gpio 2>/dev/null | head -n 5
			g() { echo "$k" | grep -q -F -- "$1"; }
			enoent=0; echo "$oo" | grep -q 'OPEN_ERRNO 2 ' && enoent=1
			sn=0; g 'sensor node present in the device tree' && sn=1
			bound=0; g 'sep sensor: bound,' && bound=1
			pwr=0; g 'sep sensor: power line from the device node' && pwr=1
			kb=0; g 'Touch ID: no persisted identity keybag exists' && kb=1
			# SBIO setup logs nothing on success on a profile without the INIT request (T6030 is such a profile): the driver
			# registers the buffers with four control requests and only logs failures. The keybag step runs AFTER
			# enable_sbio() returned Ok, so "keybag line seen and no SBIO failure line" is the proof (3a run 13:34, 2026-10-27).
			sbio=0; if [ $kb = 1 ] && ! g 'registering the biometric buffers failed' && ! g 'communication init refused' && ! g 'communication init transport failed'; then sbio=1; fi
			sbioinit=none; g 'communication initialization accepted' && sbioinit=accepted
			cst=$(echo "$k" | grep -o 'sep sensor: [^"]*CS timing[^"]*\|sep sensor: [^"]*chip select[^"]*' | head -n1)
			mode=$(echo "$k" | grep -o 'sep sensor: bound, [^"]*' | head -n1)
			bad=$(echo "$k" | grep -i -E 'Oops|BUG:|panic|could not register the SPI driver|no sensor|sep sensor: power unavailable|no power line|communication init (refused|transport)|registering the biometric buffers failed|opening the host state failed|loading the host identity index failed|no power GPIO' | head -n 4)
			sum="open=$([ $enoent = 1 ] && echo ENOENT || echo "$(echo "$oo" | grep -o 'OPEN_[A-Z]*.*' | head -n1)") spi-node=$sn sensor-bound=$bound power-line=$pwr sbio-setup=$([ $sbio = 1 ] && echo ok || echo FAILED)(init-request:$sbioinit) keybag-missing=$kb; ${mode:-no bind line}; ${cst:-no CS timing line}"
			if [ $enoent = 1 ] && [ $kb = 1 ] && [ $sbio = 1 ] && [ $bound = 1 ] && [ $pwr = 1 ] && [ -z "$(echo "$bad" | grep -i -E 'Oops|BUG:|panic')" ]; then
				part 6-SENSOR-OPEN PASS "expected end state: $sum"
			elif [ $enoent = 1 ] && [ $kb = 1 ] && [ $sbio = 1 ]; then
				part 6-SENSOR-OPEN PARTIAL "SEP side fine (SBIO registered, ENOENT for no keybag) but the sensor side is not: $sum. Problems: ${bad:-none logged}. Fix the sensor DT block (power pin, SPI mode, pin mux) and test again."
			else
				part 6-SENSOR-OPEN FAIL "$sum. Problems: ${bad:-none logged}"
			fi
		fi
	else part 6-SENSOR-OPEN SKIP "not run: part 5 did not PASS"; fi
else part 6-SENSOR-OPEN SKIP "no sensor test boot armed (SENSOR=1 missing) or --no-open"; fi

# ---- part 6b (stage 3a+): the status-only sensor probe, logged during the open. It reads the sensor status over SPI
#      (device-tree mode first, then the other three while silent) and logs the answer and its revision code only.
if [ "$OPEN" = 1 ] && [ $PROBE = 1 ] && [ -n "${k:-}" ]; then
	pl=$(echo "$k" | grep -F 'sensor probe:' | sed -E 's/^.*sensor probe: /  /' | cut -c1-230)
	echo "--- sensor probe lines"; echo "$pl"
	res=$(echo "$k" | grep -o 'sensor probe: RESULT.*' | head -n1)
	if echo "$res" | grep -q 'answered in SPI mode.*(known)'; then
		dtm=$(echo "$res" | grep -o 'device tree says [0-9]'); wm=$(echo "$res" | grep -o 'SPI mode [0-9]' | head -n1)
		part 6b-SENSOR-PROBE PASS "the sensor answers: $res. ${wm#SPI mode } is the working mode; ${dtm:-device tree mode unknown}. If they differ, set spi-cpol/spi-cpha in the DT block to the working mode."
	elif echo "$res" | grep -q 'answered in SPI mode'; then
		part 6b-SENSOR-PROBE PARTIAL "the sensor answers but its revision code is not in the driver's known list: $res"
	elif [ -n "$res" ]; then
		part 6b-SENSOR-PROBE FAIL "$res (power pin, SPI pin mux or bus wiring is wrong; see the probe lines in the log)"
	else
		part 6b-SENSOR-PROBE FAIL "no probe line in the kernel log: the module was not the 3a+ build, or the sensor never bound"
	fi
elif [ $PROBE = 1 ]; then part 6b-SENSOR-PROBE SKIP "part 6 did not run"; fi

echo; echo "===== SUMMARY ($LOG)"; printf '%s\n' "${RES[@]}"
printf '%s\n' "${RES[@]}" | grep -q ' FAIL:' && echo "OVERALL: FAIL (see lines above)" || { printf '%s\n' "${RES[@]}" | grep -q ' PARTIAL:' && echo "OVERALL: PARTIAL" || echo "OVERALL: PASS"; }
echo "Reminder: the next reboot clears the loaded apple_sep. Run no suspend or sleep before then. After part 6 the driver refuses another /dev/sep-bio open until that reboot."
