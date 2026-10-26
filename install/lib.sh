# shellcheck shell=bash
# Shared helpers for the install stages. Sourced; the stages run with sudo.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$REPO_DIR/config.sh"

need_root() { [ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }; }

need_machine() {
	tr '\0' '\n' < /proc/device-tree/compatible | grep -qx "$AGX_MACHINE" \
		|| { echo "This is not $AGX_MACHINE (see config.sh)" >&2; exit 1; }
}

need_krel() {
	[ -n "$AGX_KREL" ] || { echo "No kernel release; run build/build-kernel.sh first" >&2; exit 1; }
}

sha() { sha256sum "$1" | cut -d' ' -f1; }

# Fill a template from system/ with this machine's values. Values are fixed at
# install time, so the root-owned copies never read a user-writable file.
render() { # <template> <output>
	local dtb="/boot/dtb-$AGX_KREL/apple/$AGX_DTB_NAME"
	local dtb_sha="" m1n1_sha="" greeter_uid=""
	[ -f "$dtb" ] && dtb_sha="$(sha "$dtb")"
	[ -f "$M1N1_BIN" ] && m1n1_sha="$(sha "$M1N1_BIN")"
	greeter_uid="$(id -u "$AGX_GREETER_USER" 2>/dev/null || true)"
	sed -e "s|@AGX_USER@|$AGX_USER|g" \
	    -e "s|@AGX_KREL@|$AGX_KREL|g" \
	    -e "s|@AGX_DTB_NAME@|$AGX_DTB_NAME|g" \
	    -e "s|@DTB_SHA@|$dtb_sha|g" \
	    -e "s|@M1N1_SHA@|$m1n1_sha|g" \
	    -e "s|@AGX_GPU_NODE@|$AGX_GPU_NODE|g" \
	    -e "s|@MESA_PREFIX@|$MESA_PREFIX|g" \
	    -e "s|@ESP_M1N1@|$ESP_M1N1|g" \
	    -e "s|@UBOOT@|$UBOOT|g" \
	    -e "s|@AGX_M1N1_OPTIONS@|$AGX_M1N1_OPTIONS|g" \
	    -e "s|@GREETER_UID@|$greeter_uid|g" \
	    -e "s|@AGX_GREETER_USER@|$AGX_GREETER_USER|g" \
	    -e "s|@AGX_GPU_DRIVER@|$AGX_GPU_DRIVER|g" \
	    -e "s|@LOCALVERSION@|$LOCALVERSION|g" \
	    "$1" > "$2"
	if grep -q '@[A-Z0-9_]*@' "$2"; then
		echo "Unfilled value in $2: $(grep -o '@[A-Z0-9_]*@' "$2" | sort -u | tr '\n' ' ')" >&2
		exit 1
	fi
}

# Remove the root-owned files of the first test install, which used m3gpu
# names. The new agx-* files replace them. An old off switch carries over.
migrate_legacy() {
	local found=no f
	if [ -e /etc/systemd/system/m3gpu-mesa-select.service ]; then
		systemctl disable --now m3gpu-mesa-select.service || true
		rm -f /etc/systemd/system/m3gpu-mesa-select.service
		systemctl daemon-reload
		found=yes
	fi
	for f in /etc/sudoers.d/m3gpu /usr/local/sbin/m3gpu-boot /usr/local/sbin/m3gpu-mesa-select \
		/etc/systemd/user-environment-generators/60-m3gpu-native-mesa \
		/etc/ld.so.conf.d/00-m3gpu-native-mesa.conf /etc/profile.d/m3gpu-native-mesa.sh \
		"$AGX_HOME/.config/plasma-workspace/env/m3gpu-native-mesa.sh"; do
		[ -e "$f" ] && { rm -f "$f"; found=yes; }
	done
	[ -d /usr/local/lib/m3gpu ] && { rm -rf /usr/local/lib/m3gpu; found=yes; }
	[ -e /etc/m3gpu-native-mesa.off ] && mv -f /etc/m3gpu-native-mesa.off /etc/agx-native-mesa.off
	if [ "$found" = yes ]; then
		ldconfig
		echo "Removed the old m3gpu files (replaced by agx-*)."
	fi
}
