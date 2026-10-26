#!/usr/bin/env bash
# Stage G: desktop and login screen on the native Mesa, only on GPU boots.
# Installs root-owned, filled-in copies of
#   agx-mesa-select (+ service): linker cache entry for $MESA_PREFIX/lib64 only
#     when the native G15 driver is bound (KWin ignores LD_LIBRARY_PATH because
#     it has the cap_sys_nice file capability)
#   60-agx-native-mesa: user environment generator, same condition
# and re-runs setup-nopasswd.sh (adds the mesa-select and restart-login actions).
# Then selects Mesa for this boot and restarts the login screen if nobody is
# logged in on it. Off switch: create /etc/agx-native-mesa.off and reboot.
# Usage: sudo install/stage-g.sh
. "$(dirname "$0")/lib.sh"
need_root; need_machine; need_krel

migrate_legacy

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
render "$REPO_DIR/system/agx-mesa-select.in" "$TMP/agx-mesa-select"
render "$REPO_DIR/system/60-agx-native-mesa.in" "$TMP/60-agx-native-mesa"
sh -n "$TMP/agx-mesa-select"
sh -n "$TMP/60-agx-native-mesa"

install -o root -g root -m 0755 "$TMP/agx-mesa-select" /usr/local/sbin/agx-mesa-select
install -o root -g root -m 0644 "$REPO_DIR/system/agx-mesa-select.service" /etc/systemd/system/agx-mesa-select.service
install -D -o root -g root -m 0755 "$TMP/60-agx-native-mesa" /etc/systemd/user-environment-generators/60-agx-native-mesa
restorecon -RF /usr/local/sbin/agx-mesa-select /etc/systemd/system/agx-mesa-select.service \
	/etc/systemd/user-environment-generators

"$(dirname "$0")/setup-nopasswd.sh"

systemctl daemon-reload
systemctl enable agx-mesa-select.service
systemctl start agx-mesa-select.service
/usr/local/sbin/agx-boot mesa-select
/usr/local/sbin/agx-boot restart-login || echo "Login screen not restarted; log out or reboot to apply"
echo STAGE_G_DONE
