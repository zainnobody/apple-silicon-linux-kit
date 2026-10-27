#!/usr/bin/env bash
# Shared memory limit test, no root and no register access. Measures CPU and GPU read bandwidth
# alone and at the same time, and the CPU on each cluster type. If CPU + GPU together stay near the
# single result, one limit is shared below both (memory controller or fabric).
# Usage: tests/mem-shared.sh <dir with cpu-bw, vk-bandwidth, vk-bandwidth.spv>
set -euo pipefail
D="${1:-$HOME/vktest}"
cd "$D"
if [ -z "${VK_DRIVER_FILES:-}" ]; then
	for p in /opt/mesa-agx /opt/mesa-m3; do
		[ -f "$p/share/vulkan/icd.d/asahi_icd.aarch64.json" ] && { export VK_DRIVER_FILES="$p/share/vulkan/icd.d/asahi_icd.aarch64.json"; break; }
	done
fi

# CPU numbering: the cpufreq policy with the lower maximum is the E cluster.
clusters=$(for pol in /sys/devices/system/cpu/cpufreq/policy*; do
	echo "$(cat "$pol/cpuinfo_max_freq") $(tr ' ' ',' < "$pol/related_cpus" | sed 's/,$//')"
done | sort -n)
e_cpus=$(echo "$clusters" | head -1 | cut -d' ' -f2)
p_cpus=$(echo "$clusters" | tail -1 | cut -d' ' -f2)
echo "kernel $(uname -r); P cores $p_cpus; E cores $e_cpus"
grep -H . /sys/devices/system/cpu/cpufreq/policy*/scaling_cur_freq

echo "== alone"
echo "CPU, P cores:   $(OMP_NUM_THREADS=6 taskset -c "$p_cpus" ./cpu-bw 8 | cut -d: -f2-)"
echo "CPU, E cores:   $(OMP_NUM_THREADS=6 taskset -c "$e_cpus" ./cpu-bw 8 | cut -d: -f2-)"
echo "CPU, all:       $(OMP_NUM_THREADS=12 ./cpu-bw 8 | cut -d: -f2-)"
echo "GPU:            $(./vk-bandwidth 512 60 16 | grep GB/s | cut -d: -f2-)"

echo "== CPU (P cores) and GPU at the same time"
OMP_NUM_THREADS=6 taskset -c "$p_cpus" ./cpu-bw 40 > /tmp/mem-shared-cpu.txt &
cpu=$!
sleep 0.3
gpu_out=$(./vk-bandwidth 512 60 16 | grep GB/s | cut -d: -f2-)
wait "$cpu"
echo "CPU, P cores:   $(cut -d: -f2- /tmp/mem-shared-cpu.txt)"
echo "GPU:            $gpu_out"

echo "== CPU on both clusters at the same time"
OMP_NUM_THREADS=6 taskset -c "$p_cpus" ./cpu-bw 20 > /tmp/mem-shared-p.txt &
p=$!
OMP_NUM_THREADS=6 taskset -c "$e_cpus" ./cpu-bw 20 > /tmp/mem-shared-e.txt &
e=$!
wait "$p" "$e"
echo "CPU, P cores:   $(cut -d: -f2- /tmp/mem-shared-p.txt)"
echo "CPU, E cores:   $(cut -d: -f2- /tmp/mem-shared-e.txt)"
echo MEM_SHARED_DONE
