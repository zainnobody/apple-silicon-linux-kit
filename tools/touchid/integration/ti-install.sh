#!/usr/bin/env bash
# Touch ID install for the M3 Pro (J516S): boot with the Secure Enclave, load the driver at boot, libfprint with the
# aurora driver, fprintd, PAM for the KDE lock screen and the Plasma Login screen. Sudo stays password-only.
# Plan: docs/features/touchid-integration-plan.md. Run it through ti-run.sh (which also builds the boot file and takes the
# xART backup), or directly:
#
#   sudo ./ti-install.sh preflight                 checks only, changes nothing
#   sudo ./ti-install.sh install [--no-pam-test]   all steps in order; any failure undoes the steps of this run
#   sudo m3-touchid-install undo [STEP ...]        undo all steps (or only the named ones), newest first
#   sudo m3-touchid-install status | verify
#
# Steps in order: module units selinux libfprint dropin pam-lock pam-login bootbin
# The boot file (bootbin) is last, so a failure before it leaves the next boot unchanged.
# Each step has its own undo. Nothing here reboots, loads the module or starts the driver.
# Offline tests: TI_ROOT=<dir> TI_TEST=1 with stub commands first in PATH (tests/touchid-integration-test.sh).
set -uo pipefail

R="${TI_ROOT:-}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KREL="${TI_KREL:-7.2.11-m3gpu+}"
STATE="$R/var/lib/m3-touchid"; BK="$STATE/backup"; MARK="$STATE/steps"
LOGF="$R/var/log/m3-touchid.log"
ESP="$R/boot/efi/m1n1"
SBIN="$R/usr/local/sbin"
SELF_INSTALLED="$SBIN/m3-touchid-install"
STEPS=(module units selinux libfprint dropin pam-lock pam-login bootbin)

# Pinned inputs (the files tested on 2026-10-30).
MODULE_SHA="${TI_MODULE_SHA:-d7b1e23d711bdcca107655537b869e07653f7445f67f95aa794e76e3a101bf0a}"   # apple-sep-3f.ko
RPM_SHA="${TI_RPM_SHA:-f6926eb82b8d26d2885c159a50bbddafc753cd5b025cbeca5e28779481aab378}"          # libfprint-aurora-1.94.100-1.fc44
STAGEE_SHA="${TI_STAGEE_SHA:-f3197272d588f4b0a037c5f81f0cfb2c36dfc6c7398a4205910ed8b9cbaa0725}"    # boot.bin.stageE
BASE_DTB_PFX="${TI_BASE_DTB_PFX:-18baac96}"   # stock t6030-j516s.dtb
PAM_LOGIN_LINE='-auth       sufficient    pam_fprintd.so max-tries=2 timeout=10'

UHOME="${TI_UHOME:-/home/${SUDO_USER:-nobody}}"
MODULE_SRC="${TI_MODULE:-$UHOME/window/touchid/apple-sep-3f.ko}"
RPM_SRC="${TI_RPM:-$UHOME/aurora-build/rpmbuild/RPMS/aarch64/libfprint-aurora-1.94.100-1.fc44.aarch64.rpm}"
BOOT_NEW="${TI_BOOT_NEW:-$UHOME/window/touchid/dry/expected-boot.bin.sep}"
BOOT_DTB="${TI_BOOT_DTB:-$UHOME/window/touchid/work/merged.dtb}"
BACKUPS="${TOUCHID_BACKUP_DIR:-/data/touchid-backup}"
PAMTEST="$HERE/pam-auth-test.py"

say() { echo "[ti] $*"; }
die() { echo "[ti] STOP: $*" >&2; exit 1; }
log() { mkdir -p "$(dirname "$LOGF")"; echo "$(date '+%F %T') $*" >> "$LOGF"; }
need_root() { [ -n "${TI_TEST:-}" ] || [ "$(id -u)" = 0 ] || die "run with sudo"; }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
atomic() { # src dst mode: copy under a temporary name so a reader never sees half a file
	mkdir -p "$(dirname "$2")" && cp "$1" "$2.ti-new" && chmod "$3" "$2.ti-new" && mv -f "$2.ti-new" "$2"
}
relabel() { command -v restorecon >/dev/null 2>&1 && restorecon -R "$@" >/dev/null 2>&1; return 0; }
done_mark() { mkdir -p "$MARK"; date '+%F %T' > "$MARK/$1.done"; }
is_done() { [ -f "$MARK/$1.done" ]; }
clear_mark() { rm -f "$MARK/$1.done"; }
save_orig() { # file name: keep the first original of a file, never overwrite an older backup (a second run sees our own file)
	local f="$1" n="$2"
	mkdir -p "$BK/$n"
	[ -e "$BK/$n/orig" ] || [ -e "$BK/$n/absent" ] && return 0
	if [ -e "$f" ]; then cp -p "$f" "$BK/$n/orig" && sha "$f" > "$BK/$n/orig.sha"; else : > "$BK/$n/absent"; fi
}
restore_orig() { # file name
	local f="$1" n="$2"
	# No backup means this tool never changed the file (or already undid it): leave the file alone.
	if [ -e "$BK/$n/orig" ]; then atomic "$BK/$n/orig" "$f" 0644 && relabel "$f"; elif [ -e "$BK/$n/absent" ]; then rm -f "$f"; else say "no backup of $f: leaving it as it is"; fi
	rm -rf "$BK/$n"
}

# ---------------------------------------------------------------- preflight
preflight() {
	local bad=0 f
	fail() { echo "[ti] FAIL: $*" >&2; bad=1; }
	pass() { say "ok: $*"; }
	[ -n "${TI_TEST:-}" ] || [ "$(uname -r)" = "$KREL" ] && pass "kernel $KREL" || fail "running kernel is $(uname -r), expected $KREL"
	if [ -z "${TI_TEST:-}" ]; then
		tr '\0' '\n' < /proc/device-tree/compatible | grep -qx 'apple,j516s' && pass "machine is a J516S" || fail "not a J516S"
		[ "$(cat /sys/class/power_supply/macsmc-ac/online 2>/dev/null)" = 1 ] && pass "AC power is connected" || fail "connect the charger first"
	fi
	[ -f "$MODULE_SRC" ] && [ "$(sha "$MODULE_SRC")" = "$MODULE_SHA" ] && pass "module $(basename "$MODULE_SRC") hash is the tested one" || fail "module missing or hash differs: $MODULE_SRC"
	[ -f "$RPM_SRC" ] && [ "$(sha "$RPM_SRC")" = "$RPM_SHA" ] && pass "libfprint-aurora RPM hash is the tested one" || fail "RPM missing or hash differs: $RPM_SRC"
	[ -f "$R/lib/firmware/apple/mesacal-j516s.bin" ] && pass "sensor calibration file is installed" || fail "/lib/firmware/apple/mesacal-j516s.bin is missing"
	[ -f "$R/usr/lib64/security/pam_fprintd.so" ] && pass "pam_fprintd is installed" || fail "fprintd-pam is not installed"
	[ -x "$R/usr/libexec/fprintd" ] && pass "fprintd is installed" || fail "fprintd is not installed"
	[ -f "$R/usr/lib/pam.d/plasmalogin" ] && pass "vendor PAM file for Plasma Login found" || fail "/usr/lib/pam.d/plasmalogin is missing"
	[ -f "$R/etc/pam.d/kde" ] && [ -f "$R/etc/pam.d/kde-fingerprint" ] && pass "KDE lock screen PAM files found" || fail "/etc/pam.d/kde or kde-fingerprint missing"
	for f in checkmodule semodule_package semodule semanage depmod modinfo rpm systemctl python3; do
		command -v "$f" >/dev/null 2>&1 || fail "command missing: $f"
	done
	[ -f "$ESP/boot.bin" ] && [ -f "$ESP/boot.bin.stageE" ] && pass "ESP boot.bin and boot.bin.stageE present" || fail "boot.bin or boot.bin.stageE missing on the ESP"
	if [ -f "$ESP/boot.bin" ] && [ -f "$ESP/boot.bin.stageE" ]; then
		[ "$(sha "$ESP/boot.bin.stageE")" = "$STAGEE_SHA" ] && pass "boot.bin.stageE is the pinned fallback" || fail "boot.bin.stageE hash differs from the pinned one"
		if is_done bootbin; then pass "boot file step already applied"
		else [ "$(sha "$ESP/boot.bin")" = "$STAGEE_SHA" ] && pass "boot.bin is stageE (the base for the new boot file)" || fail "boot.bin is not stageE: another window changed it"; fi
	fi
	[ -f "$ESP/boot.bin.stock" ] || fail "boot.bin.stock is missing"
	grep -q '^M1N1_UPDATE_DISABLED=1' "$R/etc/sysconfig/update-m1n1" 2>/dev/null && pass "m1n1 updates are paused" || fail "m1n1 updates are not paused: a kernel update could replace boot.bin"
	[ ! -e "$R/etc/systemd/system/m3-touchid-restore.service" ] && [ ! -e "$R/etc/systemd/system/ane-window-restore.service" ] && pass "no test window is armed" || fail "a test window is armed (m3-touchid-restore or ane-window-restore)"
	[ -f "$BOOT_NEW" ] && [ -f "$BOOT_DTB" ] && pass "new boot file and merged DTB are prepared" || fail "run ti-run.sh (it prepares $BOOT_NEW and $BOOT_DTB)"
	f=$(ls -1dt "$BACKUPS"/*/ 2>/dev/null | head -n1)
	[ -n "$f" ] && pass "xART backup found: $(basename "$f")" || fail "no xART backup in $BACKUPS (ti-run.sh takes one)"
	[ -z "${TI_TEST:-}" ] && grep -q '^apple_sep ' /proc/modules 2>/dev/null && say "note: apple_sep is loaded in this boot; fine, nothing here loads or unloads it"
	return $bad
}

# ---------------------------------------------------------------- steps
apply_module() {
	local dst="$R/lib/modules/$KREL/extra/apple_sep.ko" got
	[ -d "$R/lib/modules/$KREL" ] || die "no /lib/modules/$KREL"
	save_orig "$dst" module
	atomic "$MODULE_SRC" "$dst" 0644 || return 1
	relabel "$dst"
	depmod -a "$KREL" || return 1
	got=$(modinfo -k "$KREL" -F filename apple_sep 2>/dev/null) || return 1
	[ "$got" = "${dst#"$R"}" ] || { echo "[ti] modinfo finds apple_sep at '$got', not at ${dst#"$R"}" >&2; return 1; }
	modinfo -k "$KREL" -F parm apple_sep 2>/dev/null | grep -q '^sensor_rearm_mode:' || { echo "[ti] module lacks sensor_rearm_mode" >&2; return 1; }
	say "module installed: ${dst#"$R"} ($(sha "$dst" | cut -c1-8))"
}
undo_module() {
	restore_orig "$R/lib/modules/$KREL/extra/apple_sep.ko" module
	depmod -a "$KREL" || true
	say "module removed (a loaded copy stays until the next boot)"
}

apply_units() {
	mkdir -p "$SBIN" "$R/etc/systemd/system"
	atomic "$HERE/m3-touchid-load" "$SBIN/m3-touchid-load" 0755 || return 1
	atomic "$HERE/m3-touchid.service" "$R/etc/systemd/system/m3-touchid.service" 0644 || return 1
	mkdir -p "$BK"
	[ -e "$R/etc/m3-touchid.conf" ] || { atomic "$HERE/m3-touchid.conf.example" "$R/etc/m3-touchid.conf" 0644 || return 1; echo created > "$BK/units-conf-created"; }
	[ "$HERE/ti-install.sh" -ef "$SELF_INSTALLED" ] || atomic "$HERE/ti-install.sh" "$SELF_INSTALLED" 0755 || return 1
	relabel "$SBIN/m3-touchid-load" "$R/etc/systemd/system/m3-touchid.service" "$SELF_INSTALLED"
	systemctl daemon-reload || return 1
	systemctl enable m3-touchid.service >/dev/null 2>&1 || return 1
	say "boot unit installed and enabled (it starts only on a boot with the Secure Enclave device nodes)"
}
undo_units() {
	systemctl disable m3-touchid.service >/dev/null 2>&1 || true
	rm -f "$R/etc/systemd/system/m3-touchid.service" "$SBIN/m3-touchid-load"
	if [ -e "$BK/units-conf-created" ] && cmp -s "$R/etc/m3-touchid.conf" "$HERE/m3-touchid.conf.example" 2>/dev/null; then rm -f "$R/etc/m3-touchid.conf"; fi
	rm -f "$BK/units-conf-created"
	systemctl daemon-reload || true
	say "boot unit removed (m3-touchid-install stays in $SBIN so this undo can run again)"
}

apply_selinux() {
	local w; w=$(mktemp -d) || return 1
	checkmodule -M -m -o "$w/m3touchid.mod" "$HERE/m3touchid.te" >/dev/null && semodule_package -o "$w/m3touchid.pp" -m "$w/m3touchid.mod" || { rm -rf "$w"; return 1; }
	semodule -i "$w/m3touchid.pp" || { rm -rf "$w"; return 1; }
	rm -rf "$w"
	semanage fcontext -a -t lib_t '/opt/aurora-sep(/.*)?' 2>/dev/null || semanage fcontext -m -t lib_t '/opt/aurora-sep(/.*)?' || return 1
	say "SELinux: policy module m3touchid installed, /opt/aurora-sep labelled lib_t"
}
undo_selinux() {
	semanage fcontext -d '/opt/aurora-sep(/.*)?' 2>/dev/null || true
	semodule -r m3touchid 2>/dev/null || true
	say "SELinux: m3touchid removed"
}

apply_libfprint() {
	if rpm -q libfprint-aurora >/dev/null 2>&1; then say "libfprint-aurora is already installed; leaving it"; return 0; fi
	rpm -qpl "$RPM_SRC" | grep -v '^/opt/aurora-sep' | grep -q . && { echo "[ti] the RPM lists files outside /opt/aurora-sep" >&2; return 1; }
	rpm -i --test "$RPM_SRC" || return 1
	rpm -i "$RPM_SRC" || return 1
	mkdir -p "$BK"; echo "$RPM_SHA" > "$BK/libfprint-installed"
	relabel /opt/aurora-sep
	[ -e "$R/opt/aurora-sep/lib64/libfprint-2.so.2" ] || { echo "[ti] /opt/aurora-sep/lib64/libfprint-2.so.2 missing after install" >&2; return 1; }
	grep -aq 'aurora_' "$R/opt/aurora-sep/lib64/libfprint-2.so.2" || { echo "[ti] the library has no aurora driver" >&2; return 1; }
	say "libfprint-aurora installed under /opt/aurora-sep (the distro libfprint is untouched)"
}
undo_libfprint() {
	if [ -e "$BK/libfprint-installed" ]; then rpm -e libfprint-aurora || return 1; rm -f "$BK/libfprint-installed"; say "libfprint-aurora removed"
	else say "libfprint-aurora was not installed by this tool; leaving it"; fi
}

DROPIN_DIR="$R/etc/systemd/system/fprintd.service.d"
apply_dropin() {
	atomic "$HERE/fprintd-aurora.conf" "$DROPIN_DIR/aurora-private.conf" 0644 || return 1
	relabel "$DROPIN_DIR"
	systemctl daemon-reload || return 1
	say "fprintd drop-in installed (LD_LIBRARY_PATH, /dev/sep-bio, start after m3-touchid.service, --no-timeout)"
}
undo_dropin() {
	rm -f "$DROPIN_DIR/aurora-private.conf"; rmdir "$DROPIN_DIR" 2>/dev/null || true
	systemctl daemon-reload || true
	say "fprintd drop-in removed"
}

pam_lock_file="$R/etc/pam.d/kde-fingerprint"
apply_pam_lock() {
	save_orig "$pam_lock_file" pam-lock
	atomic "$HERE/pam/kde-fingerprint" "$pam_lock_file" 0644 || return 1
	relabel "$pam_lock_file"
	grep -c '^-auth       required      pam_fprintd.so$' "$pam_lock_file" | grep -qx 1 || return 1
	say "PAM: /etc/pam.d/kde-fingerprint installed (the lock screen password service \"kde\" is not touched)"
}
undo_pam_lock() { restore_orig "$pam_lock_file" pam-lock; say "PAM: kde-fingerprint restored"; }

pam_login_file="$R/etc/pam.d/plasmalogin"
make_login_pam() { # vendor file in, override on stdout: one line before the first password-auth substack
	awk -v line="$PAM_LOGIN_LINE" '
		!done && $1 == "auth" && $2 == "substack" && $3 == "password-auth" { print line; done = 1 }
		{ print }
		END { if (!done) exit 3 }' "$1"
}
apply_pam_login() {
	local vendor="$R/usr/lib/pam.d/plasmalogin" t
	t=$(mktemp) || return 1
	make_login_pam "$vendor" > "$t" || { rm -f "$t"; echo "[ti] vendor plasmalogin has no 'auth substack password-auth' line" >&2; return 1; }
	grep -c -F -e "$PAM_LOGIN_LINE" "$t" | grep -qx 1 || { rm -f "$t"; return 1; }
	save_orig "$pam_login_file" pam-login
	atomic "$t" "$pam_login_file" 0644; local rc=$?
	rm -f "$t"; [ $rc = 0 ] || return 1
	relabel "$pam_login_file"
	say "PAM: /etc/pam.d/plasmalogin installed (fingerprint first, then the unchanged password stack)"
}
undo_pam_login() { restore_orig "$pam_login_file" pam-login; say "PAM: plasmalogin override removed"; }

apply_bootbin() {
	local base_dtb="$R/boot/dtb-$KREL/apple/t6030-j516s.dtb" cur new_sha
	[ ! -e "$R/etc/systemd/system/m3-touchid-restore.service" ] || { echo "[ti] a Touch ID restore unit is armed" >&2; return 1; }
	[ "$(sha "$ESP/boot.bin.stageE")" = "$STAGEE_SHA" ] || { echo "[ti] boot.bin.stageE is not the pinned fallback" >&2; return 1; }
	cur=$(sha "$ESP/boot.bin")
	if [ "$cur" != "$STAGEE_SHA" ] && [ -f "$ESP/boot.bin.stageS" ] && [ "$cur" = "$(sha "$ESP/boot.bin.stageS")" ]; then say "boot.bin is already stageS"; return 0; fi
	[ "$cur" = "$STAGEE_SHA" ] || { echo "[ti] boot.bin is neither stageE nor stageS" >&2; return 1; }
	[ "$(sha "$base_dtb" | cut -c1-8)" = "$BASE_DTB_PFX" ] || { echo "[ti] installed J516S dtb is not the known one" >&2; return 1; }
	# Proof: the new file equals stageE with only the J516S dtb replaced by the merged dtb.
	python3 -I - "$ESP/boot.bin.stageE" "$base_dtb" "$BOOT_DTB" "$BOOT_NEW" <<'PY' || return 1
import struct, sys
base, bdtb, ndtb, new = (open(p, "rb").read() for p in sys.argv[1:5])
if ndtb[:4] != b"\xd0\x0d\xfe\xed" or struct.unpack(">I", ndtb[4:8])[0] != len(ndtb):
    sys.exit("merged dtb: bad magic or size")
if base.count(bdtb) != 1:
    sys.exit("base J516S dtb found %d times in stageE, expected 1" % base.count(bdtb))
i = base.index(bdtb)
if new != base[:i] + ndtb + base[i + len(bdtb):]:
    sys.exit("new boot file is not stageE with only the J516S dtb replaced")
print("[ti] proof OK: new boot file = stageE with only the J516S dtb replaced (%d -> %d bytes)" % (len(base), len(new)))
PY
	new_sha=$(sha "$BOOT_NEW")
	mkdir -p "$STATE"
	printf 'BASE_SHA=%s\nS_SHA=%s\nWHEN=%s\n' "$STAGEE_SHA" "$new_sha" "$(date '+%F %T')" > "$STATE/bootbin.env"
	cp -f "$BOOT_NEW" "$ESP/boot.bin.stageS.new" && sync && mv -f "$ESP/boot.bin.stageS.new" "$ESP/boot.bin.stageS" && sync || return 1
	[ "$(sha "$ESP/boot.bin.stageS")" = "$new_sha" ] || { echo "[ti] boot.bin.stageS hash wrong after the copy" >&2; return 1; }
	cp -f "$ESP/boot.bin.stageS" "$ESP/boot.bin.new" && sync && mv -f "$ESP/boot.bin.new" "$ESP/boot.bin" && sync || return 1
	[ "$(sha "$ESP/boot.bin")" = "$new_sha" ] || { echo "[ti] boot.bin hash wrong after the switch" >&2; cp -f "$ESP/boot.bin.stageE" "$ESP/boot.bin"; return 1; }
	say "boot.bin is now stageS ($(echo "$new_sha" | cut -c1-8)); boot.bin.stageE stays as the fallback. The next boot has the Secure Enclave."
}
undo_bootbin() {
	local cur; [ "$(sha "$ESP/boot.bin.stageE")" = "$STAGEE_SHA" ] || die "boot.bin.stageE does not match the pinned hash; not switching. Use m3gpu-default status and decide by hand."
	cur=$(sha "$ESP/boot.bin")
	[ "$cur" = "$STAGEE_SHA" ] && { say "boot.bin is already stageE"; return 0; }
	# Only switch back when boot.bin is the file this tool installed. Another choice (stageD, stock) is not ours to change.
	if [ -f "$STATE/bootbin.env" ]; then . "$STATE/bootbin.env"; fi
	[ -n "${S_SHA:-}" ] && [ "$cur" = "$S_SHA" ] || { say "boot.bin is neither stageE nor the file this tool installed; leaving it (check: m3gpu-default status)"; return 0; }
	cp -f "$ESP/boot.bin.stageE" "$ESP/boot.bin.new" && sync && mv -f "$ESP/boot.bin.new" "$ESP/boot.bin" && sync || return 1
	[ "$(sha "$ESP/boot.bin")" = "$STAGEE_SHA" ] || die "boot.bin hash wrong after the switch back"
	say "boot.bin is stageE again (the next boot has no Secure Enclave); boot.bin.stageS is kept for a later retry"
}

# ---------------------------------------------------------------- PAM password test
pam_test() {
	local svc rc=0
	[ -n "${TI_TEST:-}" ] && { say "pam test skipped (TI_TEST)"; return 0; }
	[ -t 0 ] || { echo "[ti] the password test needs a terminal" >&2; return 1; }
	command -v python3 >/dev/null || return 1
	say "Password test: type the password of ${SUDO_USER:-your user} when asked. Services: kde (lock screen password) and plasmalogin (login screen)."
	for svc in kde plasmalogin; do
		python3 -I "$PAMTEST" "$svc" "${SUDO_USER:-}" || rc=1
	done
	return $rc
}

# ---------------------------------------------------------------- driver
step_fn() { echo "${1//-/_}"; }
run_apply() { local fn; fn="apply_$(step_fn "$1")"; "$fn"; }
run_undo() { local fn; fn="undo_$(step_fn "$1")"; "$fn"; }

do_install() {
	local nopam=0 s applied=() i
	for a in "$@"; do case "$a" in --no-pam-test) nopam=1;; *) die "unknown option $a";; esac; done
	need_root
	preflight || die "preflight failed; nothing was changed"
	mkdir -p "$STATE" "$BK" "$MARK"
	log "install start"
	for s in "${STEPS[@]}"; do
		say "step $s: apply"
		if run_apply "$s"; then applied+=("$s"); done_mark "$s"; log "step $s applied"
		else
			echo "[ti] STEP FAILED: $s. Undoing this run's steps, newest first." >&2; log "step $s failed"
			for ((i=${#applied[@]}-1; i>=0; i--)); do say "undo ${applied[$i]}"; run_undo "${applied[$i]}" || echo "[ti] undo of ${applied[$i]} failed" >&2; clear_mark "${applied[$i]}"; done
			run_undo "$s" 2>/dev/null || true
			die "install failed at $s and was undone"
		fi
		if [ "$s" = pam-login ] && [ $nopam = 0 ]; then
			if ! pam_test; then
				echo "[ti] PASSWORD TEST FAILED. Undoing everything of this run." >&2
				for ((i=${#applied[@]}-1; i>=0; i--)); do run_undo "${applied[$i]}" || true; clear_mark "${applied[$i]}"; done
				die "password test failed; all steps undone"
			fi
		fi
	done
	for s in sudo system-auth password-auth login sshd; do [ -e "$R/etc/pam.d/$s" ] && echo "$s $(sha "$(readlink -f "$R/etc/pam.d/$s")")"; done > "$STATE/pam-untouched.sha"
	log "install done"
	say "ALL STEPS APPLIED. Nothing is loaded yet. Reboot once to start with the Secure Enclave, then run: ti-run.sh verify"
	say "Undo everything: sudo m3-touchid-install undo"
}

do_undo() {
	local list=() s i
	need_root
	if [ $# -gt 0 ]; then for s in "$@"; do printf '%s\n' "${STEPS[@]}" | grep -qx "$s" || die "unknown step $s"; list+=("$s"); done
	else list=("${STEPS[@]}"); fi
	log "undo ${list[*]}"
	# Newest first, in the fixed reverse order, not in the order given.
	for ((i=${#STEPS[@]}-1; i>=0; i--)); do
		s="${STEPS[$i]}"; printf '%s\n' "${list[@]}" | grep -qx "$s" || continue
		say "step $s: undo"
		run_undo "$s" && clear_mark "$s" || echo "[ti] undo of $s FAILED; carry on with the next step and read the log" >&2
	done
	say "undo finished. Check: m3-touchid-install status"
}

do_status() {
	local s st
	for s in "${STEPS[@]}"; do is_done "$s" && st="applied $(cat "$MARK/$s.done")" || st="not applied"; printf '%-10s %s\n' "$s" "$st"; done
	[ -f "$ESP/boot.bin" ] && echo "boot.bin   sha $(sha "$ESP/boot.bin" | cut -c1-8) ($( [ "$(sha "$ESP/boot.bin")" = "$STAGEE_SHA" ] && echo stageE || { [ -f "$ESP/boot.bin.stageS" ] && [ "$(sha "$ESP/boot.bin")" = "$(sha "$ESP/boot.bin.stageS")" ] && echo stageS || echo unknown; } ))"
	[ -f "$STATE/bootbin.env" ] && sed 's/^/bootbin.env: /' "$STATE/bootbin.env"
}

# Post-reboot checks. Read-only. The alarm check runs from ti-run.sh (needs the user context).
do_verify() {
	local bad=0 v u="${SUDO_USER:-${TI_USER:-}}" out
	need_root
	ok() { say "ok: $*"; }; no() { echo "[ti] FAIL: $*" >&2; bad=1; }
	[ "$(uname -r)" = "$KREL" ] && ok "kernel $KREL" || no "kernel is $(uname -r)"
	ls /proc/device-tree/soc/sep@*/iboot-manifest >/dev/null 2>&1 && ok "boot has the Secure Enclave device nodes (stageS)" || no "no sep node in the device tree: this boot used stageE or stock"
	grep -q '^apple_sep ' /proc/modules && ok "apple_sep is loaded" || no "apple_sep is not loaded (see: journalctl -u m3-touchid)"
	for v in xart_guard=3 sensor_rearm_mode=2 sensor_rearm_settle_ms=1800; do
		[ "$(cat "/sys/module/apple_sep/parameters/${v%%=*}" 2>/dev/null)" = "${v#*=}" ] && ok "parameter $v" || no "parameter ${v%%=*} is '$(cat "/sys/module/apple_sep/parameters/${v%%=*}" 2>/dev/null)', expected ${v#*=}"
	done
	[ "$(systemctl is-active m3-touchid.service 2>/dev/null)" = active ] && ok "m3-touchid.service is active" || no "m3-touchid.service is not active"
	journalctl -u m3-touchid.service -b --no-pager 2>/dev/null | grep -q 'Touch ID is ready' && ok "journal: Touch ID is ready" || no "journal has no 'Touch ID is ready' line"
	[ -c /dev/sep-bio ] && ok "/dev/sep-bio exists" || no "/dev/sep-bio missing"
	if [ -x "$R/usr/bin/fprintd-list" ] && [ -n "$u" ]; then
		out=$(timeout 30 fprintd-list "$u" 2>&1) && echo "$out" | grep -q 'found 1 devices' && ok "fprintd sees the reader" || no "fprintd-list: $(echo "$out" | head -n2 | tr '\n' ' ')"
		echo "$out" | sed 's/^/[ti]   /'
	fi
	systemctl show fprintd.service -p Environment 2>/dev/null | grep -q 'LD_LIBRARY_PATH=/opt/aurora-sep/lib64' && ok "fprintd runs with the private libfprint path" || no "fprintd unit has no LD_LIBRARY_PATH drop-in"
	out=$(ausearch -m avc,user_avc -ts boot 2>/dev/null | grep -E 'fprintd|sep-bio' || true)
	[ -z "$out" ] && ok "no SELinux denial for fprintd or sep-bio since boot" || { no "SELinux denials:"; echo "$out" | tail -n 8; }
	grep -q '^-auth.*pam_fprintd.so' "$pam_lock_file" 2>/dev/null && ok "kde-fingerprint has the fingerprint line" || no "kde-fingerprint has no fingerprint line"
	grep -qF -e "$PAM_LOGIN_LINE" "$pam_login_file" 2>/dev/null && ok "plasmalogin has the fingerprint line" || no "plasmalogin override missing"
	if [ -f "$STATE/pam-untouched.sha" ]; then
		while read -r s h; do [ "$(sha "$(readlink -f "$R/etc/pam.d/$s")")" = "$h" ] && ok "pam.d/$s unchanged" || no "pam.d/$s differs from the install time"; done < "$STATE/pam-untouched.sha"
	fi
	if [ -f "$STATE/bootbin.env" ]; then . "$STATE/bootbin.env"; [ "$(sha "$ESP/boot.bin")" = "$S_SHA" ] && ok "boot.bin is stageS" || no "boot.bin is not stageS (did m3gpu-default gpu run?)"; fi
	[ $bad = 0 ] && say "VERIFY PASS (still to do by hand: password login after the reboot, lock screen with finger and password, alarm check)" || say "VERIFY FAILED: see the lines above"
	return $bad
}

CMD="${1:-}"; shift || true
case "$CMD" in
	preflight) need_root; preflight && say "PREFLIGHT PASS" || { echo "[ti] PREFLIGHT FAILED" >&2; exit 1; } ;;
	install) do_install "$@" ;;
	undo) do_undo "$@" ;;
	status) do_status ;;
	verify) do_verify ;;
	step) [ $# = 2 ] || die "usage: step NAME apply|undo"; need_root; mkdir -p "$STATE" "$BK" "$MARK"
		case "$2" in apply) run_apply "$1" && done_mark "$1";; undo) run_undo "$1" && clear_mark "$1";; *) die "apply or undo";; esac ;;
	pam-test) pam_test ;;
	*) sed -n '2,16p' "$0"; exit 2 ;;
esac
