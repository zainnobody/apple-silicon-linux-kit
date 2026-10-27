#!/usr/bin/env bash
# Boot macOS once from Fedora, without a password: installs asahi-bless, /usr/local/sbin/agx-os and
# a sudoers rule for exactly its subcommands. The default boot volume stays as it is.
#   sudo install/setup-macos-switch.sh
# Then, as your user:
#   sudo -n /usr/local/sbin/agx-os status        show the default and next boot volumes
#   sudo -n /usr/local/sbin/agx-os macos-once    boot macOS on the next boot only
#   sudo -n /usr/local/sbin/agx-os clear-next    cancel macos-once
#   sudo -n systemctl reboot                     (allowed by the agx-boot or m3gpu rule)
# Undo: sudo rm /usr/local/sbin/agx-os /etc/sudoers.d/agx-os
set -euo pipefail
. "$(dirname "$0")/lib.sh"
need_root
need_machine

dnf install -y asahi-bless
command -v asahi-bless >/dev/null

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/agx-os" <<'EOF'
#!/usr/bin/env bash
# Boot volume control for one user without a password (installed by setup-macos-switch.sh).
set -euo pipefail
case "${1:-}" in
status)
	echo "default: $(asahi-bless --get-boot)"
	echo "next:    $(asahi-bless --get-boot --next 2>&1 || true)"
	asahi-bless --list-volumes
	;;
macos-once)
	asahi-bless --set-boot-macos --next --yes
	echo "next boot: macOS (once). Reboot with: sudo -n systemctl reboot"
	;;
clear-next)
	asahi-bless --clear-next
	;;
*)
	echo "usage: agx-os status | macos-once | clear-next" >&2
	exit 1
	;;
esac
EOF

cat > "$tmp/agx-os.sudoers" <<EOF
# Installed by agx-linux-kit install/setup-macos-switch.sh
Cmnd_Alias AGX_OS = /usr/local/sbin/agx-os status, /usr/local/sbin/agx-os macos-once, /usr/local/sbin/agx-os clear-next
$AGX_USER ALL=(root) NOPASSWD: AGX_OS
EOF
visudo -cf "$tmp/agx-os.sudoers"

install -m 0755 -o root -g root "$tmp/agx-os" /usr/local/sbin/agx-os
install -m 0440 -o root -g root "$tmp/agx-os.sudoers" /etc/sudoers.d/agx-os
visudo -c >/dev/null
echo "Installed /usr/local/sbin/agx-os and /etc/sudoers.d/agx-os for $AGX_USER."
/usr/local/sbin/agx-os status
