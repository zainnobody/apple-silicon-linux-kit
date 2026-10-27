#!/usr/bin/env bash
# AirDrop on the M3 (J516S, 7.2.11-m3gpu+) with the built-in Broadcom BCM4388, Fedora Asahi Remix.
# Uses omdrop-awdl (userspace radio helpers) and omdrop-plugin (receiver). Runs on the M3.
# Each step is its own subcommand. Nothing runs without a subcommand. See docs/features/airdrop.md.
#   fetch     download both projects at the pinned commits into $SRC (no root)
#   deps      install three Python modules with dnf (root)
#   mac       set the Wi-Fi profile to the permanent MAC; awdl-up refuses a random MAC (root)
#   up        create awdl0 once; does not open a visible window (root)
#   firewall  put awdl0 in the "work" zone and open TCP 8771; runtime only (root)
#   receiver  start the receiver in a retry loop (no root)
#   window N  become visible for N seconds (root; needs a terminal if sudo asks for a password)
#   send ADDR FILE  send a file to a peer on awdl0 (user; needs an open window). ADDR is the peer link-local
#             address with port, e.g. "[fe80::...%awdl0]:8770"; list peers with: ip -6 neigh show dev awdl0
#   notify    desktop notification after each received file; follows the receiver log (no root)
#   status    read-only
#   undo      remove awdl0, the NetworkManager file, the firewall change; restore the MAC setting (root)
set -u
SRC=${AIRDROP_SRC:-$HOME/omdrop-test}
OUT=${AIRDROP_OUT:-$HOME/Downloads}
AWDL_REV=9c846cd598e234cf874019a868a777e85dce05fe
PLUGIN_REV=48867c6d5bb6ee08eb6b7e6e4e20a8210d65fdee
UP=$SRC/omdrop-awdl/userspace/awdl-up
DISC=$SRC/omdrop-awdl/userspace/omdrop-discoverable
NMFILE=/etc/NetworkManager/conf.d/99-awdl-unmanaged.conf
ok()  { echo "ok:   $*"; }
bad() { echo "FAIL: $*"; exit 1; }

# The Wi-Fi connection profile on the brcmfmac interface, found rather than assumed.
wifi_profile() {
	local dev
	dev=$(nmcli -t -f DEVICE,TYPE dev | awk -F: '$2=="wifi" && $1!~/^p2p-dev/ {print $1; exit}')
	nmcli -t -f NAME,DEVICE con show --active | awk -F: -v d="$dev" '$2==d {print $1; exit}'
}

case "${1:-}" in
fetch)
	mkdir -p "$SRC" || bad "cannot create $SRC"
	for p in "omdrop-awdl netmojo-systems $AWDL_REV" "omdrop-plugin netmojo-systems $PLUGIN_REV"; do
		set -- $p
		[ -d "$SRC/$1/.git" ] || git clone --quiet "https://github.com/$2/$1.git" "$SRC/$1" || bad "clone $1"
		git -C "$SRC/$1" fetch --quiet origin "$3" && git -C "$SRC/$1" checkout --quiet "$3" || bad "checkout $1 $3"
		ok "$1 at $3"
	done
	# The receiver refuses to start without the Apple root certificate. Check the fingerprint.
	fp=$(openssl x509 -in "$SRC/omdrop-plugin/share/certs/apple_root_ca.pem" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d :)
	[ "$fp" = B0B1730ECBC7FF4505142C49F1295E6EDA6BCAED7E2C68C5BE91B5A11001F024 ] && ok "Apple Root CA fingerprint" || bad "certificate fingerprint differs"
	;;
deps)
	sudo dnf install -y python3-ifaddr python3-libarchive-c python3-zeroconf || bad "dnf"
	;;
mac)
	p=$(wifi_profile); [ -n "$p" ] || bad "no active Wi-Fi profile"
	sudo nmcli connection modify "$p" wifi.cloned-mac-address permanent && sudo nmcli connection up "$p" || bad "nmcli"
	ok "profile set to the permanent MAC (Wi-Fi reconnects once; SSH over Wi-Fi drops for a few seconds)"
	;;
up)
	sudo "$UP" && ok "awdl0 created" || bad "awdl-up failed (exit 5 = random MAC: run 'mac' first)"
	;;
firewall)
	sudo firewall-cmd --zone=work --change-interface=awdl0 && sudo firewall-cmd --zone=work --add-port=8771/tcp || bad "firewall-cmd"
	ok "awdl0 in zone work, TCP 8771 open (runtime only)"
	;;
receiver)
	mkdir -p "$OUT"
	cd "$SRC/omdrop-plugin/bin" || bad "run fetch first"
	# awdl0 has no link-local address until a window is open, so the receiver exits until then.
	for _ in $(seq 1 90); do
		python3 airdrop-serve.py --outdir "$OUT" --name "${AIRDROP_NAME:-M3 Pro}" >> "$SRC/receiver.log" 2>&1
		sleep 3
	done
	;;
window)
	sudo "$DISC" start "${2:-180}"
	;;
send)
	[ -n "${2:-}" ] && [ -f "${3:-}" ] || bad "usage: send ADDR FILE"
	python3 "$SRC/omdrop-awdl/userspace/airdrop-send.py" --direct "$2" --ask-timeout 45 --op-timeout 10 "$3"
	;;
notify)
	DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus; export DBUS_SESSION_BUS_ADDRESS
	tail -n0 -F "$SRC/receiver.log" | while read -r line; do
		case "$line" in
		*'POST /Upload HTTP/1.1" 200'*)
			sleep 1
			notify-send -a AirDrop "AirDrop: file received" "$(ls -t "$OUT" | head -1) saved in $OUT"
			;;
		esac
	done
	;;
status)
	ip -br link show awdl0 2>&1
	"$DISC" status --json 2>&1
	sudo -n firewall-cmd --zone=work --list-ports 2>&1
	ls -la "$OUT" 2>&1
	;;
undo)
	sudo "$DISC" stop
	sudo ip link del awdl0
	sudo rm -f "$NMFILE" && sudo nmcli general reload conf
	sudo firewall-cmd --zone=work --remove-port=8771/tcp
	sudo firewall-cmd --zone=work --remove-interface=awdl0
	p=$(wifi_profile)
	[ -n "$p" ] && sudo nmcli connection modify "$p" wifi.cloned-mac-address stable-ssid && sudo nmcli connection up "$p"
	ok "undone; the three Python packages stay installed (sudo dnf remove python3-ifaddr python3-libarchive-c python3-zeroconf)"
	;;
*)
	sed -n '2,16p' "$0"
	;;
esac
