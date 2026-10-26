# shellcheck shell=bash
# m3-linux settings. Every build and install script sources this file.
# Edit the values in the first block for your machine. Defaults are for the
# machine this was developed on: MacBook Pro 16-inch M3 Pro (Mac15,7, J516s),
# Fedora Asahi Remix 44, OS firmware 14.7.

# ---- Machine ----------------------------------------------------------------
# Device tree compatible of the machine (cat /proc/device-tree/compatible).
M3_MACHINE="${M3_MACHINE:-apple,j516s}"
# Board DTB that m1n1 uses for this machine (in <dtb-dir>/apple/).
M3_DTB_NAME="${M3_DTB_NAME:-t6030-j516s.dtb}"
# GPU device node name in sysfs (ls /sys/bus/platform/devices | grep gpu).
M3_GPU_NODE="${M3_GPU_NODE:-292400000.gpu}"
# Login screen account (plasmalogin on Fedora KDE 44; sddm on older releases).
M3_GREETER_USER="${M3_GREETER_USER:-plasmalogin}"

# ---- User and folders -------------------------------------------------------
# The normal (non-root) user who builds. Under sudo this is the calling user.
M3_USER="${M3_USER:-${SUDO_USER:-${USER:-$(id -un)}}}"
M3_HOME="${M3_HOME:-$(getent passwd "$M3_USER" | cut -d: -f6)}"
# Work folder for sources, builds, staged output and logs (outside the repo).
M3_ROOT="${M3_ROOT:-$M3_HOME/m3gpu}"
SRC="$M3_ROOT/src"
OUT="$M3_ROOT/out"
LOGS="$M3_ROOT/logs"

# ---- Pinned sources (SiliconForest set for J516S / OS firmware 14.7) --------
KERNEL_REPO="https://github.com/iconidentify/siliconforest-linux.git"
KERNEL_COMMIT="0e1f466613761fecbe71ba8ca25f8b3598577062"
M1N1_REPO="https://github.com/iconidentify/siliconforest-m1n1.git"
M1N1_COMMIT="aca1258c2d7daad7db7079d4f89bb8217659f7ac"
MESA_REPO="https://github.com/iconidentify/siliconforest-mesa.git"
MESA_COMMIT="7515336b3dfbe8943b555ffec9817b9ed64379a8"

# ---- Build and install ------------------------------------------------------
LOCALVERSION="${LOCALVERSION:--m3gpu}"
MESA_PREFIX="${MESA_PREFIX:-/opt/mesa-m3}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
# Kernel release of the test kernel, written by build/build-kernel.sh.
M3_KREL="${M3_KREL:-$(cat "$OUT/kernel-release" 2>/dev/null || true)}"
M1N1_BIN="$OUT/m1n1/m1n1-$M1N1_COMMIT.bin"
ESP_M1N1="${ESP_M1N1:-/boot/efi/m1n1}"
UBOOT="${UBOOT:-/usr/share/uboot/apple_m1/u-boot-nodtb.bin}"
# m1n1 options that turn on the native GPU and display (stage E).
M3_GPU_OPTIONS="${M3_GPU_OPTIONS:-chosen.asahi,t6030-gpu=1 chosen.asahi,t6030-dcp=1 chosen.asahi,t6030-dcpext=1}"
