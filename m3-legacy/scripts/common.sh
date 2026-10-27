# Shared settings for the M3 GPU build. Sourced by the other scripts.
set -euo pipefail

ROOT="$HOME/m3gpu"
SRC="$ROOT/src"
OUT="$ROOT/out"
LOGS="$ROOT/logs"

# Pinned SiliconForest set for J516S / OS firmware 14.7 (catalog v2026.10.19.2).
KERNEL_REPO="https://github.com/iconidentify/siliconforest-linux.git"
KERNEL_COMMIT="0e1f466613761fecbe71ba8ca25f8b3598577062"
M1N1_REPO="https://github.com/iconidentify/siliconforest-m1n1.git"
M1N1_COMMIT="aca1258c2d7daad7db7079d4f89bb8217659f7ac"
MESA_REPO="https://github.com/iconidentify/siliconforest-mesa.git"
MESA_COMMIT="7515336b3dfbe8943b555ffec9817b9ed64379a8"

LOCALVERSION="-m3gpu"
MESA_PREFIX="/opt/mesa-m3"
JOBS="${JOBS:-$(nproc)}"

mkdir -p "$SRC" "$OUT" "$LOGS"

# Run long builds detached from SSH so a dropped connection does not kill them:
#   systemd-run --user --unit=m3-kernel ~/m3gpu/scripts/build-kernel.sh
# and keep the machine awake while they run:
#   systemd-inhibit --what=sleep:idle --why=m3gpu-build <command>

# Fetch exactly one commit, without history, into $1.
fetch_pinned() {
	local dir="$1" repo="$2" commit="$3"
	if [ ! -d "$dir/.git" ]; then
		git init -q "$dir"
		git -C "$dir" config core.hooksPath /dev/null
		git -C "$dir" remote add origin "$repo"
	fi
	if [ "$(git -C "$dir" rev-parse -q --verify HEAD 2>/dev/null)" != "$commit" ]; then
		git -C "$dir" fetch -q --depth 1 origin "$commit"
		git -C "$dir" checkout -q --detach "$commit"
	fi
	echo "$(basename "$dir"): $(git -C "$dir" rev-parse HEAD)"
}
