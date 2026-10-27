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
# Vulkan compute check (needs glslc and the Vulkan headers).
if command -v glslc >/dev/null; then
	glslc "$T/vk-compute.comp" -o "$OUT/vk-compute.spv"
	gcc -O2 -Wall "$T/vk-compute.c" -lvulkan -o "$OUT/vk-compute"
	glslc "$T/vk-bandwidth.comp" -o "$OUT/vk-bandwidth.spv"
	gcc -O2 -Wall "$T/vk-bandwidth.c" -lvulkan -o "$OUT/vk-bandwidth"
	echo "built $OUT/vk-compute and $OUT/vk-bandwidth (run them from $OUT)"
fi
gcc -O3 -march=native -fopenmp "$T/cpu-bw.c" -o "$OUT/cpu-bw" && echo "built $OUT/cpu-bw"
