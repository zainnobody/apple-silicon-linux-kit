#!/usr/bin/env bash
# Incremental rebuild of the test kernel with patches/g15-perf-boost-base.patch (module parameters for the
# firmware DVFS boost words and base state) on top of the recovery and tgt_util patches. Builds only.
set -euo pipefail
K=$HOME/m3gpu/src/linux; B=$HOME/m3gpu/build-linux; L=$HOME/m3gpu/logs/kernel-boost.log
mkdir -p "$(dirname "$L")"
grep -q "fn perf_overrides" "$K/drivers/gpu/drm/asahi-m3/g15/initdata.rs" || { echo "patch not applied" > "$L"; exit 1; }
nice -n 19 make -C "$K" O="$B" -j6 Image modules > "$L" 2>&1 || { echo BUILD_FAILED >> "$L"; exit 1; }
KREL=$(make -s -C "$K" O="$B" kernelrelease)
S=$HOME/m3gpu/out/kernel-$KREL-boost
rm -rf "$S"; mkdir -p "$S/boot"
cp "$B/arch/arm64/boot/Image" "$S/boot/vmlinuz-$KREL"
cp "$B/.config" "$S/boot/config-$KREL"
cp "$B/System.map" "$S/boot/System.map-$KREL"
make -C "$K" O="$B" INSTALL_MOD_PATH="$S" INSTALL_MOD_STRIP=1 modules_install > /dev/null
strings "$S/boot/vmlinuz-$KREL" | grep -c "g15_perf_boost_min\|g15_perf_base_pstate" >> "$L"
sha256sum "$S/boot/vmlinuz-$KREL" >> "$L"
echo "BUILD_DONE $S" >> "$L"
