#!/usr/bin/env bash
# Offline test of tools/touchid/integration/ti-install.sh in a fake root with stub system commands.
# Needs no root and touches nothing outside a temporary directory. Run: tests/touchid-integration-test.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; INT="$HERE/../tools/touchid/integration"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
KREL=7.2.11-m3gpu+
pass=0; fail=0
ok() { echo "PASS  $*"; pass=$((pass+1)); }
no() { echo "FAIL  $*"; fail=$((fail+1)); }
chk() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else no "$d"; fi; }
sha() { shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1 || sha256sum "$1" | cut -d' ' -f1; }

R="$T/root"; S="$T/stubs"; U="$T/home"; mkdir -p "$S" "$U"
mkdir -p "$R/lib/modules/$KREL" "$R/boot/efi/m1n1" "$R/boot/dtb-$KREL/apple" "$R/usr/lib64/security" "$R/usr/libexec" "$R/usr/lib/pam.d" \
	"$R/etc/pam.d" "$R/etc/sysconfig" "$R/etc/systemd/system" "$R/lib/firmware/apple" "$R/usr/local/bin" "$R/var/lib" "$T/backups/20260101-000000"
ln -s bin "$R/usr/local/sbin"
: > "$R/usr/lib64/security/pam_fprintd.so"; printf '#!/bin/sh\n' > "$R/usr/libexec/fprintd"; chmod +x "$R/usr/libexec/fprintd"
: > "$R/lib/firmware/apple/mesacal-j516s.bin"; echo 'M1N1_UPDATE_DISABLED=1' > "$R/etc/sysconfig/update-m1n1"
cat > "$R/usr/lib/pam.d/plasmalogin" <<'PAM'
auth     [success=done ignore=ignore default=bad] pam_selinux_permit.so
auth        substack      password-auth
-auth        optional      pam_kwallet5.so
auth        include       postlogin

account     required      pam_nologin.so
account     include       password-auth
PAM
cat > "$R/etc/pam.d/kde" <<'PAM'
auth        substack      password-auth
auth        include       postlogin
PAM
cat > "$R/etc/pam.d/kde-fingerprint" <<'PAM'
auth        substack      fingerprint-auth
auth        include       postlogin
PAM
for f in sudo system-auth password-auth login sshd; do echo "pam $f" > "$R/etc/pam.d/$f"; done
# Boot files: stageE = head + base dtb + tail. New file = head + merged dtb + tail.
python3 - "$R" <<'PY'
import struct, sys
r = sys.argv[1]
def dtb(tag, n): b = b"\xd0\x0d\xfe\xed" + struct.pack(">I", n) + tag * (n - 8); return b[:n]
base, merged = dtb(b"B", 200), dtb(b"M", 260)
head, tail = b"M1N1HEAD" * 50, b"UBOOT-GZ-AND-CONF" * 20
open(r + "/boot/dtb-7.2.11-m3gpu+/apple/t6030-j516s.dtb", "wb").write(base)
open(r + "/boot/efi/m1n1/boot.bin.stageE", "wb").write(head + base + tail)
open(r + "/boot/efi/m1n1/boot.bin", "wb").write(head + base + tail)
open(r + "/boot/efi/m1n1/boot.bin.stock", "wb").write(b"stock")
open(r + "/../merged.dtb", "wb").write(merged)
open(r + "/../expected-boot.bin.sep", "wb").write(head + merged + tail)
PY
echo "module image" > "$T/apple-sep-3f.ko"; echo "rpm image" > "$T/libfprint-aurora.rpm"

# Stub commands (they log their calls).
for c in systemctl depmod restorecon semanage semodule semodule_package; do printf '#!/bin/sh\necho "%s $*" >> "%s/calls.log"\nexit 0\n' "$c" "$T" > "$S/$c"; done
printf '#!/bin/sh\nfor a in "$@"; do case "$a" in -o) o=1;; *) [ "${o:-}" = 1 ] && : > "$a"; o=;; esac; done\nexit 0\n' > "$S/checkmodule"
cat > "$S/modinfo" <<'SH'
#!/bin/sh
case "$*" in *filename*) echo "/lib/modules/7.2.11-m3gpu+/updates/apple_sep.ko";; *parm*) echo "sensor_rearm_mode:re-arm";; esac
SH
cat > "$S/rpm" <<SH
#!/bin/sh
echo "rpm \$*" >> "$T/calls.log"
case "\$1" in
	-q) [ -e "$T/rpm-installed" ] && exit 0 || exit 1;;
	-qpl) echo /opt/aurora-sep/lib64/libfprint-2.so.2;;
	-i) if [ "\$2" != "--test" ]; then mkdir -p "$R/opt/aurora-sep/lib64"; echo aurora_driver > "$R/opt/aurora-sep/lib64/libfprint-2.so.2"; touch "$T/rpm-installed"; fi;;
	-e) rm -rf "$R/opt/aurora-sep" "$T/rpm-installed";;
esac
exit 0
SH
chmod +x "$S"/*
export PATH="$S:$PATH" TI_ROOT="$R" TI_TEST=1 TI_UHOME="$U" TI_KREL="$KREL" TOUCHID_BACKUP_DIR="$T/backups"
export TI_MODULE="$T/apple-sep-3f.ko" TI_MODULE_SHA="$(sha "$T/apple-sep-3f.ko")" TI_RPM="$T/libfprint-aurora.rpm" TI_RPM_SHA="$(sha "$T/libfprint-aurora.rpm")"
export TI_STAGEE_SHA="$(sha "$R/boot/efi/m1n1/boot.bin.stageE")" TI_BASE_DTB_PFX="$(sha "$R/boot/dtb-$KREL/apple/t6030-j516s.dtb" | cut -c1-8)"
export TI_BOOT_NEW="$T/expected-boot.bin.sep" TI_BOOT_DTB="$T/merged.dtb"
INSTALL="$INT/ti-install.sh"
orig_lock=$(sha "$R/etc/pam.d/kde-fingerprint"); stagee=$TI_STAGEE_SHA; newsha=$(sha "$TI_BOOT_NEW")

# 1 preflight
"$INSTALL" preflight >"$T/o1" 2>&1 && ok "preflight passes on a good fake root" || { no "preflight on a good fake root"; cat "$T/o1"; }

# 2 install
"$INSTALL" install >"$T/o2" 2>&1 && ok "install runs all steps" || { no "install"; cat "$T/o2"; }
chk "module copied" test -f "$R/lib/modules/$KREL/updates/apple_sep.ko"
chk "unit, loader, conf, self copy installed" test -f "$R/etc/systemd/system/m3-touchid.service" -a -x "$R/usr/local/sbin/m3-touchid-load" -a -f "$R/etc/m3-touchid.conf" -a -x "$R/usr/local/sbin/m3-touchid-install"
chk "fprintd drop-in installed" grep -q 'LD_LIBRARY_PATH=/opt/aurora-sep/lib64' "$R/etc/systemd/system/fprintd.service.d/aurora-private.conf"
chk "libfprint RPM installed" test -f "$R/opt/aurora-sep/lib64/libfprint-2.so.2"
chk "kde-fingerprint has the fingerprint line" grep -q '^-auth       required      pam_fprintd.so$' "$R/etc/pam.d/kde-fingerprint"
chk "plasmalogin: one fingerprint line" test "$(grep -c pam_fprintd "$R/etc/pam.d/plasmalogin")" = 1
chk "plasmalogin: fingerprint line sits between selinux_permit and the password substack" test "$(grep -n -e pam_selinux_permit -e pam_fprintd -e 'substack' "$R/etc/pam.d/plasmalogin" | cut -d: -f1 | tr '\n' ' ')" = "1 2 3 "
chk "plasmalogin keeps every vendor line" test "$(grep -v pam_fprintd "$R/etc/pam.d/plasmalogin" | cksum)" = "$(cksum < "$R/usr/lib/pam.d/plasmalogin")"
chk "boot.bin is the new file" test "$(sha "$R/boot/efi/m1n1/boot.bin")" = "$newsha"
chk "boot.bin.stageE untouched" test "$(sha "$R/boot/efi/m1n1/boot.bin.stageE")" = "$stagee"
chk "sudo, system-auth, password-auth, login, sshd never edited" test "$(cat "$R/etc/pam.d/sudo" "$R/etc/pam.d/system-auth" "$R/etc/pam.d/password-auth" "$R/etc/pam.d/login" "$R/etc/pam.d/sshd" | cksum)" = "$(for f in sudo system-auth password-auth login sshd; do echo "pam $f"; done | cksum)"
chk "status lists all steps applied" test "$("$R/usr/local/sbin/m3-touchid-install" status | grep -c applied)" = 8
chk "no systemctl start or reboot was issued" test "$(grep -c -E 'systemctl (start|restart|reboot)|reboot' "$T/calls.log")" = 0

# 3 install again (idempotent)
"$INSTALL" install >"$T/o3" 2>&1 && ok "second install run passes" || { no "second install"; cat "$T/o3"; }

# 4 undo all
"$R/usr/local/sbin/m3-touchid-install" undo >"$T/o4" 2>&1 && ok "undo all runs" || { no "undo"; cat "$T/o4"; }
chk "boot.bin back to stageE" test "$(sha "$R/boot/efi/m1n1/boot.bin")" = "$stagee"
chk "kde-fingerprint restored byte for byte" test "$(sha "$R/etc/pam.d/kde-fingerprint")" = "$orig_lock"
chk "plasmalogin override removed" test ! -e "$R/etc/pam.d/plasmalogin"
chk "module, units, drop-in, RPM removed" test ! -e "$R/lib/modules/$KREL/updates/apple_sep.ko" -a ! -e "$R/etc/systemd/system/m3-touchid.service" -a ! -e "$R/etc/systemd/system/fprintd.service.d/aurora-private.conf" -a ! -e "$R/opt/aurora-sep"
chk "SELinux module removal was called" grep -q 'semodule -r m3touchid' "$T/calls.log"

# 5 failure injection: a boot file that is not stageE + merged dtb must stop at the last step and undo the rest
cp "$TI_BOOT_NEW" "$T/bad.bin"; printf 'X' >> "$T/bad.bin"
TI_BOOT_NEW="$T/bad.bin" "$INSTALL" install >"$T/o5" 2>&1 && no "install with a bad boot file should fail" || ok "install with a bad boot file fails"
chk "bad boot file: boot.bin still stageE" test "$(sha "$R/boot/efi/m1n1/boot.bin")" = "$stagee"
chk "bad boot file: earlier steps undone (kde-fingerprint original, no plasmalogin, no module)" test "$(sha "$R/etc/pam.d/kde-fingerprint")" = "$orig_lock" -a ! -e "$R/etc/pam.d/plasmalogin" -a ! -e "$R/lib/modules/$KREL/updates/apple_sep.ko"

# 6 preflight refuses a changed fallback and a changed boot.bin
cp "$R/boot/efi/m1n1/boot.bin" "$T/boot.bin.keep"; echo tamper >> "$R/boot/efi/m1n1/boot.bin"
"$INSTALL" preflight >"$T/o6" 2>&1 && no "preflight should refuse a changed boot.bin" || ok "preflight refuses a changed boot.bin"
cp "$T/boot.bin.keep" "$R/boot/efi/m1n1/boot.bin"
echo tamper >> "$R/boot/efi/m1n1/boot.bin.stageE"
"$INSTALL" preflight >"$T/o7" 2>&1 && no "preflight should refuse a changed stageE" || ok "preflight refuses a changed stageE"

# 7 shell and python syntax of the boot-time pieces
chk "m3-touchid-load: sh -n" sh -n "$INT/m3-touchid-load"
chk "ti-run.sh: bash -n" bash -n "$INT/ti-run.sh"
chk "pam-auth-test.py compiles" python3 -I -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$INT/pam-auth-test.py"

echo "---- $pass passed, $fail failed"; [ $fail = 0 ]
