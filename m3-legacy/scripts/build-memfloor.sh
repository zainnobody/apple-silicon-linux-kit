#!/usr/bin/env bash
# Incremental rebuild of the test kernel with the memory floor call; stages into out/kernel-<rel>-memfloor.
set -euo pipefail
K=$HOME/m3gpu/src/linux; B=$HOME/m3gpu/build-linux; L=$HOME/m3gpu/logs/kernel-memfloor.log
make -C "$K" O="$B" -j12 Image modules > "$L" 2>&1 || { echo BUILD_FAILED >> "$L"; exit 1; }
KREL=$(make -s -C "$K" O="$B" kernelrelease)
S=$HOME/m3gpu/out/kernel-$KREL-memfloor
rm -rf "$S"; mkdir -p "$S/boot"
cp "$B/arch/arm64/boot/Image" "$S/boot/vmlinuz-$KREL"
cp "$B/.config" "$S/boot/config-$KREL"
cp "$B/System.map" "$S/boot/System.map-$KREL"
make -C "$K" O="$B" INSTALL_MOD_PATH="$S" INSTALL_MOD_STRIP=1 modules_install > /dev/null
grep -c apple_pmp_t6030_floor_work "$S/boot/System.map-$KREL" >> "$L"
sha256sum "$S/boot/vmlinuz-$KREL" >> "$L"
echo "BUILD_DONE $S" >> "$L"
