#!/usr/bin/env bash
# Build m1n1 stage 2 (m1n1.bin) from the pinned commit. Installs nothing. No sudo.
. "$(dirname "$0")/common.sh"

M="$SRC/m1n1"
make -C "$M" clean >/dev/null 2>&1 || true
# Clang, as in the fork's CI. GCC links fail on __popcountdi2 (kboot_gpu_t8122_power.c).
make -C "$M" -j"$JOBS" RELEASE=1 USE_CLANG=1 ARCH=aarch64-linux-gnu 2>&1 | tee "$LOGS/m1n1-build.log" | tail -15

mkdir -p "$OUT/m1n1"
cp "$M/build/m1n1.bin" "$M1N1_BIN"
sha256sum "$M1N1_BIN"
