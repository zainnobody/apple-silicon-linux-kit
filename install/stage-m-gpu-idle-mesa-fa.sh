#!/usr/bin/env bash
# Stage M: prepare one test boot. Does not reboot. Run with sudo.
# - Installs the staged Mesa with patches/mesa-agx3-fmul-narrow-wait.patch (llama.cpp flash
#   attention) into /opt/mesa-m3, after a full backup. GPU programs use it after they restart.
# - Adds asahi.g15_idle_standby_us=100000 to the 7.2.11-m3gpu+ boot entry only: the GPU stays
#   powered 100 ms after its last job (default 2.5 ms). Test: does GPU compute keep its clock
#   on bursty loads (docs/performance.md, "What limits this test")? The stock entry is not changed.
# Stage the Mesa first, as the desktop user: DESTDIR=~/m3gpu/out/mesa-stage-fa ninja -C ~/m3gpu/build-mesa install
# Undo: rsync -a --delete <backup>/mesa-m3/ /opt/mesa-m3/
#       grubby --update-kernel=/boot/vmlinuz-7.2.11-m3gpu+ --remove-args=asahi.g15_idle_standby_us=100000
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }
KREL=7.2.11-m3gpu+
KIMG=/boot/vmlinuz-$KREL
ARG=asahi.g15_idle_standby_us=100000
STAGE=/home/user/m3gpu/out/mesa-stage-fa/opt/mesa-m3
BACKUP="/root/m3gpu-backup/$(date +%Y%m%d-%H%M%S)-pre-mesa-fa"

# Checks before any change.
grep -q "apple,j516s" /proc/device-tree/compatible || { echo "Not a J516S" >&2; exit 1; }
[ -f "$KIMG" ] || { echo "No $KIMG" >&2; exit 1; }
[ -f "$STAGE/lib64/libgallium-26.3.0-devel.so" ] && [ -f "$STAGE/share/vulkan/icd.d/asahi_icd.aarch64.json" ] \
	|| { echo "Staged Mesa missing in $STAGE" >&2; exit 1; }
[ -d /opt/mesa-m3/lib64 ] || { echo "No /opt/mesa-m3" >&2; exit 1; }

# Backup.
mkdir -p "$BACKUP"
cp -a /opt/mesa-m3 "$BACKUP/mesa-m3"
grubby --info="$KIMG" > "$BACKUP/grubby-info.txt"
echo "backup: $BACKUP"

# Mesa.
rsync -a --delete "$STAGE/" /opt/mesa-m3/
cmp -s "$STAGE/lib64/libgallium-26.3.0-devel.so" /opt/mesa-m3/lib64/libgallium-26.3.0-devel.so
echo "Mesa installed: $(sha256sum /opt/mesa-m3/lib64/libgallium-26.3.0-devel.so | cut -c1-16)"

# Boot argument, GPU entry only.
grubby --update-kernel="$KIMG" --args="$ARG"
grubby --info="$KIMG" | grep -q "$ARG" || { echo "Argument not set" >&2; exit 1; }
grubby --info=ALL | grep -E "^(kernel|args)="
echo "STAGE_M_DONE (reboot is a separate step)"
