#!/usr/bin/env bash
# Wi-Fi recovery after a FAILED suspend. Not installed by any stage; run it by hand.
# Problem (docs/features/sleep-lid-battery.md, "Bug: failed suspend with a USB-C display
# attached"): the DCP refuses system sleep with -16 while a USB-C display is attached,
# the suspend fails, and Wi-Fi does not come back on its own.
# The hook is a systemd-sleep script. It remembers /sys/power/suspend_stats/fail before the
# sleep ("pre") and, if the count grew after it ("post"), switches the Wi-Fi radio off and on.
# A successful suspend does nothing.
#
# Usage:
#   tools/sleep-wifi-hook.sh print      print the hook script (no root, changes nothing)
#   sudo tools/sleep-wifi-hook.sh install   write /usr/lib/systemd/system-sleep/90-agx-wifi-recover
#   sudo tools/sleep-wifi-hook.sh undo      remove it (the only file this tool writes)
#   tools/sleep-wifi-hook.sh status     show whether it is installed
# Test after install: attach a USB-C display, press the suspend key, wait 30 s, check Wi-Fi
# (nmcli -t -f DEVICE,STATE d) and look for "agx-wifi-recover" in `journalctl -b`.
HOOK=/usr/lib/systemd/system-sleep/90-agx-wifi-recover

print_hook() {
	cat <<'HOOK_EOF'
#!/bin/sh
# agx-linux-kit: restart Wi-Fi after a failed suspend. Remove with tools/sleep-wifi-hook.sh undo.
# systemd-sleep runs this with $1 = pre|post and $2 = suspend|hibernate|...
STATS="${AGX_SUSPEND_STATS:-/sys/power/suspend_stats}"
SAVE="${AGX_SLEEP_SAVE:-/run/agx-sleep-fail-count}"
case "$1" in
pre)
	cat "$STATS/fail" > "$SAVE" 2>/dev/null
	;;
post)
	before=$(cat "$SAVE" 2>/dev/null) || exit 0
	now=$(cat "$STATS/fail" 2>/dev/null) || exit 0
	rm -f "$SAVE"
	if [ "$now" -gt "$before" ] 2>/dev/null; then
		logger -t agx-wifi-recover "suspend failed (fail count $before -> $now); restarting the Wi-Fi radio"
		command -v nmcli >/dev/null 2>&1 || exit 0
		nmcli radio wifi off
		sleep 2
		nmcli radio wifi on
	fi
	;;
esac
exit 0
HOOK_EOF
}

need_root() { [ "$(id -u)" = 0 ] || { echo "Run with sudo." >&2; exit 1; }; }

case "${1:-}" in
print)
	print_hook
	;;
install)
	need_root
	[ -d "$(dirname "$HOOK")" ] || { echo "No $(dirname "$HOOK"); is this systemd?" >&2; exit 1; }
	tmp="$(mktemp)"
	print_hook > "$tmp"
	sh -n "$tmp" || { rm -f "$tmp"; echo "Hook failed the syntax check; nothing changed" >&2; exit 1; }
	install -o root -g root -m 0755 "$tmp" "$HOOK"
	rm -f "$tmp"
	echo "Installed $HOOK. Undo: sudo $0 undo"
	;;
undo)
	need_root
	if [ -e "$HOOK" ]; then rm -f "$HOOK" /run/agx-sleep-fail-count; echo "Removed $HOOK"; else echo "Not installed"; fi
	;;
status)
	if [ -e "$HOOK" ]; then echo "installed: $HOOK"; else echo "not installed"; fi
	;;
*)
	sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
	exit 1
	;;
esac
