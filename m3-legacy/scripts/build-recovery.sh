#!/usr/bin/env bash
# Incremental rebuild of the test kernel with patches/g15-recovery-drain-halt.patch (the drain loop answers
# a halt that comes after the queues drained) on top of patches/g15-perf-tgt-util.patch. Builds only.
set -euo pipefail
K=$HOME/m3gpu/src/linux; B=$HOME/m3gpu/build-linux; L=$HOME/m3gpu/logs/kernel-recovery.log
mkdir -p "$(dirname "$L")"
grep -q "DRAIN_QUIET_POLLS" "$K/drivers/gpu/drm/asahi-m3/g15/recovery/logic.rs" || { echo "patch not applied" > "$L"; exit 1; }
nice -n 19 make -C "$K" O="$B" -j6 Image modules > "$L" 2>&1 || { echo BUILD_FAILED >> "$L"; exit 1; }
KREL=$(make -s -C "$K" O="$B" kernelrelease)
S=$HOME/m3gpu/out/kernel-$KREL-recovery
rm -rf "$S"; mkdir -p "$S/boot"
cp "$B/arch/arm64/boot/Image" "$S/boot/vmlinuz-$KREL"
cp "$B/.config" "$S/boot/config-$KREL"
cp "$B/System.map" "$S/boot/System.map-$KREL"
make -C "$K" O="$B" INSTALL_MOD_PATH="$S" INSTALL_MOD_STRIP=1 modules_install > /dev/null
strings "$S/boot/vmlinuz-$KREL" | grep -c "g15_perf_tgt_util" >> "$L"
sha256sum "$S/boot/vmlinuz-$KREL" >> "$L"
echo "BUILD_DONE $S" >> "$L"
