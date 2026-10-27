#!/usr/bin/env bash
# Build LibrePods (AirPods features for Linux) as a user app on the M3. Needs sudo for the dnf step
# (the user types the password). Installs no binary and no service: the app runs from the build folder.
# Source: https://github.com/kavishdevar/librepods, pinned commit 89356c0 (GPL v3). Reviewed with
# SkillSpector (no HIGH findings) and by reading the Linux source (no network code).
set -euo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${LIBREPODS_SRC:-$HOME/librepods-build}"
PIN=89356c0

sudo dnf -y install \
	qt6-qtbase-devel qt6-qtconnectivity-devel qt6-qtmultimedia-devel qt6-qtdeclarative-devel \
	qt6-qttools-devel pulseaudio-libs-devel openssl-devel cmake gcc-c++

[ -d "$SRC/.git" ] || git clone https://github.com/kavishdevar/librepods.git "$SRC"
cd "$SRC"
git checkout -q "$PIN"
# Local fixes, in this order. The codec patch is verified on the M3. The resume patch is not yet.
for p in librepods-m3-aac-codec.patch librepods-m3-resume-playback.patch; do
	if git apply --check "$KIT/patches/$p" 2>/dev/null; then
		git apply "$KIT/patches/$p"
	else
		echo "skipped $p"
	fi
done
cd linux
cmake -B build -DCMAKE_BUILD_TYPE=Release
nice make -C build -j4
echo "BUILD_DONE. Run it inside the desktop session:"
echo "  QT_QPA_PLATFORM=wayland $SRC/linux/build/librepods --hide"
echo "Logs go to the user journal: journalctl --user -t librepods"
