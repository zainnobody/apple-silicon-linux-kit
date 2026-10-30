#!/usr/bin/env bash
# User-side wrapper for the Touch ID install (run as the user, NOT with sudo; needs the sudo window open).
#   ti-run.sh install [--skip-backup] [--no-pam-test]
#       1 checks (sudo, charger)  2 xART backup  3 builds the new boot file (read-only dry run)  4 sudo ti-install.sh install
#       It never reboots. After it: reboot once, then ti-run.sh verify.
#   ti-run.sh verify         post-reboot checks and the alarm check
#   ti-run.sh enroll [FINGER]  after the first successful verify: removes the old test identity, enrols through fprintd
#   ti-run.sh undo [STEP ...]  one-command rollback (also: sudo m3-touchid-install undo, from a TTY or over SSH)
#   ti-run.sh status
set -uo pipefail
[ "$(id -u)" != 0 ] || { echo "[ti-run] STOP: run as the user, not with sudo (the script calls sudo -n itself)" >&2; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
WIN="${TI_WINDOW:-$HOME/window}"
INST=/usr/local/sbin/m3-touchid-install
say() { echo "[ti-run] $*"; }
die() { echo "[ti-run] STOP: $*" >&2; exit 1; }
rt() { sudo -n "$@"; }
sudo -n true 2>/dev/null || die "sudo -n does not work (the sudo window is closed)"
CMD="${1:-}"; shift || true
case "$CMD" in
install)
	SKIPB=0; PASS=()
	for a in "$@"; do case "$a" in --skip-backup) SKIPB=1;; --no-pam-test) PASS+=("$a");; *) die "unknown option $a";; esac; done
	[ "$(cat /sys/class/power_supply/macsmc-ac/online 2>/dev/null)" = 1 ] || die "connect the charger first"
	[ -x "$WIN/touchid-boot.sh" ] && [ -x "$WIN/touchid-xart.sh" ] || die "$WIN/touchid-boot.sh or touchid-xart.sh missing (TI_WINDOW=$WIN)"
	if [ $SKIPB = 0 ]; then say "1/3 xART backup (read-only toward the partition, about a minute)"; "$WIN/touchid-xart.sh" backup || die "xART backup failed"
	else say "1/3 xART backup skipped on request"; fi
	say "2/3 build the new boot file (dry run: reads the ESP, writes nothing outside $WIN/touchid)"
	out=$("$WIN/touchid-boot.sh" --dry --sensor-irq 2>&1); rc=$?; echo "$out" | tail -n 14
	[ $rc = 0 ] && echo "$out" | grep -q 'DRY RUN done' || die "boot file dry run failed"
	say "3/3 install (root)"
	rt "$HERE/ti-install.sh" install "${PASS[@]}" ;;
undo)
	if [ -x "$INST" ]; then rt "$INST" undo "$@"; else rt "$HERE/ti-install.sh" undo "$@"; fi ;;
status)
	if [ -x "$INST" ]; then rt "$INST" status; else rt "$HERE/ti-install.sh" status; fi ;;
verify)
	rt "$INST" verify; rc=$?
	say "alarm check (partition against the newest xART backup)"
	"$WIN/touchid-3b.sh" alarm 2>&1 | tail -n 6; arc=${PIPESTATUS[0]}
	[ $rc = 0 ] && [ "$arc" = 0 ] && say "VERIFY AND ALARM CHECK OK" || { say "NOT OK: read the lines above; do not enrol"; exit 1; }
	cat <<'TXT'
[ti-run] Still to do by hand (the script cannot do them):
  1. Log out or reboot to the login screen: the password must log in.
  2. Lock the screen (Meta+L): the password must unlock it.
  3. After "ti-run.sh enroll": lock the screen, touch the sensor (hold the finger on it): it must unlock.
     A wrong finger must not unlock.
TXT
	;;
enroll)
	FINGER="${1:-right-index-finger}"
	say "stopping fprintd, then listing the identities in the enclave"
	rt systemctl stop fprintd.service
	rt timeout 60 python3 -I "$WIN/touchid/sepbio.py" list || die "sepbio list failed"
	echo "[ti-run] The old test identity is not known to fprintd, and it would win the match. Type DELETE to remove all identities, anything else to stop."
	read -r ans; [ "$ans" = DELETE ] || die "stopped; nothing deleted"
	rt timeout 60 python3 -I "$WIN/touchid/sepbio.py" delete-all --yes || die "delete failed"
	rt systemctl start fprintd.service
	say "enrol $FINGER through fprintd: touch and lift as asked (at most 3 tries; stop after 3 failures)"
	fprintd-enroll -f "$FINGER" "$USER" || die "enrol failed; the password still works everywhere"
	say "verify through fprintd: touch the sensor"
	fprintd-verify "$USER" ;;
*) sed -n '2,11p' "$0"; exit 2 ;;
esac
