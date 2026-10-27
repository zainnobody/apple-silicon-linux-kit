#!/usr/bin/env bash
# Assemble an m1n1 boot.bin the same way Fedora's update-m1n1 does:
#   m1n1 stage 2 + DTBs + gzip(U-Boot) + m1n1 config lines
# Writes only to /boot/efi/m1n1/boot.bin.<stage>. Never touches boot.bin itself.
# Usage: sudo make-bootbin.sh <stage> <m1n1.bin> <dtb-dir> [extra chosen line ...]
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }
[ $# -ge 3 ] || { echo "usage: $0 <stage> <m1n1.bin> <dtb-dir> [chosen.x=y ...]" >&2; exit 1; }

STAGE="$1"; M1N1="$2"; DTBDIR="$3"; shift 3
UBOOT=/usr/share/uboot/apple_m1/u-boot-nodtb.bin
TARGET="/boot/efi/m1n1/boot.bin.$STAGE"

[ -f "$M1N1" ] || { echo "No m1n1 at $M1N1" >&2; exit 1; }
[ -f "$DTBDIR/apple/t6030-j516s.dtb" ] || { echo "No t6030-j516s.dtb in $DTBDIR" >&2; exit 1; }

CONF="$(mktemp)"
# Keep the active options from /etc/m1n1.conf, as update-m1n1 does.
grep -E '^(chosen\.[^=]+|display|mitigations)=' /etc/m1n1.conf > "$CONF" || true
for line in "$@"; do
	[[ "$line" =~ ^chosen\.[A-Za-z0-9,._-]+=[^[:space:]]+$ ]] || { echo "Bad option: $line" >&2; exit 1; }
	echo "$line" >> "$CONF"
done

# Same DTB set as update-m1n1 (t6* and t81*), from the given folder.
cat "$M1N1" "$DTBDIR"/apple/t6*.dtb "$DTBDIR"/apple/t81*.dtb > "$TARGET.new"
gzip -c "$UBOOT" >> "$TARGET.new"
cat "$CONF" >> "$TARGET.new"
mv -f "$TARGET.new" "$TARGET"
sync

echo "=== $TARGET"
ls -la "$TARGET"
sha256sum "$TARGET" "$M1N1" "$DTBDIR/apple/t6030-j516s.dtb"
echo "m1n1 options:"; cat "$CONF"; rm -f "$CONF"
echo "Free on ESP: $(df -h /boot/efi | tail -1 | awk '{print $4}')"
