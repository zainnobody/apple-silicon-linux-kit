#!/usr/bin/env bash
# Desktop notification when the AirDrop receiver finishes an upload. Follows the receiver log. No root.
# Installed as ~/omdrop-test/notify-receive.sh by airdrop-persist.sh user, and run by a systemd user service.
SRC=${AIRDROP_SRC:-$HOME/omdrop-test}
OUT=${AIRDROP_OUT:-$HOME/Downloads}
DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}
export DBUS_SESSION_BUS_ADDRESS
# Look: the flat AirDrop icon if installed (airdrop-ui/install-icon.sh), else the theme icon. A file path works in every notification server.
ICON=emblem-shared
M3_ICON="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/m3-airdrop.svg"
[ -e "$M3_ICON" ] && ICON=$M3_ICON
tail -n0 -F "$SRC/receiver.log" | while read -r line; do
	case "$line" in
	*'POST /Upload HTTP/1.1" 200'*)
		sleep 1
		notify-send -a AirDrop -i "$ICON" "File received" "$(ls -t "$OUT" | head -1) is in $OUT."
		;;
	esac
done
