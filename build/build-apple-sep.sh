#!/usr/bin/env bash
# Build the Touch ID module (apple-sep.ko, module name apple_sep) out of tree.
# It copies drivers/soc/apple from the pinned kernel tree to a scratch folder, applies patches/touchid/ there in
# order, and builds the module against the kernel build folder from build/build-kernel.sh.
# The kernel tree and the build folder stay unchanged. No sudo. Installs nothing.
#
# Needs: build/fetch-sources.sh and build/build-kernel.sh have run (Module.symvers exists in the build folder).
# Output: $OUT/touchid/apple-sep.ko and apple-sep.ko.sha256. The hash of your build differs from the author's
# build, so give it to the installer (tools/touchid/integration/ti-install.sh) as TI_MODULE and TI_MODULE_SHA.
#
# Options (environment):
#   WITH_ENTROPY_TRACE=1   also apply sep-entropy-trace.patch (diagnostic option entropy_trace=1; off by default)
#   PATCH_ONLY=1           copy and patch only; do not build (checks that the patches apply)
#   SEP_JOBS=2             build jobs (default 2, the module is small)
. "$(dirname "$0")/common.sh"

K="$SRC/linux"
BUILD="$AGX_ROOT/build-linux"
W="$AGX_ROOT/apple-sep-build"
A="$W/drivers/soc/apple"
DEST="$OUT/touchid"
PATCHDIR="$REPO_DIR/patches/touchid"

# Order matters: each patch is made against the result of the ones before it.
# Stage 3f is the set that the installer pins. sep-entropy-trace.patch (stage 3g) is a trace option on top.
PATCHES=(t6030-profile t6030-sepos13 sensor-probe guard-loaded-only sensor-poll-trace sensor-rearm sensor-rearm-settle)
[ "${WITH_ENTROPY_TRACE:-0}" = 1 ] && PATCHES+=(sep-entropy-trace)

[ -d "$K/drivers/soc/apple" ] || { echo "No kernel tree at $K: run build/fetch-sources.sh" >&2; exit 1; }
if [ "${PATCH_ONLY:-0}" != 1 ]; then
	[ -f "$BUILD/Module.symvers" ] || { echo "No kernel build at $BUILD: run build/build-kernel.sh first" >&2; exit 1; }
fi

# Scratch copy of the driver folder: the plain files only (not the m3/ folder).
rm -rf "$W"
mkdir -p "$A"
find "$K/drivers/soc/apple" -maxdepth 1 -type f -exec cp {} "$A/" \;

for p in "${PATCHES[@]}"; do
	patch -p1 -d "$W" --dry-run -s < "$PATCHDIR/$p.patch" >/dev/null \
		|| { echo "Patch $p.patch does not apply to $KERNEL_COMMIT" >&2; exit 1; }
	patch -p1 -d "$W" -s < "$PATCHDIR/$p.patch"
	echo "applied $p.patch"
done
[ "${PATCH_ONLY:-0}" = 1 ] && { echo "PATCH_ONLY: all patches apply; scratch tree in $W"; exit 0; }

# Kbuild file: the object list of apple-sep from the tree's Makefile, plus fv_shim.o. The tree builds fv_shim.o into
# the kernel only when CONFIG_APPLE_SEP is on, and build-kernel.sh turns that off.
objs="$(awk '/^apple-sep-y/{p=1} p{print} p&&!/\\$/{exit}' "$A/Makefile" | sed 's/^apple-sep-y *:*= *//; s/\\$//' | tr -s ' \t\n' ' ')"
[ -n "${objs// /}" ] || { echo "No apple-sep-y list in $A/Makefile" >&2; exit 1; }
rm -f "$A/Makefile"
{
	echo "# SPDX-License-Identifier: GPL-2.0-only"
	echo "obj-m += apple-sep.o"
	echo "apple-sep-y := $objs fv_shim.o"
} > "$A/Kbuild"

nice -n 19 make -C "$K" O="$BUILD" M="$A" -j"${SEP_JOBS:-2}" modules 2>&1 | tee "$LOGS/apple-sep-build.log" | tail -20
[ -f "$A/apple-sep.ko" ] || { echo "Build failed: see $LOGS/apple-sep-build.log" >&2; exit 1; }

KREL="$(make -s -C "$K" O="$BUILD" kernelrelease)"
vermagic="$(modinfo -F vermagic "$A/apple-sep.ko")"
case "$vermagic" in
	"$KREL "*) ;;
	*) echo "Vermagic '$vermagic' does not match kernel release $KREL" >&2; exit 1 ;;
esac

mkdir -p "$DEST"
cp "$A/apple-sep.ko" "$DEST/apple-sep.ko"
(cd "$DEST" && sha256sum apple-sep.ko > apple-sep.ko.sha256)
echo "Module: $DEST/apple-sep.ko (vermagic $vermagic)"
echo "Give it to the installer with:"
echo "  export TI_MODULE=$DEST/apple-sep.ko TI_MODULE_SHA=$(cut -d' ' -f1 "$DEST/apple-sep.ko.sha256")"
