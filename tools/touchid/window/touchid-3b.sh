#!/usr/bin/env bash
# Touch ID stage 3b: load with xART writes, enrol, verify. WRITES to the shared xART store and creates a
# Linux identity keybag inside the Secure Enclave. Run only after the user said yes, and only after
# touchid-xart.sh backup PASSED. Run as the user, NOT with sudo (the script calls sudo -n itself).
#
#   touchid-3b.sh pre              read-only checks: SEP booted, backup exists and still equals the partition,
#                                  calibration installed, module present, AC power, apple_sep not loaded
#   touchid-3b.sh load             pre, then insmod with xart_writes=1 provision_keybag=1 xart_guard=3 (TOUCHID_GUARD=0|1|2|3
#                                  overrides the guard), watches the log, trusted-key seal/unseal test, then the alarm check
#   touchid-3b.sh alarm            the alarm check alone (also runs after load, open, enrol and verify)
#   touchid-3b.sh open             first open of /dev/sep-bio: sensor bring-up, key-store restore (sepbio info)
#   touchid-3b.sh enrol [LABEL]    enrol one finger. The USER touches the sensor (power button) when prompted
#   touchid-3b.sh verify           one match attempt. The USER touches the sensor
#   touchid-3b.sh status           diag attributes, sepbio info and list
#
# ALARM CHECK (guard level 3 = loaded only): compares the partition with the newest backup (touchid-xart.sh diff).
# OK only when every change is a root record (kind 1 or 2), a new record, or a pre-existing session record that the
# guard logged as allowed ("allowed a rewrite of the kind-N record UID") or that Linux created (its owned list).
# Any other pre-existing session record changed or removed, any change outside the .gl file, or a bad CRC is an
# ALARM: stop, no further step, tell the user.
#
# The module can be loaded once per boot and is never unloaded. A test boot is armed with
# touchid-boot.sh --sensor (do NOT run touchid-check.sh in the same boot: it loads the module read-only).
# STOP RULE: after every step the script prints lines that need a human look (refusals, failures, timeouts).
# If any appear, stop, do not run the next step, and ask the user. A reboot clears an unresponsive enclave.
set -uo pipefail
[ "$(id -u)" != 0 ] || { echo "[3b] STOP: run as the user, not with sudo (the script calls sudo -n itself)" >&2; exit 1; }
STEP="${1:-}"; shift || true
HERE="$(cd "$(dirname "$0")" && pwd)"; W="$HERE/touchid"
TEST="${TOUCHID_3B_TEST:-}"   # offline test only: skips the hardware checks
KREL=7.2.11-m3gpu+
KON="${TOUCHID_3B_MODULE:-apple-sep-3c.ko}"   # 3c: 3b (13.5 key-store profile for this firmware) plus guard level 3 (loaded only); 3b's guard level 1 refused a rewrite in the second load
KO="/lib/modules/$KREL/touchid-test/$KON"
GUARD="${TOUCHID_GUARD:-3}"
XART="${TOUCHID_3B_XART:-$HERE/touchid-xart.sh}"
OWNED="${TOUCHID_OWNED_FILE:-/var/lib/aurora-sep-xart-owned.bin}"
BACKUPS="${TOUCHID_BACKUP_DIR:-/data/touchid-backup}"
PART=/dev/disk/by-partlabel/iBootSystemContainer
FW=/lib/firmware/apple/mesacal-j516s.bin
TS=$(date +%Y%m%d-%H%M%S); mkdir -p "$W/logs"; LOG="$W/logs/3b-${STEP:-none}-$TS.log"
exec > >(tee -a "$LOG") 2>&1
say() { echo "[3b] $*"; }
die() { echo "[3b] STOP: $*" >&2; exit 1; }
rt() { sudo -n "$@"; }
sudo -n true 2>/dev/null || die "sudo -n does not work (the sudo window is closed)"
diag() { for f in /sys/bus/platform/devices/*.sep/diag/*; do [ -f "$f" ] && echo "  diag $(basename "$f")=$(cat "$f" 2>/dev/null)"; done; }
kl() { rt journalctl -k --since "$1" --no-pager 2>/dev/null; }
# Lines that need a human look. Known benign noise (the SEP random source) is left out.
review() { kl "$1" | grep -E 'apple_sep|apple-sep|apple-mesa|xART|spi1' | grep -v 'hwrng:' |
	grep -i -E 'xART guard: refused|refus|fail|error|timed out|timeout|unusable|ambiguous|unreadable|invalid|unavailable|cannot commit|Oops|BUG:|panic|Call trace' |
	{ if [ -n "${FIRST_ENROL:-}" ]; then grep -v -E 'restore (owner|user) catacomb state None outcome Failed|matching unavailable this boot: cold-match'; else cat; fi; } | cut -c1-230; }
verdict_review() { # $1 since
	local r; r=$(review "$1")
	if [ -n "$r" ]; then echo "--- LINES THAT NEED A LOOK (stop rule: do not continue before the user has seen them):"; echo "$r"; return 1; fi
	echo "--- no refusal, failure or timeout lines in the kernel log"; return 0
}

step_pre() {
	local ok=1 why=""
	if [ -n "$TEST" ]; then say "pre: TEST MODE, hardware checks skipped"; return 0; fi
	[ "$(uname -r)" = "$KREL" ] || { ok=0; why="$why kernel;"; }
	sepdir=$(ls -d /proc/device-tree/soc/sep@* 2>/dev/null | head -n1)
	[ -n "$sepdir" ] && [ -f "$sepdir/iboot-manifest" ] || { ok=0; why="$why this boot has no SEP device tree (arm it with touchid-boot.sh --sensor);"; }
	mb=$(ls -d /sys/bus/platform/devices/29e408000.* 2>/dev/null | head -n1); [ -n "$mb" ] && [ -e "$mb/driver" ] || { ok=0; why="$why SEP mailbox not bound;"; }
	lsmod | grep -q '^apple_sep' && { ok=0; why="$why apple_sep already loaded (once per boot);"; }
	d=$(ls -1dt "$BACKUPS"/ibootsys-* 2>/dev/null | head -n1)
	if [ -z "$d" ] || [ ! -f "$d/MANIFEST" ]; then ok=0; why="$why no backup (run touchid-xart.sh backup);"
	else
		want=$(sed -n 's/^sha256=//p' "$d/MANIFEST")
		[ "$(rt sha256sum "$d/ibootsys.img" | cut -d' ' -f1)" = "$want" ] || { ok=0; why="$why backup image hash differs from its MANIFEST;"; }
		[ "$(rt sha256sum "$PART" | cut -d' ' -f1)" = "$want" ] || { ok=0; why="$why partition no longer equals the newest backup: make a new backup;"; }
	fi
	rt test -f "$FW" && cmp -s "$FW" "$W/mesacal-j516s.bin" || { ok=0; why="$why calibration not installed (touchid-calib.sh --install);"; }
	( cd "$W" && sha256sum -c "$KON.sha256" >/dev/null 2>&1 ) && cmp -s "$W/$KON" "$KO" || { ok=0; why="$why module $KO missing or differs (the check script installs it, or: sudo install -D -m 0644 $W/$KON $KO && sudo restorecon -F $KO);"; }
	on=0; for p in /sys/class/power_supply/*/online; do [ -f "$p" ] && [ "$(cat "$p")" = 1 ] && on=1; done
	[ $on = 1 ] || { ok=0; why="$why AC power is not connected;"; }
	if [ $ok = 1 ]; then say "pre PASS: SEP booted, backup ${d##*/} verified and equal to the partition, calibration installed, module ready, AC on"; return 0; fi
	say "pre FAIL:$why"; return 1
}

trusted_test() { # seal and unseal a trusted key in this boot; across boots with the blob saved in boot 1
	local blobf="$W/trusted-blob.txt" boot; boot=$(cat /proc/sys/kernel/random/boot_id)
	[ -n "$TEST" ] && { say "trusted-key test skipped in test mode"; return 0; }
	rt keyctl session aurora-3b bash -c '
		set -u; blobf="$1"; boot="$2"
		id=$(printf "new 32" | keyctl padd trusted 3b-test @s 2>/dev/null) || { echo "TRUSTED seal FAIL: padd new"; exit 1; }
		blob=$(keyctl pipe "$id" | tr -d "\n\r ") ; [ -n "$blob" ] || { echo "TRUSTED seal FAIL: empty blob"; exit 1; }
		lid=$(printf "load %s" "$blob" | keyctl padd trusted 3b-load @s 2>/dev/null) && echo "TRUSTED same-boot seal+unseal PASS" || { echo "TRUSTED same-boot unseal FAIL"; exit 1; }
		if [ -f "$blobf" ]; then
			ob=$(sed -n 1p "$blobf"); old=$(sed -n 2p "$blobf")
			if [ "$ob" != "$boot" ]; then
				printf "load %s" "$old" | keyctl padd trusted 3b-old @s >/dev/null 2>&1 && echo "TRUSTED cross-boot unseal PASS (blob from an earlier boot)" || echo "TRUSTED cross-boot unseal FAIL (blob from an earlier boot)"
			fi
		else
			umask 077; printf "%s\n%s\n" "$boot" "$blob" > "$blobf"; echo "TRUSTED blob saved for the next boot test"
		fi' _ "$blobf" "$boot"
}

step_load() {
	step_pre || exit 1
	local T0 start att=0 prof=0 wr=0 gd=0 kb=0 fail="" ks=""
	T0=$(date '+%Y-%m-%d %H:%M:%S')
	printf '%s\n%s\n' "$(cat /proc/sys/kernel/random/boot_id)" "$T0" > "$W/load-since"
	say "insmod $KON xart_writes=1 provision_keybag=1 xart_guard=$GUARD sensor_trace=1 xarm_trace=1 at $T0"
	say "this load can write the shared xART store and create the Linux identity keybag in the enclave"
	if [ -n "$TEST" ]; then true; else rt insmod "$KO" xart_writes=1 provision_keybag=1 xart_guard="$GUARD" sensor_trace=1 xarm_trace=1 || { say "insmod FAILED"; kl "$T0" | tail -n 8; exit 1; }; fi
	start=$(date +%s)
	while [ $(( $(date +%s) - start )) -lt 150 ]; do
		k=$(kl "$T0")
		grep -q 'SEP platform profile: T6030/J516s' <<<"$k" && prof=1
		grep -q 'xART:.*writes ENABLED' <<<"$k" && wr=1
		grep -q 'xART guard level' <<<"$k" && gd=1
		grep -q 'attach: [0-9]* endpoints advertised' <<<"$k" && att=1
		grep -q -E 'sks: identity keybag provisioned' <<<"$k" && kb=1
		grep -q 'using the 13.5 key store' <<<"$k" && ks=13.5
		fail=$(review "$T0" | head -n 3)
		[ -n "$fail" ] && break
		[ -e /dev/sep-bio ] && [ $att = 1 ] && break
		sleep 3
	done
	echo "--- kernel lines since the insmod ($(( $(date +%s) - start )) s)"; kl "$T0" | grep -E 'apple_sep|apple-sep|xART|sks|trusted|bringup|keybag' | grep -v -E 'discover:|xarm: op|hwrng:' | cut -c1-230 | tail -n 40
	echo "--- diag"; diag
	kbp=0; for f in /sys/bus/platform/devices/*.sep/diag/keybag; do [ -f "$f" ] && [ "$(cat "$f")" = present ] && kbp=1; done
	verdict_review "$T0"; rv=$?
	alarm_check "$T0"; av=$?
	if [ $av != 0 ]; then say "LOAD STOP: ALARM. Do not enrol. The user decides. A reboot restores the normal state of the enclave (what was already written stays). Do NOT restore a backup without the user."; exit 1; fi
	if [ -n "$fail" ] || [ $rv != 0 ]; then say "LOAD STOP: lines above need a look. Do not enrol. The user decides. A reboot restores the normal state of the enclave (what was already written stays)."; exit 1; fi
	if [ $prof = 1 ] && [ $wr = 1 ] && [ $gd = 1 ] && [ $att = 1 ] && { [ $kb = 1 ] || [ $kbp = 1 ]; } && [ -e /dev/sep-bio ]; then
		say "LOAD PASS: profile (key store ${ks:-not announced}), xART writes ENABLED, guard level line, endpoints, keybag ($([ $kb = 1 ] && echo "provisioned now" || echo "already present")), /dev/sep-bio exists"
		trusted_test
	else
		say "LOAD INCOMPLETE: profile=$prof writes=$wr guard=$gd attach=$att keybag=$kb/$kbp sep-bio=$([ -e /dev/sep-bio ] && echo yes || echo no). Wait a minute and run: $0 status. If still incomplete, stop and ask the user."; exit 1
	fi
}

# The alarm rule. $1 = kernel log since (the load); prints the diff and a verdict; returns 0 OK, 1 ALARM.
alarm_check() {
	local since="$1" out rc allowed tf of
	out=$("$XART" diff 2>&1); rc=$?
	echo "--- touchid-xart.sh diff (partition against the newest backup)"; echo "$out" | cut -c1-200
	[ $rc = 0 ] || { say "ALARM: the diff could not run (exit $rc). Stop. The user decides."; return 1; }
	allowed=$(kl "$since" | grep -o 'allowed a rewrite of the kind-[34] record [0-9a-f]\{8\}' | awk '{print $NF}' | tr '\n' ' ')
	tf=$(mktemp); of=$(mktemp); printf '%s\n' "$out" > "$tf"
	if [ -n "$TEST" ]; then cp "$OWNED" "$of" 2>/dev/null || : > "$of"; else rt cat "$OWNED" > "$of" 2>/dev/null || : > "$of"; fi
	python3 -I - "$tf" "$of" $allowed <<'PY'
import re, sys
text = open(sys.argv[1]).read().splitlines()
owned = open(sys.argv[2], "rb").read()
ok_uids = set(sys.argv[3:])
nowned = 0
for i in range(0, len(owned) - 31, 32):
    e = owned[i:i + 32]
    if e[:4] == b"AXGO" and e[4] > 2:
        ok_uids.add(e[8:12].hex()); nowned += 1
alarms, roots, new, rewr = [], 0, 0, 0
m = re.search(r"sizes: partition (\d+), image (\d+); differing 4 KiB blocks: (\d+) \(inside .gl (\d+), outside (\d+)\)", "\n".join(text))
if not m and "IDENTICAL" not in "\n".join(text): alarms.append("the diff output has no summary line")
if m:
    if m.group(1) != m.group(2): alarms.append("partition and image sizes differ")
    if int(m.group(5)) > 0: alarms.append("%s changed 4 KiB blocks outside the .gl file" % m.group(5))
def parse(side):
    if side.strip() == "empty": return None
    r = re.match(r"kind (\d+) len (\d+) rev (\d+) crc_ok (True|False)(?: uid ([0-9a-f]{8}))?", side.strip())
    return None if not r else dict(kind=int(r.group(1)), ln=int(r.group(2)), rev=int(r.group(3)), crc=r.group(4) == "True", uid=r.group(5) or "")
i = 0
while i < len(text):
    a = re.match(r"slot\s+(\d+)\s+image:\s+(.*)$", text[i])
    if a and i + 1 < len(text):
        b = re.match(r"\s+now\s*:\s+(.*)$", text[i + 1])
        if b:
            slot = a.group(1); old, now = parse(a.group(2)), parse(b.group(1))
            if a.group(2).strip() != "empty" and old is None: alarms.append("slot %s: unreadable before-record (%s)" % (slot, a.group(2)[:60]))
            if b.group(1).strip() != "empty" and now is None: alarms.append("slot %s: unreadable record now (%s)" % (slot, b.group(1)[:60]))
            if old and old["kind"] > 2:
                if old["uid"] in ok_uids: rewr += 1
                else: alarms.append("slot %s: pre-existing session record (kind %d, %d bytes, uid %s) changed or removed and was not allowed" % (slot, old["kind"], old["ln"], old["uid"]))
            if old and old["kind"] in (1, 2): roots += 1
            if now:
                if not now["crc"]: alarms.append("slot %s: record now has a bad CRC" % slot)
                if now["kind"] not in (1, 2, 3, 4): alarms.append("slot %s: unknown record kind %d" % (slot, now["kind"]))
                if now["kind"] > 2 and old is None: new += 1
            i += 2; continue
    i += 1
print("alarm check: %d allowed-uid entries (%d from the Linux owned list), %d root slot changes, %d allowed session rewrites, %d new session records" % (len(ok_uids), nowned, roots, rewr, new))
if alarms:
    for x in alarms: print("ALARM: " + x)
    sys.exit(1)
print("alarm check: OK")
PY
	rc=$?; rm -f "$tf" "$of"
	if [ $rc = 0 ]; then say "ALARM CHECK OK: only roots, allowed rewrites of records the enclave loaded at attach, and new records changed"; return 0; fi
	say "ALARM CHECK FAILED: a record the guard should protect changed, or the diff shows something unexpected. STOP. No further step. Tell the user."; return 1
}
since_load() { # the time of this boot's load, or of this boot
	local f="$W/load-since" bid; bid=$(cat /proc/sys/kernel/random/boot_id)
	if [ -f "$f" ] && [ "$(sed -n 1p "$f")" = "$bid" ]; then sed -n 2p "$f"; else uptime -s; fi
}

sepbio() { rt timeout "$1" python3 -I "$W/sepbio.py" "${@:2}"; }

step_open() {
	local T0; T0=$(date '+%Y-%m-%d %H:%M:%S')
	# First enrol: no catacomb file exists yet, so the restore lines "state None outcome Failed" and "matching unavailable this boot"
	# are expected (nothing to restore, no identity yet). Verify becomes available after a good enrol. With files present they stay a stop.
	if [ -z "$TEST" ] && ! rt sh -c 'ls /var/lib/apple-sep-catacomb-*.bin' >/dev/null 2>&1; then FIRST_ENROL=1; say "no catacomb files yet: first-enrol state, the restore Failed and matching unavailable lines are expected"; fi
	 say "first open of /dev/sep-bio (activates Touch ID: sensor bring-up, key-store restore; up to 2 minutes)"
	sepbio 150 info; rc=$?
	echo "--- diag"; diag; echo "--- kernel lines since the open"; kl "$T0" | grep -E 'apple_sep|apple-sep|apple-mesa|sks|sbio|sensor|Touch ID' | cut -c1-230 | tail -n 40
	verdict_review "$T0"; rv=$?
	alarm_check "$(since_load)" || { say "OPEN STOP: ALARM. Do not enrol."; exit 1; }
	[ $rc = 0 ] && [ $rv = 0 ] && say "OPEN PASS: the sensor and the enclave are up (sensor present, see info above)" || { say "OPEN STOP: exit $rc. Lines above need a look. Do not enrol."; exit 1; }
}

step_enrol() {
	local T0 label="${1:-linux-finger}"; T0=$(date '+%Y-%m-%d %H:%M:%S')
	if [ -z "$TEST" ] && ! rt sh -c 'ls /var/lib/apple-sep-catacomb-*.bin' >/dev/null 2>&1; then FIRST_ENROL=1; fi
	say "ENROL: the user must touch the sensor (the power button) when prompted. Up to 3 minutes."
	sepbio 220 enrol "$label"; rc=$?
	echo "--- diag"; diag; verdict_review "$T0"; rv=$?
	sepbio 30 list
	alarm_check "$(since_load)" || { say "ENROL STOP: ALARM. No further step."; exit 1; }
	[ $rc = 0 ] && [ $rv = 0 ] && say "ENROL PASS: identity created. Next: $0 verify" || { say "ENROL STOP: exit $rc or log lines need a look. Do not repeat blindly. The user decides."; exit 1; }
}

step_verify() {
	local T0; T0=$(date '+%Y-%m-%d %H:%M:%S')
	say "VERIFY: the user must touch the sensor with the enrolled finger now (up to 30 s)."
	sepbio 60 verify; rc=$?
	verdict_review "$T0"; rv=$?
	alarm_check "$(since_load)" || { say "VERIFY STOP: ALARM. No further step."; exit 1; }
	[ $rc = 0 ] && say "VERIFY PASS: match$([ $rv = 0 ] || echo ' (but log lines need a look)')" || { say "VERIFY FAIL: no match or error (exit $rc). A wrong finger gives this too."; exit 1; }
}

case "$STEP" in
	pre) step_pre ;;
	load) step_load ;;
	open) step_open ;;
	enrol) step_enrol "$@" ;;
	verify) step_verify ;;
	alarm) alarm_check "$(since_load)" ;;
	status) echo "--- diag"; diag; sepbio 60 info; sepbio 30 list ;;
	*) sed -n '2,30p' "$0"; exit 2 ;;
esac
