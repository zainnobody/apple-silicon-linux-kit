#!/usr/bin/env bash
# Build the Apple video decoder (AVD) firmware from AsahiLinux/avd-fw and print the install command.
# Builds only. Installs nothing. No sudo.
# The kernel asks for apple/avd-fw-v4-t0.bin on the M3 Pro (apple,t6030-avd, avd-drv.c).
# Needs clang, lld, llvm-objcopy, meson and ninja (all in Fedora Asahi Remix).
. "$(dirname "$0")/common.sh"

AVD_FW_REPO="${AVD_FW_REPO:-https://github.com/AsahiLinux/avd-fw.git}"
AVD_FW_COMMIT="${AVD_FW_COMMIT:-220b1e70c9d7dcccbf66d5194e372300aa3c5a32}"   # tested; release 0.1 has no tag
AVD_FW_VARIANT="${AVD_FW_VARIANT:-avd-fw-v4-t0}"
D="$AGX_ROOT/avd-fw"

fetch_pinned "$D" "$AVD_FW_REPO" "$AVD_FW_COMMIT"
rm -rf "$D/build"
(cd "$D" && meson setup build --cross-file=./llvm.ini --prefix=/usr && ninja -C build)

BIN="$D/build/apple/$AVD_FW_VARIANT.bin"
[ -f "$BIN" ] || { echo "Missing $BIN" >&2; exit 1; }
sha256sum "$BIN"
echo "Install (needs root, no module reload):"
echo "  sudo install -D -m 0644 $BIN /lib/firmware/apple/$AVD_FW_VARIANT.bin && sudo restorecon -v /lib/firmware/apple/$AVD_FW_VARIANT.bin"
echo "Then reload apple_avd only with the user's go: sudo modprobe -r apple_avd && sudo modprobe apple_avd"
