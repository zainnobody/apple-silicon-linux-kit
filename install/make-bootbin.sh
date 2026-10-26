#!/usr/bin/env bash
# Assemble an m1n1 boot.bin the same way Fedora's update-m1n1 does:
#   m1n1 stage 2 + DTBs + gzip(U-Boot) + m1n1 config lines
# Writes only to $ESP_M1N1/boot.bin.<stage>. Never touches boot.bin itself.
# Usage: sudo install/make-bootbin.sh <stage> <m1n1.bin> <dtb-dir> [chosen.x=y ...]
. "$(dirname "$0")/lib.sh"
need_root
[ $# -ge 3 ] || { echo "usage: $0 <stage> <m1n1.bin> <dtb-dir> [chosen.x=y ...]" >&2; exit 1; }

STAGE="$1"; M1N1="$2"; DTBDIR="$3"; shift 3
TARGET="$ESP_M1N1/boot.bin.$STAGE"

[ -f "$M1N1" ] || { echo "No m1n1 at $M1N1" >&2; exit 1; }
[ -f "$DTBDIR/apple/$AGX_DTB_NAME" ] || { echo "No $AGX_DTB_NAME in $DTBDIR" >&2; exit 1; }

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
sha256sum "$TARGET" "$M1N1" "$DTBDIR/apple/$AGX_DTB_NAME"
echo "m1n1 options:"; cat "$CONF"; rm -f "$CONF"
echo "Free on ESP: $(df -h /boot/efi | tail -1 | awk '{print $4}')"
