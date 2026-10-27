#!/usr/bin/env bash
# Make AirDrop on the M3 survive a reboot. Runs on the M3 after `airdrop-setup.sh fetch` and the first manual test.
#   root    sudo ./airdrop-persist.sh root    root-owned helpers, awdl0 boot service, firewall, polkit policy
#   user    ./airdrop-persist.sh user         user services for the receiver and the notification watcher
#   ui      ./airdrop-persist.sh ui           buttons: AirDrop on/off launchers and a Dolphin "Send via AirDrop" entry (user files only)
#   remove  sudo ./airdrop-persist.sh remove  undo the root part (the user part: systemctl --user disable --now ...)
# Nothing here opens a visible window. A window stays a manual step (polkit lets a local desktop session do it without a password).
set -eu
SRC=${AIRDROP_SRC:-${HOME}/omdrop-test}
OUT=${AIRDROP_OUT:-${HOME}/Downloads}
LIB=/usr/lib/omdrop
ok()  { echo "ok:   $*"; }
bad() { echo "FAIL: $*"; exit 1; }

case "${1:-}" in
root)
	[ "$(id -u)" = 0 ] || bad "run with sudo"
	# SUDO_USER's checkout, not root's home
	[ -n "${SUDO_USER:-}" ] && SRC=$(getent passwd "$SUDO_USER" | cut -d: -f6)/omdrop-test
	U=$SRC/omdrop-awdl
	[ -f "$U/userspace/awdl-up" ] || bad "no sources in $U (run airdrop-setup.sh fetch)"
	# Root helpers must sit at a root-owned path: the polkit policy and the unit name this path.
	install -d -m755 "$LIB"
	for f in "$U"/userspace/*; do [ -f "$f" ] && install -m755 "$f" "$LIB/"; done
	install -m644 "$U/packaging/awdl0.service" /etc/systemd/system/awdl0.service
	install -d -m755 /etc/systemd/system/awdl0.service.d
	# NetworkManager does not manage awdl0, so firewalld is told about the interface each time it appears.
	printf '[Service]\nExecStartPost=-/usr/bin/firewall-cmd --zone=work --change-interface=awdl0\n' > /etc/systemd/system/awdl0.service.d/firewall.conf
	install -m644 "$U/packaging/org.omarchy.omdrop.policy" /usr/share/polkit-1/actions/org.omarchy.omdrop.policy
	restorecon -R "$LIB" /etc/systemd/system/awdl0.service /etc/systemd/system/awdl0.service.d 2>/dev/null || true
	firewall-cmd --permanent --zone=work --add-port=8771/tcp
	firewall-cmd --reload
	# reload drops runtime-only bindings: bind awdl0 again if it exists
	ip link show awdl0 >/dev/null 2>&1 && firewall-cmd --zone=work --change-interface=awdl0
	systemctl daemon-reload
	# awdl0 is NOT created at boot (see docs/features/airdrop.md, Wi-Fi coexistence): while awdl0 exists it holds a station slot
	# in cfg80211 and any other interface add fails with -16. Set AIRDROP_BOOT_AWDL=1 to enable the boot unit anyway.
	if [ "${AIRDROP_BOOT_AWDL:-0}" = 1 ]; then systemctl enable awdl0.service; else systemctl disable awdl0.service 2>/dev/null || true; fi
	ok "root part installed; awdl0 is created on demand by the AirDrop on button"
	;;
user)
	d=$HOME/.config/systemd/user
	mkdir -p "$d" "$OUT"
	install -m755 "$(dirname "$(readlink -f "$0")")/airdrop-notify.sh" "$SRC/notify-receive.sh"
	cat > "$d/airdrop-receiver.service" <<EOF
[Unit]
Description=AirDrop receiver on awdl0 (exits until awdl0 has a link-local address, so it restarts)

[Service]
WorkingDirectory=$SRC/omdrop-plugin/bin
ExecStart=/usr/bin/python3 airdrop-serve.py --outdir $OUT --name "M3 Pro"
Restart=on-failure
RestartSec=10
StartLimitIntervalSec=300
StartLimitBurst=5
StandardOutput=append:$SRC/receiver.log
StandardError=append:$SRC/receiver.log

EOF
	cat > "$d/airdrop-notify.service" <<EOF
[Unit]
Description=Desktop notification when the AirDrop receiver finishes an upload

[Service]
ExecStart=/bin/bash $SRC/notify-receive.sh
Restart=always

[Install]
WantedBy=default.target
EOF
	systemctl --user daemon-reload
	# The receiver runs only while a window is open: the AirDrop on button starts it and the off button stops it.
	systemctl --user disable --now airdrop-receiver.service 2>/dev/null || true
	systemctl --user enable --now airdrop-notify.service
	ok "notify service enabled; receiver is started by the AirDrop on button"
	;;
ui)
	b=$(dirname "$(readlink -f "$0")")/airdrop-ui
	mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications" "$HOME/.local/share/kio/servicemenus"
	for f in airdrop-on airdrop-off airdrop-send; do install -m755 "$b/$f" "$HOME/.local/bin/$f"; done
	install -m644 "$b/airdrop-on.desktop" "$b/airdrop-off.desktop" "$HOME/.local/share/applications/"
	# Plasma 6 only honours service menus that are executable
	install -m755 "$b/airdrop-send.desktop" "$HOME/.local/share/kio/servicemenus/airdrop-send.desktop"
	kbuildsycoca6 >/dev/null 2>&1 || true
	ok "buttons installed: find \"AirDrop on\" in the application menu and pin it to the panel; right-click a file for Send via AirDrop"
	;;
remove)
	[ "$(id -u)" = 0 ] || bad "run with sudo"
	systemctl disable --now awdl0.service || true
	rm -f /etc/systemd/system/awdl0.service /etc/systemd/system/awdl0.service.d/firewall.conf /usr/share/polkit-1/actions/org.omarchy.omdrop.policy
	rmdir /etc/systemd/system/awdl0.service.d 2>/dev/null || true
	rm -rf "$LIB"
	firewall-cmd --permanent --zone=work --remove-port=8771/tcp
	firewall-cmd --reload
	systemctl daemon-reload
	ok "root part removed"
	;;
*)
	sed -n '2,7p' "$0"
	;;
esac
