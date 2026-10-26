#!/usr/bin/env bash
# Fetch the three pinned source trees. No sudo. Runs no code from the trees.
. "$(dirname "$0")/common.sh"

fetch_pinned "$SRC/linux" "$KERNEL_REPO" "$KERNEL_COMMIT"
fetch_pinned "$SRC/m1n1" "$M1N1_REPO" "$M1N1_COMMIT"
fetch_pinned "$SRC/mesa" "$MESA_REPO" "$MESA_COMMIT"

# m1n1 uses git submodules (for example its Rust dependencies).
git -C "$SRC/m1n1" submodule update --init --depth 1 --recursive
