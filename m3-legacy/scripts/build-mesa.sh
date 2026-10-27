#!/usr/bin/env bash
# Build Mesa for the M3 GPU into a staging folder. Copying to /opt/mesa-m3 is a
# separate sudo step. Fedora's own Mesa is not touched.
. "$(dirname "$0")/common.sh"

S="$SRC/mesa"
B="$ROOT/build-mesa"
STAGE="$OUT/mesa-stage"

if [ ! -f "$B/build.ninja" ]; then
	meson setup "$B" "$S" \
		--prefix="$MESA_PREFIX" --libdir=lib64 --buildtype=release \
		-Dgallium-drivers=asahi,zink,softpipe -Dvulkan-drivers=asahi \
		-Dplatforms=x11,wayland -Dglx=dri -Degl=enabled -Dgbm=enabled \
		-Dglvnd=disabled -Dllvm=enabled -Dmesa-clc=enabled \
		-Dprecomp-compiler=enabled -Dvideo-codecs= -Dgallium-va=disabled \
		-Dbuild-tests=false -Dtools=asahi
fi
ninja -C "$B" -j"$JOBS" 2>&1 | tee "$LOGS/mesa-build.log" | tail -15

rm -rf "$STAGE"
DESTDIR="$STAGE" ninja -C "$B" install >/dev/null
echo "Mesa staged in $STAGE$MESA_PREFIX"
ls "$STAGE$MESA_PREFIX/lib64/dri" "$STAGE$MESA_PREFIX/share/vulkan/icd.d" 2>&1
