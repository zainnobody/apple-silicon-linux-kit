# shellcheck shell=bash
# agx-linux-kit settings. Every build, install and test script sources this file.
# Order: config.local.sh (your overrides, not in git), then the machine profile
# in machines/<AGX_PROFILE>.sh, then the defaults below. The first value set wins.
_agx_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
[ -f "$_agx_repo/config.local.sh" ] && . "$_agx_repo/config.local.sh"

# ---- Machine profile ----------------------------------------------------------
# One file per machine in machines/. See machines/README.md for the list and
# for how to add a machine.
AGX_PROFILE="${AGX_PROFILE:-j516s}"
[ -f "$_agx_repo/machines/$AGX_PROFILE.sh" ] \
	|| { echo "No machine profile machines/$AGX_PROFILE.sh" >&2; return 1 2>/dev/null || exit 1; }
# shellcheck source=machines/j516s.sh
. "$_agx_repo/machines/$AGX_PROFILE.sh"

# ---- User and folders -------------------------------------------------------
# The normal (non-root) user who builds. Under sudo this is the calling user.
AGX_USER="${AGX_USER:-${SUDO_USER:-${USER:-$(id -un)}}}"
AGX_HOME="${AGX_HOME:-$(getent passwd "$AGX_USER" | cut -d: -f6)}"
# Work folder for sources, builds, staged output and logs (outside the repo).
AGX_ROOT="${AGX_ROOT:-$AGX_HOME/agx-work}"
SRC="$AGX_ROOT/src"
OUT="$AGX_ROOT/out"
LOGS="$AGX_ROOT/logs"

# ---- Pinned sources -----------------------------------------------------------
# The tested SiliconForest set (catalog v2026.10.19.2). A profile can pin others.
KERNEL_REPO="${KERNEL_REPO:-https://github.com/iconidentify/siliconforest-linux.git}"
KERNEL_COMMIT="${KERNEL_COMMIT:-0e1f466613761fecbe71ba8ca25f8b3598577062}"
M1N1_REPO="${M1N1_REPO:-https://github.com/iconidentify/siliconforest-m1n1.git}"
M1N1_COMMIT="${M1N1_COMMIT:-aca1258c2d7daad7db7079d4f89bb8217659f7ac}"
MESA_REPO="${MESA_REPO:-https://github.com/iconidentify/siliconforest-mesa.git}"
MESA_COMMIT="${MESA_COMMIT:-7515336b3dfbe8943b555ffec9817b9ed64379a8}"

# ---- Build and install ------------------------------------------------------
# Suffix of the test kernel release; GPU-boot checks look for it in uname -r.
LOCALVERSION="${LOCALVERSION:--agx}"
MESA_PREFIX="${MESA_PREFIX:-/opt/mesa-agx}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
# Kernel release of the test kernel, written by build/build-kernel.sh.
AGX_KREL="${AGX_KREL:-$(cat "$OUT/kernel-release" 2>/dev/null || true)}"
M1N1_BIN="$OUT/m1n1/m1n1-$M1N1_COMMIT.bin"
ESP_M1N1="${ESP_M1N1:-/boot/efi/m1n1}"
UBOOT="${UBOOT:-/usr/share/uboot/apple_m1/u-boot-nodtb.bin}"
# Login screen account (plasmalogin on Fedora 44 KDE; sddm on older releases).
AGX_GREETER_USER="${AGX_GREETER_USER:-plasmalogin}"
unset _agx_repo
