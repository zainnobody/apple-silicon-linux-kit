#!/usr/bin/env bash
# Touch ID stage 3a: is the Mesa calibration file in this Mac's iBoot system container?
# Usage: touchid-calib.sh [--install]     (run as the user, NOT with sudo; needs sudo -n)
#   (no flag)   READ-ONLY. Reads the iBootSystemContainer partition (raw, read only), carves the calibration
#               into ~/window/touchid/mesacal-j516s.bin (mode 0600, owned by the user) and prints PASS or FAIL.
#               It writes nothing to the partition and installs nothing.
#   --install   also copies the file to /lib/firmware/apple/mesacal-j516s.bin (root, 0644, SELinux label restored).
#               The driver needs it only after a keybag exists (stage 3b), not in stage 3a.
# The file is per-device factory data: it never leaves the M3, is never committed, and its hash is not printed.
set -uo pipefail
[ "$(id -u)" != 0 ] || { echo "[touchid-calib] STOP: run as the user, not with sudo (the script calls sudo -n itself)" >&2; exit 1; }
INSTALL=0
for a in "$@"; do case "$a" in --install) INSTALL=1;; *) echo "unknown option $a" >&2; exit 2;; esac; done
HERE="$(cd "$(dirname "$0")" && pwd)"; W="$HERE/touchid"
UHOME="/home/${SUDO_USER:-$USER}"
TOOL="$UHOME/m3gpu/src/linux/tools/aurora-sep/extract-mesa-calibration.py"
PART=/dev/disk/by-partlabel/iBootSystemContainer
TESTPART="${CALIB_TEST_PART:-}"   # offline test only: a regular file standing in for the partition
OUT="$W/mesacal-j516s.bin"
mkdir -p "$W/logs"
sudo -n true 2>/dev/null || { echo "[touchid-calib] STOP: sudo -n does not work"; exit 1; }
if [ -n "$TESTPART" ]; then PART="$TESTPART"; TOOL="${CALIB_TEST_TOOL:-$TOOL}"; echo "[touchid-calib] TEST MODE: $PART"
else
	sudo -n test -b "$PART" || { echo "[touchid-calib] FAIL: $PART is not a block device"; exit 1; }
	src=$(readlink -f "$PART")
	sudo -n lsblk -no MOUNTPOINTS "$src" | grep -q . && { echo "[touchid-calib] FAIL: $src is mounted"; exit 1; }
fi
[ -f "$TOOL" ] || { echo "[touchid-calib] FAIL: $TOOL is missing"; exit 1; }
echo "[touchid-calib] reading $PART (raw, read only; about 500 MB, up to a minute)"
TMP=$(mktemp -d "$W/.calib.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
# The extractor opens the partition read only and writes only the -o file. Output goes to a root-owned
# temporary file first, so the partition path is never an output target.
sudo -n python3 -I "$TOOL" "$PART" -o "$TMP/mesacal.bin" > "$TMP/out.txt" 2> "$TMP/err.txt"; rc=$?
sed -E 's/sha256 [0-9a-f]+/sha256 <not shown>/' "$TMP/out.txt"; cat "$TMP/err.txt"
if [ $rc != 0 ]; then echo "[touchid-calib] FAIL: no calibration carved (exit $rc). Stage 3a does not need it; stage 3b does."; exit 1; fi
sudo -n chown "$(id -u):$(id -g)" "$TMP/mesacal.bin" && chmod 0600 "$TMP/mesacal.bin"
size=$(stat -c %s "$TMP/mesacal.bin")
# Shape checks only (the extractor already validated the DER): a SEQUENCE start (0x30) and the IMG4, IM4P and
# CALB markers. No content is printed.
first=$(head -c1 "$TMP/mesacal.bin" | od -An -tx1 | tr -d ' ')
img4=$(grep -c -a -F 'IMG4' "$TMP/mesacal.bin" || true); im4p=$(grep -c -a -F 'IM4P' "$TMP/mesacal.bin" || true)
calb=$(grep -c -a -F 'CALB' "$TMP/mesacal.bin" || true)
kind=$(grep -q -a -F 'FSCl' "$TMP/mesacal.bin" && echo FSCl || { grep -q -a -F 'FSC2' "$TMP/mesacal.bin" && echo FSC2 || echo unknown; })
ok=1; [ "$size" -ge 256 ] || ok=0; [ "$first" = 30 ] || ok=0
[ "$img4" -ge 1 ] && [ "$im4p" -ge 1 ] && [ "$calb" -ge 1 ] && [ "$kind" != unknown ] || ok=0
if [ $ok = 1 ]; then
	mv -f "$TMP/mesacal.bin" "$OUT"
	echo "[touchid-calib] PASS: $OUT is $size bytes, type $kind, DER sequence start, IMG4/IM4P/CALB markers present"
else
	echo "[touchid-calib] FAIL: file shape wrong (size $size, first byte 0x$first, type $kind, IMG4 $img4, IM4P $im4p, CALB $calb)"; exit 1
fi
if [ $INSTALL = 1 ]; then
	sudo -n install -D -m 0644 -o root -g root "$OUT" /lib/firmware/apple/mesacal-j516s.bin && sudo -n restorecon -F /lib/firmware/apple/mesacal-j516s.bin 2>/dev/null
	cmp -s "$OUT" /lib/firmware/apple/mesacal-j516s.bin && echo "[touchid-calib] installed /lib/firmware/apple/mesacal-j516s.bin" || { echo "[touchid-calib] FAIL: install"; exit 1; }
else
	echo "[touchid-calib] not installed (re-run with --install when stage 3b needs it)"
fi
