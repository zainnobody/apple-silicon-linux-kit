# shellcheck shell=bash
# Machine profile: MacBook Pro 16-inch, M3 Pro (Mac15,7, J516s, SoC T6030, GPU G15S).
# Status: tested 2026-10-26 on chip revision B1, Fedora Asahi Remix 44,
# OS firmware 14.7, with patches/g15-j516s-b1-pin.patch.
# Device tree compatible of the machine (cat /proc/device-tree/compatible).
AGX_MACHINE="${AGX_MACHINE:-apple,j516s}"
# Board DTB that m1n1 uses for this machine (in <dtb-dir>/apple/).
AGX_DTB_NAME="${AGX_DTB_NAME:-t6030-j516s.dtb}"
# GPU device name in sysfs (ls /sys/bus/platform/devices | grep gpu).
AGX_GPU_NODE="${AGX_GPU_NODE:-292400000.gpu}"
# m1n1 options that turn on the native GPU and display (stage E).
AGX_M1N1_OPTIONS="${AGX_M1N1_OPTIONS:-chosen.asahi,t6030-gpu=1 chosen.asahi,t6030-dcp=1 chosen.asahi,t6030-dcpext=1}"
# Kernel driver that binds the native GPU (asahi-g15 for the M3 generation, G15).
AGX_GPU_DRIVER="${AGX_GPU_DRIVER:-asahi-g15}"
