#!/usr/bin/env bash
# Build the VA-API layer for the Apple video decoder (AVD) and install it under ~/.local.
# Source: sofus13/libva-v4l2_request (GPL-3.0, megi's driver with AVD work). No root, no system files.
# Needs libva-devel, libdrm-devel, kernel-headers, meson, ninja, gcc (all in Fedora Asahi Remix).
# Use the driver with:
#   export LIBVA_DRIVERS_PATH=$HOME/.local/lib64/dri LIBVA_DRIVER_NAME=v4l2_request
. "$(dirname "$0")/common.sh"

REPO="${LIBVA_V4L2_REPO:-https://github.com/sofus13/libva-v4l2_request.git}"
COMMIT="${LIBVA_V4L2_COMMIT:-f54d8d2c36433b38ba9b8633ac10eec444ac9cf1}"   # master on 2026-10-27, meson version 1.2
D="$AGX_ROOT/libva-v4l2-request"
PREFIX="${LIBVA_V4L2_PREFIX:-$HOME/.local}"

fetch_pinned "$D" "$REPO" "$COMMIT"
rm -rf "$D/build"
(cd "$D" \
	&& nice -n 19 meson setup build --prefix="$PREFIX" -Ddriverdir="$PREFIX/lib64/dri" \
	&& nice -n 19 ninja -j"${JOBS:-4}" -C build \
	&& nice -n 19 ninja -C build install)
ls -l "$PREFIX/lib64/dri/v4l2_request_drv_video.so"
sha256sum "$PREFIX/lib64/dri/v4l2_request_drv_video.so"
