#!/usr/bin/env bash
# Build the GPU test programs into $OUT. Needs gcc and the headers that the
# native Mesa installs under $MESA_PREFIX/include. No sudo.
set -euo pipefail
. "$(dirname "$0")/../config.sh"
T="$(dirname "$0")"
mkdir -p "$OUT"
for t in gles-readback gles-stress; do
	gcc -O2 -Wall -I"$MESA_PREFIX/include" "$T/$t.c" \
		/usr/lib64/libEGL.so.1 /usr/lib64/libGLESv2.so.2 -o "$OUT/$t"
	echo "built $OUT/$t"
done
# Quick check on the CPU renderer (works on any boot, no GPU needed).
LIBGL_ALWAYS_SOFTWARE=1 "$OUT/gles-stress" 2 | tail -1
