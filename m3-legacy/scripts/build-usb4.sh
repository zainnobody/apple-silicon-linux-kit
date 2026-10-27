#!/usr/bin/env bash
# Incremental rebuild of the test kernel with CONFIG_USB4_APPLE_SOC=m; stages into out/kernel-<rel>-usb4-bt. Builds only.
set -euo pipefail
K=$HOME/m3gpu/src/linux; B=$HOME/m3gpu/build-linux; L=$HOME/m3gpu/logs/kernel-usb4-bt.log
grep -qx "CONFIG_USB4_APPLE_SOC=m" "$B/.config" || { echo "USB4_APPLE_SOC not set" > "$L"; exit 1; }
nice -n 10 make -C "$K" O="$B" -j8 Image modules > "$L" 2>&1 || { echo BUILD_FAILED >> "$L"; exit 1; }
KREL=$(make -s -C "$K" O="$B" kernelrelease)
S=$HOME/m3gpu/out/kernel-$KREL-usb4-bt
rm -rf "$S"; mkdir -p "$S/boot"
cp "$B/arch/arm64/boot/Image" "$S/boot/vmlinuz-$KREL"
cp "$B/.config" "$S/boot/config-$KREL"
cp "$B/System.map" "$S/boot/System.map-$KREL"
make -C "$K" O="$B" INSTALL_MOD_PATH="$S" INSTALL_MOD_STRIP=1 modules_install > /dev/null
grep -c apple_pmp_t6030_floor_work "$S/boot/System.map-$KREL" >> "$L"
sha256sum "$S/boot/vmlinuz-$KREL" >> "$L"
echo "BUILD_DONE $S" >> "$L"
