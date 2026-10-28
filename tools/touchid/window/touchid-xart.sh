#!/usr/bin/env bash
# Touch ID stage 3b, safety net for the shared xART store (the iBootSystemContainer partition).
# Usage (as the user, NOT with sudo; needs sudo -n):
#   touchid-xart.sh backup             READ-ONLY toward the partition. Checks the APFS layout with the read-only
#                                      inspector, copies the partition raw to DEST, copies the Touch ID state files,
#                                      re-reads the partition and compares hashes, writes MANIFEST.
#   touchid-xart.sh verify [DIR]       re-hash the image in DIR (default: the newest backup) against its MANIFEST.
#   touchid-xart.sh diff [DIR]         READ-ONLY. Compares the partition with a backup image (default: the newest) and
#                                      lists which xART slots changed (kind, length, revision, never contents or ids).
#   touchid-xart.sh restore DIR --yes --accept-replay-risk
#                                      WRITES the partition: puts the image back and moves the Linux Touch ID state
#                                      files aside. Only in a normal boot with apple_sep not loaded.
# DEST is /data/touchid-backup (override: TOUCHID_BACKUP_DIR). Everything in it is private (root, 0600).
# A restored image brings back the APFS and xART files only. It does NOT roll back the Secure Enclave's own
# anti-replay state (XART-SAFETY.md says so). If the enclave committed writes after the backup, restoring makes the
# store OLDER than the enclave expects, which is the rollback case anti-replay exists to catch. Do not restore just
# because the partition differs from the backup: run diff first and restore only when something is actually broken.
set -uo pipefail
[ "$(id -u)" != 0 ] || { echo "[xart] STOP: run as the user, not with sudo (the script calls sudo -n itself)" >&2; exit 1; }
CMD="${1:-}"; shift || true
UHOME="/home/${SUDO_USER:-$USER}"
PART="${XART_TEST_PART:-/dev/disk/by-partlabel/iBootSystemContainer}"
TOOL="${XART_TEST_TOOL:-$UHOME/m3gpu/src/linux/tools/aurora-sep/apfs-xart-inspect.py}"
DEST="${TOUCHID_BACKUP_DIR:-/data/touchid-backup}"
KREL=7.2.11-m3gpu+
STATE=(/var/lib/aurora-sep-host-state.bin /var/lib/apple-sep-catacomb-master.bin /var/lib/apple-sep-catacomb-owner.bin
       /var/lib/apple-sep-catacomb-user.bin /var/lib/aurora-sep-refkey.bin /var/lib/aurora-sep-refkey-v2.bin
       /var/lib/aurora-sep-keybag.bin /var/lib/aurora-sep-xart-owned.bin)
say() { echo "[xart] $*"; }
die() { echo "[xart] STOP: $*" >&2; exit 1; }
rt() { sudo -n "$@"; }
sudo -n true 2>/dev/null || die "sudo -n does not work (the sudo window is closed)"

common_guards() { # "ro": the command only reads, so a loaded apple_sep is fine
	if [ -z "${XART_TEST_PART:-}" ]; then
		[ "$(uname -r)" = "$KREL" ] || die "running kernel is $(uname -r), expected $KREL"
		[ "${1:-}" = ro ] || { lsmod | grep -q '^apple_sep' && die "apple_sep is loaded. Use a normal boot (it is never unloaded in a test boot)."; }
		rt test -b "$PART" || die "$PART is not a block device"
		rt lsblk -no MOUNTPOINTS "$(readlink -f "$PART")" | grep -q . && die "$PART is mounted"
	else say "TEST MODE: $PART"; fi
}
sha() { rt sha256sum "$1" | cut -d' ' -f1; }
newest() { ls -1dt "$DEST"/ibootsys-* 2>/dev/null | head -n1; }

case "$CMD" in
backup)
	common_guards
	[ -f "$TOOL" ] || die "$TOOL is missing"
	TS=$(date +%Y%m%d-%H%M%S); D="$DEST/ibootsys-$TS"
	[ ! -e "$D" ] || die "$D already exists (two runs in one second?). Wait a second and run again."
	rt install -d -m 0700 -o "$(id -u)" -g "$(id -g)" "$DEST" "$D"
	psize=$(rt blockdev --getsize64 "$PART" 2>/dev/null || rt stat -L -c %s "$PART")
	free=$(df -B1 --output=avail "$DEST" | tail -n1 | tr -d ' ')
	[ "$free" -ge $((psize * 3)) ] || die "not enough free space in $DEST ($free bytes, need three times $psize)"
	# 1. layout check, read only
	say "1/4 read-only APFS layout check (the driver's own write rules need exactly this layout)"
	rt python3 -I "$TOOL" "$PART" > "$D/inspect.txt" 2> "$D/inspect.err"; irc=$?
	cat "$D/inspect.err"
	ok=1; why=""
	[ $irc = 0 ] || { ok=0; why="$why inspector exit $irc;"; }
	grep -q 'snapshot_count=0 revert_xid=0 revert_sblock=0' "$D/inspect.txt" || { ok=0; why="$why snapshot or revert state;"; }
	grep -qE '^gigalocker_extents_logical_bytes_physical_blocks_flags=\[\(0, 6291456, [0-9]+, 0, [0-9]+\)\]$' "$D/inspect.txt" || { ok=0; why="$why not exactly one plain 6 MiB .gl extent;"; }
	grep -q '^gigalocker_extent_reference_block_length_kind_owner_refcount=' "$D/inspect.txt" || { ok=0; why="$why no single owned extent reference;"; }
	grep -q '^gigalocker_records_slot_kind_length_revision_crc_valid=.*False' "$D/inspect.txt" && { ok=0; why="$why a record has a bad CRC;"; }
	grep -E '^raw_locator_best_block=' "$D/inspect.txt" | grep -q 'shift_blocks=0 ' || say "NOTE: raw locator shift is not 0 (information only; the driver uses the APFS-resolved extent)"
	grep -q '^crc_valid_root_signatures_outside_apfs_gl=\[\]' "$D/inspect.txt" || say "NOTE: root signatures exist outside the .gl extent (stale copies; information only)"
	if [ $ok = 1 ]; then say "1/4 PASS: one plain 6 MiB .gl extent, no snapshots, no revert state, all records CRC valid"
	else say "1/4 FAIL:$why Writes would be refused by the driver. No backup made."; rt rm -rf "$D"; exit 1; fi
	# 2. raw copy
	say "2/4 raw copy of $PART ($psize bytes) to $D/ibootsys.img (read only on the partition)"
	rt dd if="$PART" of="$D/ibootsys.img" bs=4M conv=fsync status=none || { rt rm -rf "$D"; die "dd failed"; }
	rt chmod 0600 "$D/ibootsys.img"
	# 3. two independent reads of the partition and the copy
	say "3/4 hashing the copy and re-reading the partition"
	a=$(sha "$D/ibootsys.img"); b=$(sha "$PART")
	[ "$a" = "$b" ] || { say "3/4 FAIL: copy $a differs from the partition $b (something wrote to the partition during the copy?)"; exit 1; }
	[ "$(rt stat -c %s "$D/ibootsys.img")" = "$psize" ] || { say "3/4 FAIL: size differs"; exit 1; }
	say "3/4 PASS: copy and partition hash equal ($psize bytes)"
	# 4. state files
	say "4/4 Touch ID state files"
	rt install -d -m 0700 -o "$(id -u)" -g "$(id -g)" "$D/state"; n=0
	for f in "${STATE[@]}"; do if rt test -e "$f"; then rt cp -p "$f" "$D/state/"; n=$((n + 1)); echo "  kept $(basename "$f") $(rt stat -c %s "$f") bytes"; fi; done
	{ echo "date=$TS"; echo "partition=$PART"; echo "bytes=$psize"; echo "sha256=$a"; echo "state_files=$n"; echo "kernel=$(uname -r)"; } | rt tee "$D/MANIFEST" >/dev/null
	rt chown -R "$(id -u):$(id -g)" "$D" 2>/dev/null || true; rt chmod -R go-rwx "$D"
	say "BACKUP PASS: $D (image sha256 $a, $n state files). Keep a second copy off this Mac, for example: scp -r the folder to the Mac host (the image is private: do not commit it)."
	say "Restore later: $0 restore $D --yes   (read the header of this script first)"
	;;
verify)
	D="${1:-$(newest)}"; [ -n "$D" ] && [ -d "$D" ] || die "no backup folder"
	[ -f "$D/MANIFEST" ] || die "no MANIFEST in $D"
	want=$(sed -n 's/^sha256=//p' "$D/MANIFEST"); got=$(sha "$D/ibootsys.img")
	[ "$want" = "$got" ] && say "VERIFY PASS: $D image hash equals the MANIFEST ($want)" || { say "VERIFY FAIL: image $got, MANIFEST $want"; exit 1; }
	;;
diff)
	common_guards ro
	D="${1:-$(newest)}"; [ -n "$D" ] && [ -f "$D/ibootsys.img" ] || die "no backup image"
	[ -f "$TOOL" ] || die "$TOOL is missing"
	blk=$(rt python3 -I "$TOOL" "$PART" 2>/dev/null | sed -n 's/^gigalocker_extents_logical_bytes_physical_blocks_flags=\[(0, 6291456, \([0-9]*\), .*/\1/p')
	[ -n "$blk" ] || die "could not resolve the .gl extent with the inspector"
	say "comparing $PART with $D/ibootsys.img (.gl extent at APFS block $blk)"
	rt python3 -I - "$PART" "$D/ibootsys.img" "$blk" <<'PY'
import sys, zlib, os
part, img, glblk = sys.argv[1], sys.argv[2], int(sys.argv[3])
BS = 4096; GL0 = glblk; GLN = 0x600000 // BS; SLOT = 0x9000
fa, fb = os.open(part, os.O_RDONLY), os.open(img, os.O_RDONLY)
sa, sb = os.lseek(fa, 0, os.SEEK_END), os.lseek(fb, 0, os.SEEK_END)
diff = []; off = 0; CH = 4 * 1024 * 1024
while off < max(sa, sb):
    a = os.pread(fa, CH, off); b = os.pread(fb, CH, off)
    if a != b:
        for i in range(0, max(len(a), len(b)), BS):
            if a[i:i + BS] != b[i:i + BS]: diff.append((off + i) // BS)
    off += CH
inside = [b for b in diff if GL0 <= b < GL0 + GLN]; outside = [b for b in diff if not (GL0 <= b < GL0 + GLN)]
print("sizes: partition %d, image %d; differing 4 KiB blocks: %d (inside .gl %d, outside %d)" % (sa, sb, len(diff), len(inside), len(outside)))
if outside: print("OUTSIDE the .gl extent (APFS blocks): %s" % outside[:40])
slots = sorted({((b - GL0) * BS) // SLOT for b in inside} | {((b - GL0) * BS + BS - 1) // SLOT for b in inside})
def hdr(fd, s):
    d = os.pread(fd, 0x22 + 0x8000, GL0 * BS + s * SLOT)
    if not any(d[:0x22]): return "empty"
    ln = int.from_bytes(d[0x12:0x16], "little"); rev = int.from_bytes(d[0x1a:0x22], "little")
    ok = 1 <= ln <= 0x8000 and zlib.crc32(d[0x22:0x22 + ln]) == int.from_bytes(d[0x16:0x1a], "little")
    return "kind %d len %d rev %d crc_ok %s%s%s" % (d[1], ln, rev, ok, " uid " + d[2:6].hex() if d[1] > 2 else "", " (root)" if d[1] in (1, 2) else "")
for s in slots:
    print("slot %3d  image: %s" % (s, hdr(fb, s))); print("          now  : %s" % hdr(fa, s))
if not diff: print("IDENTICAL: the partition equals the backup")
PY
	;;
restore)
	D="${1:-}"; [ -n "$D" ] && [ -d "$D" ] || die "usage: $0 restore DIR --yes --accept-replay-risk"
	[ "${2:-}" = "--yes" ] && [ "${3:-}" = "--accept-replay-risk" ] || die "restore writes the partition and can leave the xART store OLDER than the enclave expects (anti-replay). Run '$0 diff' first. Add --yes --accept-replay-risk only if something is actually broken."
	common_guards
	want=$(sed -n 's/^sha256=//p' "$D/MANIFEST"); got=$(sha "$D/ibootsys.img")
	[ "$want" = "$got" ] || die "image hash differs from the MANIFEST ($got vs $want). Not restoring."
	[ "$(rt stat -c %s "$D/ibootsys.img")" = "$(sed -n 's/^bytes=//p' "$D/MANIFEST")" ] || die "image size differs from the MANIFEST"
	say "writing $D/ibootsys.img to $PART"
	rt dd if="$D/ibootsys.img" of="$PART" bs=4M conv=fsync status=none || die "dd failed. The partition may be half written: run restore again."
	[ "$(sha "$PART")" = "$want" ] || die "partition hash after the write differs. Run restore again."
	say "partition equals the backup"
	TS=$(date +%Y%m%d-%H%M%S); ASIDE="$DEST/linux-state-aside-$TS"; rt install -d -m 0700 "$ASIDE"
	for f in "${STATE[@]}"; do if rt test -e "$f"; then rt mv "$f" "$ASIDE/" || die "could not move $f aside. The partition IS restored; move the Linux state files by hand before loading the driver."; echo "  moved $(basename "$f") aside"; fi; done
	say "RESTORE PASS. Linux Touch ID state files are in $ASIDE. Reboot before anything else."
	;;
*) sed -n '2,18p' "$0"; exit 2;;
esac
