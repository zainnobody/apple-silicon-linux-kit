#!/usr/bin/env bash
# Configure and build the kernel with the safe settings from m3-gpu-stack-review.md.
# Builds only. Installs nothing. No sudo.
. "$(dirname "$0")/common.sh"

K="$SRC/linux"
BUILD="$ROOT/build-linux"
mkdir -p "$BUILD"

# Start from the running Fedora Asahi kernel's config.
cp "/boot/config-$(uname -r)" "$BUILD/.config"

cfg() { "$K/scripts/config" --file "$BUILD/.config" "$@"; }
cfg --set-str LOCALVERSION "$LOCALVERSION"
cfg --enable EXPERT
cfg --enable SILICONFOREST_NATIVE_GPU
cfg --disable SILICONFOREST_M3
# Built in, as in the SiliconForest config: the Rust gpuvm binding needs DRM_GPUVM=y.
cfg --enable DRM_ASAHI
cfg --enable APPLE_PMP             # DRM_ASAHI_G15 needs APPLE_PMP=y when DRM_ASAHI=y
cfg --enable DRM_ASAHI_G15
# Livepatch fails a KSYM_NAME_LEN build check in this tree; not needed.
cfg --disable LIVEPATCH
cfg --disable APPLE_SEP
cfg --disable ARM64_USER4K_EXPERIMENTAL
cfg --disable KUNIT
cfg --disable DEBUG_INFO_BTF       # pahole/BTF often breaks Rust builds; not needed here
cfg --set-str SYSTEM_TRUSTED_KEYS ""
cfg --set-str SYSTEM_REVOCATION_KEYS ""
cfg --disable MODULE_SIG_ALL       # Fedora's signing key is not available here

make -C "$K" O="$BUILD" olddefconfig

# Fail if the safe settings did not stick (Kconfig can silently re-enable options).
check() {
	local want="$1"
	if ! grep -qx "$want" "$BUILD/.config"; then
		echo "CONFIG CHECK FAILED: wanted '$want', got: $(grep -E "${want%%=*}[= ]" "$BUILD/.config" || echo absent)" >&2
		exit 1
	fi
}
check "CONFIG_SILICONFOREST_NATIVE_GPU=y"
# Must not be on. "Not set" and "absent" (dependency not met) are both off.
check_off() {
	if grep -qE "^CONFIG_$1=(y|m)$" "$BUILD/.config"; then
		echo "CONFIG CHECK FAILED: CONFIG_$1 is on" >&2
		exit 1
	fi
	echo "ok: CONFIG_$1 off"
}
check_off SILICONFOREST_M3
check_off APPLE_SEP
check_off ARM64_USER4K_EXPERIMENTAL
check_off KUNIT
check "CONFIG_DRM_ASAHI_G15=y"
check "CONFIG_DRM_ASAHI=y"
check "CONFIG_DRM_GPUVM=y"
check_off LIVEPATCH
check "CONFIG_APPLE_PMP=y"
make -C "$K" O="$BUILD" rustavailable
[ "${CONFIG_ONLY:-0}" = 1 ] && { echo "CONFIG_ONLY: all checks passed"; exit 0; }

make -C "$K" O="$BUILD" -k -j"$JOBS" Image modules dtbs 2>&1 | tee "$LOGS/kernel-build.log" | tail -20

KREL="$(make -s -C "$K" O="$BUILD" kernelrelease)"
STAGE="$OUT/kernel-$KREL"
rm -rf "$STAGE"
mkdir -p "$STAGE/boot" "$STAGE/dtb"
cp "$BUILD/arch/arm64/boot/Image" "$STAGE/boot/vmlinuz-$KREL"
cp "$BUILD/.config" "$STAGE/boot/config-$KREL"
cp "$BUILD/System.map" "$STAGE/boot/System.map-$KREL"
make -C "$K" O="$BUILD" INSTALL_MOD_PATH="$STAGE" INSTALL_MOD_STRIP=1 modules_install >/dev/null
make -C "$K" O="$BUILD" INSTALL_DTBS_PATH="$STAGE/dtb" dtbs_install >/dev/null
echo "$KREL" > "$OUT/kernel-release"
echo "Kernel staged in $STAGE"
ls -la "$STAGE/boot"
find "$STAGE/dtb" -name '*j516s*'
