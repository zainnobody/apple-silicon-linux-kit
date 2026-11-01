# Touch ID install plan: boot, libfprint, lock screen and login (written 2026-10-30; installed on the M3 on 2026-10-31, results in touchid.md "Install and daily use")

Decision (2026-10-30): no more Touch ID experiments. The 3f mode 2 result is enough: a late touch matches, another finger does not, and the identity survives reboots. This plan is an install only. It needs one sudo window with the M3 on the charger, and one reboot. Sudo stays password-only. Settle tuning and more trials are optional later work (section 9).

The scripts are in `tools/touchid/integration/`. The offline test is `tests/touchid-integration-test.sh` (fake root, stub commands, 30 checks).

## 1. What changes, and how each step is undone

`ti-install.sh install` runs these steps in this order. Each step has its own undo. The boot file is last, so a failure before it leaves the next boot unchanged. If any step fails, the script undoes the steps of that run, newest first.

| Step | What it does | Undo |
|---|---|---|
| `module` | Copies `apple-sep-3f.ko` (hash pinned) to `/lib/modules/<krel>/updates/apple_sep.ko` (updates/ wins over the old test modules in `touchid-test/`; found 2026-10-31), runs `depmod`, checks that `modinfo` finds it. | Removes the file, `depmod`. |
| `units` | Installs `/usr/local/sbin/m3-touchid-load`, `/etc/systemd/system/m3-touchid.service` (enabled, not started), `/etc/m3-touchid.conf` and a copy of the installer as `/usr/local/sbin/m3-touchid-install`. | Disables and removes them. The installer copy stays so the undo can run again. |
| `selinux` | Installs the policy module `m3touchid` (fprintd may open the device node) and labels `/opt/aurora-sep` as `lib_t`. | `semodule -r`, `semanage fcontext -d`. |
| `libfprint` | Installs the `libfprint-aurora` RPM (hash pinned, files only under `/opt/aurora-sep`). The distro `libfprint` is not touched. | `rpm -e` (only if this tool installed it). |
| `dropin` | `/etc/systemd/system/fprintd.service.d/aurora-private.conf`: `LD_LIBRARY_PATH`, `DeviceAllow=/dev/sep-bio rw`, start after `m3-touchid.service`, `--no-timeout`. | Removes the file. |
| `pam-lock` | Replaces `/etc/pam.d/kde-fingerprint` (the original is saved). The lock screen service `kde` (password) is not changed. | Restores the saved file. |
| `pam-login` | Creates `/etc/pam.d/plasmalogin` from the vendor file, with two added lines before the password stack: `auth [success=1 default=ignore] pam_unix.so nodelay`, then `-auth sufficient pam_fprintd.so max-tries=2 timeout=5`. A typed password logs in at once; Enter with an empty password field asks for the finger. `m3-touchid-install relogin` re-applies only this step. | Removes the override. |
| `bootbin` | Writes `boot.bin.stageS` (stageE with only the J516S device tree replaced by the Secure Enclave and sensor device tree) and makes it `boot.bin`. `boot.bin.stageE` stays as the fallback. | Copies `boot.bin.stageE` back to `boot.bin`. Works without a working Touch ID. |

Never edited: `system-auth`, `password-auth`, `login`, `sudo`, `sshd`, and the authselect profile. The password path of the lock screen and of the login screen is the same stack as before. A fingerprint line that finds no reader, no enrolled finger, no match or a timeout falls through to the password.

One-command rollback, from a TTY (Ctrl+Alt+F3) or over SSH, with no working Touch ID needed:

```bash
sudo m3-touchid-install undo
```

## 2. Before the window

- The user connects the charger and opens the sudo window.
- The coordinator checks that no test boot is armed (`m3-touchid-restore.service`, `ane-window-restore.service`) and that no other session needs the M3.
- The coordinator copies `tools/touchid/integration/` to the M3 (any folder, for example `~/window/integration`) and `touchid-boot.sh`, `touchid-xart.sh`, `touchid-3b.sh`, `make-window-dtb.py` and `sepbio.py` stay in `~/window` as they are now.
- Inputs that must exist on the M3: `~/window/touchid/apple-sep-3f.ko`, the `libfprint-aurora` RPM in `~/aurora-build/rpmbuild/RPMS/aarch64/`, the sensor calibration file in `/lib/firmware/apple/`. The installer checks their hashes and refuses other files.

## 3. The window (user types the sudo password and the account password)

```bash
cd ~/window/integration && ./ti-run.sh install
```

What it does, in order:

1. Checks sudo and the charger.
2. Takes an xART backup (`touchid-xart.sh backup`, read-only toward the partition, about a minute). `--skip-backup` skips it, only if a backup from today exists.
3. Builds the new boot file as a dry run (`touchid-boot.sh --dry --sensor-irq`). This reads the ESP and writes only under `~/window/touchid`.
4. Runs `ti-install.sh install` as root: preflight, the eight steps, and a password test.

The password test runs after `pam-login`. It asks the user to type the account password once for the service `kde` and once for `plasmalogin`. For each service it passes only when the right password is accepted and a random wrong password is refused. If it fails, everything of the run is undone. Without a reader the fingerprint line returns "no device" at once, so the test shows that the password path works with the new files.

PASS output: `PREFLIGHT PASS` lines, then `step <name>: apply` for all eight steps, then `ALL STEPS APPLIED`. Nothing is loaded and nothing is rebooted.

Stop rules in the window:

- Any `FAIL` line in preflight: nothing was changed. Fix the cause or stop.
- `STEP FAILED`: the script has undone the run. Do not retry by hand. Send the output to the coordinator.
- `PASSWORD TEST FAILED`: same.
- A prompt that asks for anything other than the account password: stop.

## 4. The reboot and the checks

The user reboots once (`systemctl reboot`). The boot uses `boot.bin.stageS`. After login with the password:

```bash
cd ~/window/integration && ./ti-run.sh verify
```

`verify` checks: the kernel, the Secure Enclave nodes in the device tree, `apple_sep` loaded, the kernel log line `xART guard level 3` (the parameter has no sysfs entry), `sensor_rearm_mode=2`, `sensor_rearm_settle_ms=1800`, `m3-touchid.service` active with the line `Touch ID is ready`, `/dev/sep-bio`, `fprintd-list` sees one reader, the fprintd unit has the private library path, no SELinux denial for fprintd, the PAM files, the files that must stay unchanged, `boot.bin` is stageS. Then it runs the alarm check (`touchid-3b.sh alarm`, partition against the newest backup). PASS lines: `VERIFY PASS` and `ALARM CHECK OK`.

Checks by hand (the coordinator's list):

1. Password login: log out, log in with the password. (Expect the KWallet prompt, see section 7.)
2. Lock screen and password: Meta+L, type the password. It unlocks.
3. Enrol the finger (section 5), then lock the screen, hold the finger on the sensor. It unlocks.
4. Lock screen and a wrong finger: it does not unlock.
5. Login screen with the finger: log out, enter the user name, hold the finger on the sensor. The password also works after the fingerprint prompt ends (up to 10 s).

If a check from 1 or 2 fails: `sudo m3-touchid-install undo pam-lock pam-login` from a TTY, then tell the coordinator.

## 5. Enrolment through fprintd (the one new, untested path)

The identity that exists in the enclave was made by `sepbio.py`. fprintd does not know it. libfprint labels each print with an identity and matches by the enclave identity UUID, so the old identity would win the match and fprintd would report no match. The old identity must go first, then fprintd enrols a new one.

```bash
cd ~/window/integration && ./ti-run.sh enroll right-index-finger
```

It stops fprintd, lists the identities, asks the user to type `DELETE`, runs `sepbio.py delete-all --yes`, starts fprintd, runs `fprintd-enroll`, then `fprintd-verify`. The enclave holds up to 3 identities. Stop after 3 failed enrol attempts. A failed enrol does not touch the password path. The enrol through libfprint has not run on this M3. Only `sepbio.py` enrol and verify have.

## 6. How the finger path works

- Boot: `boot.bin.stageS` adds the Secure Enclave nodes, the sensor power line, the SPI timing and the data-ready interrupt to the J516S device tree. Normal boots before this had no Secure Enclave.
- Driver: `m3-touchid.service` (only on a boot with the Secure Enclave nodes, and not when `/etc/m3-touchid.off` exists or `m3.touchid=off` is on the kernel command line) runs `m3-touchid-load`. It loads `apple_sep` once with `xart_writes=1 provision_keybag=1 xart_guard=3 sensor_rearm_mode=2 sensor_rearm_ms=300 sensor_rearm_settle_ms=1800`, waits until the enclave seals and unseals a trusted key, waits for `/dev/sep-bio`, and opens it once. The open activates the sensor and restores the enrolled identities. Settings are in `/etc/m3-touchid.conf` and take effect at the next boot.
- fprintd: starts after the unit (so the driver finds the device node at start), with the private libfprint and `--no-timeout`.
- Lock screen: kscreenlocker runs `kde` (password) and `kde-fingerprint` (finger) side by side.
- Login: `plasmalogin` tries the finger first. A user without an enrolled finger gets the password prompt at once.

## 7. Limits the user must know

- Hold the finger on the sensor. With mode 2 the sensor detects a touch in about the first 2 s of each arm cycle. A late touch can need a second try.
- A fingerprint cannot unlock KWallet. After a finger login, the first application that asks for a stored secret asks for the wallet password.
- Login screen flow (tuned 2026-10-31): a typed password logs in at once, with no finger wait. Enter with an empty password field asks for the finger for up to 5 s (rest it on the key). Before this change, every login waited up to 10 s for a finger first. The lock screen checks the finger and the password at the same time.
- Suspend and resume with Touch ID loaded have not been tested. Use the password after a resume if the finger does not work.
- Each boot with the driver writes xART records (the guard allows only the rewrites that the alarm check knows). The alarm check must say OK after the first boot.
- Few trials exist. With no false accept in n trials, the upper limit of the false accept rate is only about 3 in n (rule of three). That is why sudo stays password-only and the password is always accepted. Stop rule after the install: if a wrong finger ever unlocks the lock screen or the login screen, run `sudo m3-touchid-install undo pam-lock pam-login` at once and report it.
- A kernel update does not change `boot.bin` (m1n1 updates are paused), but the new kernel has no `apple_sep` module. The unit finds no module and does nothing. Rebuild and install the module for the new kernel before using Touch ID there.
- `m3gpu-default gpu` copies `boot.bin.stageE` over `boot.bin`. After it, Touch ID has no Secure Enclave until `ti-install.sh step bootbin apply` runs again. `m3-touchid-install verify` shows this as `boot.bin is not stageS`.

## 8. Rollback ladder (each level needs less than the one above)

1. One step: `sudo m3-touchid-install undo <step>`. All steps: `sudo m3-touchid-install undo`. Works from a TTY or over SSH. Status: `sudo m3-touchid-install status`.
2. Stop loading the driver without removing anything: `sudo touch /etc/m3-touchid.off`, or add `m3.touchid=off` to the kernel command line in the GRUB menu (press `e`). The password still works. The fingerprint lines find no reader and fall through.
3. Put the old boot file back by hand: `sudo cp /boot/efi/m1n1/boot.bin.stageE /boot/efi/m1n1/boot.bin`, or `sudo m3gpu-default gpu`.
4. If Linux does not boot at all: the coordinator uses the existing recovery path for the M3 (macOS recovery). This plan adds no new recovery path. The new boot file differs from stageE only in the J516S device tree, and that device tree (with the sensor interrupt) booted in the 3d to 3f test boots.
5. Never restore an xART backup because of a PAM or boot problem. Restore it only for xART damage that `touchid-3b.sh alarm` shows, and only after the user decides.

## 9. Optional later work (not part of the install)

- Settle tuning: test 1000, 600 and 300 ms with `loopverify.sh` and the touch logger, then set `SETTLE_MS` in `/etc/m3-touchid.conf` and reboot. The module parameter can also change at run time under `/sys/module/apple_sep/parameters/`.
- A larger trial count (many wrong-finger and enrolled-finger trials) before any use beyond the lock screen and login.
- Sudo: add a `sufficient pam_fprintd.so` line to `/etc/pam.d/sudo` only after the trials. Keep an open root shell while you test it.
- Suspend and resume test with Touch ID.
- A Plasma login order that shows the password field first (finger on Enter with an empty field).

## 10. What needs the user

| Need | When |
|---|---|
| Connect the charger | Before the window |
| Open the sudo window and type the sudo password | Start of the window (the script uses `sudo -n`) |
| Type the account password twice (`kde`, `plasmalogin`) | The password test in the window |
| One reboot (`systemctl reboot`) | After `ALL STEPS APPLIED`. No script reboots. |
| Type the account password at the login screen | After the reboot |
| Hold the finger on the sensor, lock and unlock | Checks 3 to 5, and enrolment |
| Type `DELETE` to remove the old test identity | `ti-run.sh enroll` |
| A yes from the user for the install as a whole | Before the window (the coordinator asks) |

## 11. Not verified

Offline only (fake root, stub commands): step order, each undo, the failure rollback, the boot file proof, the PAM file generation and that no other PAM file changes. Not run: the real `semodule` and `checkmodule` compile of `m3touchid.te`, the real `rpm -i`, the real PAM stacks (`pam-auth-test.py` was only compile-checked, libpam is not on the build host), the loader `m3-touchid-load` and the unit on the M3, fprintd with the private library and the SELinux label, enrolment through fprintd, the lock screen and login screen with a finger, suspend and resume. The first window shows these. An SELinux denial for fprintd is shown by `verify`; `ausearch -m avc -ts boot` has the detail.
