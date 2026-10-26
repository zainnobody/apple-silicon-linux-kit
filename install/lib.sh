# shellcheck shell=bash
# Shared helpers for the install stages. Sourced; the stages run with sudo.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$REPO_DIR/config.sh"

need_root() { [ "$(id -u)" = 0 ] || { echo "Run with sudo" >&2; exit 1; }; }

need_machine() {
	tr '\0' '\n' < /proc/device-tree/compatible | grep -qx "$M3_MACHINE" \
		|| { echo "This is not $M3_MACHINE (see config.sh)" >&2; exit 1; }
}

need_krel() {
	[ -n "$M3_KREL" ] || { echo "No kernel release; run build/build-kernel.sh first" >&2; exit 1; }
}

sha() { sha256sum "$1" | cut -d' ' -f1; }

# Fill a template from system/ with this machine's values. Values are fixed at
# install time, so the root-owned copies never read a user-writable file.
render() { # <template> <output>
	local dtb="/boot/dtb-$M3_KREL/apple/$M3_DTB_NAME"
	local dtb_sha="" m1n1_sha="" greeter_uid=""
	[ -f "$dtb" ] && dtb_sha="$(sha "$dtb")"
	[ -f "$M1N1_BIN" ] && m1n1_sha="$(sha "$M1N1_BIN")"
	greeter_uid="$(id -u "$M3_GREETER_USER" 2>/dev/null || true)"
	sed -e "s|@M3_USER@|$M3_USER|g" \
	    -e "s|@M3_KREL@|$M3_KREL|g" \
	    -e "s|@M3_DTB_NAME@|$M3_DTB_NAME|g" \
	    -e "s|@DTB_SHA@|$dtb_sha|g" \
	    -e "s|@M1N1_SHA@|$m1n1_sha|g" \
	    -e "s|@M3_GPU_NODE@|$M3_GPU_NODE|g" \
	    -e "s|@MESA_PREFIX@|$MESA_PREFIX|g" \
	    -e "s|@ESP_M1N1@|$ESP_M1N1|g" \
	    -e "s|@UBOOT@|$UBOOT|g" \
	    -e "s|@M3_GPU_OPTIONS@|$M3_GPU_OPTIONS|g" \
	    -e "s|@GREETER_UID@|$greeter_uid|g" \
	    -e "s|@M3_GREETER_USER@|$M3_GREETER_USER|g" \
	    "$1" > "$2"
	if grep -q '@[A-Z0-9_]*@' "$2"; then
		echo "Unfilled value in $2: $(grep -o '@[A-Z0-9_]*@' "$2" | sort -u | tr '\n' ' ')" >&2
		exit 1
	fi
}
