# Touch ID stage 3b plan: enrol and verify (written 2026-10-27, nothing in this plan has been run)

Stages 3a and 3a+ proved the read-only half: the SEP attaches, the sensor node binds, the sensor answers on the bus (SPI mode 1, known revision code), and the enclave accepts the SBIO setup. Stage 3b is the first stage that **writes**. This page is the exact plan, with the risks stated first, so the user can decide.

## 1. What 3b changes, and what cannot be undone

| What | Where | Can it be undone? |
|---|---|---|
| The enclave's session records in the xART store (the 6 MiB `.gl` file inside the iBootSystemContainer partition) are rewritten as the enclave uses them. macOS shares this store. | iBootSystemContainer partition | The partition can be restored from the raw backup (section 4, step 1). **The enclave's own anti-replay state is not part of the partition and is not rolled back** (the driver's XART-SAFETY notes say a restored image does not guarantee recovery of it). |
| A new identity keybag is created inside the Secure Enclave when the module loads with `provision_keybag=1`. | Enclave | **No.** The enclave keeps it. The installer's own wording for "start over" is that the old keybag stays in the enclave, unused, and this cannot be undone once the Mac has rebooted. Linux makes a new one next time. |
| A machine reference key and the keybag are saved as root-only files. | `/var/lib` on Linux | Yes, move them aside. |
| Kernel trusted keys sealed by the enclave need this keybag. | Linux only | Lost if the keybag is reset. |

What 3b does **not** touch: the macOS and Linux root volumes, the boot files (the test boot restores itself), the login (password login stays; no PAM or authselect change), and the Neural Engine and GPU work.

**Evidence for 3b is thin.** The reference platform for this driver is the M2. There, a physical enrolment completed and the identities were saved, but after every tested reboot the enclave listed zero live identities, so persistence is the open question. The same notes say an actual xART write was not validated on that machine (the raw container hash did not change). On this Mac, three profile fields are inherited from the M2 profile and never tested: key-store variant, keybag creation, shared-memory capacity for system firmware 15.6. So 3b can fail in ways that leave the enclave unresponsive until the next reboot. Success is defined as: **an enrolled finger still verifies after a reboot** (section 4, step 6). An enrol that only works within one boot is not success.

## 2. Decisions the user has to make

1. **Allow writes to the shared xART store and the new enclave keybag** (the table above). Recommended: yes, but only after the backup in step 1 has passed and a second copy is off the M3.
2. **Guard level.** `xart_guard=1` (recommended for the first load) lists every record the enclave creates while Linux runs and refuses to rewrite any older record, so macOS records stay untouched. The driver's notes say this fits a Mac that has not used Linux Touch ID yet, and that it is untested on this chip. If the guard refuses the keybag creation, 3b stops there (a refusal is logged). Going to `xart_guard=0` (enclave may rewrite any record, including macOS ones) is a separate decision with its own yes.
3. **Does the user use Touch ID in macOS on this Mac?** If yes, the user should know that macOS Touch ID may need re-enrolling after 3b. This is a possibility, not a prediction; the plan cannot measure it without booting macOS.
4. **Downloads for the desktop path** (section 7): the libfprint source from gitlab.freedesktop.org (tag v1.94.100), a Fedora 44 container image and its packages. Only needed after 3b works. The first enrol and verify use a small client for the kernel interface and need no download.
5. **The user is at the keyboard** for the finger touches (the sensor is the power button). About 25 minutes for boot A and 15 minutes for boot B.

## 3. What is prepared (offline; deployed to the M3 but not run)

| Piece | Purpose |
|---|---|
| `touchid-xart.sh backup / verify / restore` | Read-only layout check, raw copy of the partition, two-read hash proof, state files, MANIFEST; verify; guarded restore. Tested against a synthetic partition in a Linux container with real sudo: pass case, refusal on a snapshot, refusal on a wrong extent size, restore, refusal on a corrupt image. |
| `touchid-3b.sh pre / load / open / enrol / verify / status` | The test-boot steps with the stop rule built in: after every step it prints any refusal, failure or timeout line from the kernel log and stops the sequence. Parsing and verdicts tested against stubbed logs (pass, guard refusal, incomplete load, open failure, enrol, verify). The hardware paths are untested. |
| `tools/touchid/sepbio.py` | Client for `/dev/sep-bio`: info, list, enrol, verify, cancel, delete. Struct sizes and ioctl numbers checked against the real header compiled in a Linux container (identical); logic tested against a fake device. Never prints the verify token. |
| `patches/apple-sep-sensor-probe.patch`, `apple-sep-3b.ko` | The 3b module is the 3a+ build (probe option off) plus the 13.5 key-store profile for this firmware (see section 9). The first 3b load used the 3a+ module as it was and failed; the fix is in `apple-sep-3b.ko`. |
| Patched libfprint build commands (section 7) | Not run. |

## 4. The steps

All commands run as the user (no sudo in front; the scripts call `sudo -n` themselves). The coordinator session runs them; the user touches the sensor.

**Step 1: backup (normal boot, before anything else).**
```
~/window/touchid-xart.sh backup
~/window/touchid-xart.sh verify
```
PASS lines: `1/4 PASS: one plain 6 MiB .gl extent, no snapshots, no revert state, all records CRC valid`, `3/4 PASS: copy and partition hash equal`, `BACKUP PASS: ...`, `VERIFY PASS`. If step 1/4 says FAIL the driver would refuse writes too: stop. Then copy the folder to the Mac host (second copy, private, never committed), for example from the host: `scp -r <m3-user>@<m3-address>:/data/touchid-backup/ibootsys-* <private folder>`. The 500 MB image holds Mac-specific data.

**Step 2: calibration (normal boot).**
```
~/window/touchid-calib.sh --install
```
PASS: `PASS: ... type FSCl` and `installed /lib/firmware/apple/mesacal-j516s.bin`. (The file was carved in 3a and is private.)

**Step 3: arm the test boot and reboot.**
```
~/window/touchid-boot.sh --sensor
```
Expect `ARMED`, expected boot file hash prefix `c9045f9b` (the same DTB as 3a). Reboot. Do **not** run `touchid-check.sh` in this boot: it loads the module read-only, and the module loads once per boot.

**Step 4: load (writes begin here).**
```
~/window/touchid-3b.sh load
```
It runs `pre` first (SEP booted, backup verified and still equal to the partition, calibration installed, module ready, AC on), then loads the module (`apple-sep-3b.ko`) with `xart_writes=1 provision_keybag=1 xart_guard=1 sensor_trace=1 xarm_trace=1`. PASS: `LOAD PASS: profile, xART writes ENABLED, guard level line, endpoints, keybag (provisioned now), /dev/sep-bio exists`, then `TRUSTED same-boot seal+unseal PASS` and `TRUSTED blob saved for the next boot test`. The log must contain `xART: APFS-resolved .gl extent ...; writes ENABLED`, `xART guard level 1`, `sks: identity keybag provisioned`.

**Step 5: open.**
```
~/window/touchid-3b.sh open
```
First open of the device: the driver brings the sensor up (power cycle, identification, calibration, patch) and registers it with the enclave. PASS: `OPEN PASS` and no review lines. This is the first time the calibration file and the enclave's sensor registration run on this chip.

**Step 6: enrol and verify (the user touches the power button).**
```
~/window/touchid-3b.sh enrol left-thumb
~/window/touchid-3b.sh verify
```
Enrol shows the stage count and the guidance (place, lift and move, hold still); PASS: `ENROL PASS: identity created`. Verify PASS: `VERIFY: MATCH, identity ... (token not shown)`. A wrong finger must give NO MATCH.

**Step 7: persistence test (the real success test).** Arm a second test boot with `touchid-boot.sh --sensor`, reboot, then:
```
~/window/touchid-3b.sh load      # keybag already present, no "provisioned" line; TRUSTED cross-boot unseal PASS
~/window/touchid-3b.sh open      # restores the enrolled identity from the enclave
~/window/touchid-3b.sh status    # enrolled count and live identity count must be 1
~/window/touchid-3b.sh verify    # MATCH without enrolling again
```
All four passing is "3b works". The test boot restores the normal boot by itself at the next boot.

## 5. Stop conditions

Stop means: run no further step, change nothing, collect the log file the script wrote under `~/window/touchid/logs/` (`3b-*.log`), tell the user.

| When | What triggers it | What to do |
|---|---|---|
| Any step | A line with refus, fail, error, timed out, timeout, unusable, unreadable, invalid, unavailable, Oops, BUG, panic or Call trace from apple_sep, apple-mesa or xART (the SEP random-source lines are known and ignored). The script prints these and stops. | Reboot (the next boot is the normal boot). Do not retry in the same boot: the driver says "no retry this boot". |
| Step 4 | `xART guard: refused ...` (the guard refuses the keybag creation) | Stop. Whether to use `xart_guard=0` is the user's decision. |
| Step 4 | `identity-keybag provisioning failed` | Stop. The enclave may be unresponsive until the reboot. |
| Step 4 | `LOAD INCOMPLETE` after 150 s | Run `status` once. If still incomplete, stop. |
| Step 5 | `Touch ID activation failed` or a sensor gate, identification or registration failure | Stop. |
| Step 6 | Enrol status other than 0, or no stage progress for a minute | Cancel (`sepbio.py cancel`), stop. |
| Step 7 | Zero live identities after the reboot, or the cross-boot unseal fails (the M2 pattern) | Stop. Persistence is not solved. Delete the identity (undo level 2). Do not start the desktop path. |
| Any time | The M3 stops answering or the enclave times out | Hold the power button only if it is hung; otherwise reboot. |

## 6. Undo ladder

1. **Stop here.** Reboot. The enclave keeps whatever it already stored. Nothing else is needed.
2. **Delete the identities.** `sudo python3 ~/window/touchid/sepbio.py delete-all --yes` (in a test boot with the module loaded).
3. **Restore the partition (last resort).** First run `~/window/touchid-xart.sh diff`, which lists which xART slots changed against the backup. Do not restore just because the partition differs: if the enclave committed writes after the backup, a restore makes the store older than the enclave expects (the anti-replay case; see section 10). In a normal boot (module not loaded): `~/window/touchid-xart.sh restore /data/touchid-backup/ibootsys-<time> --yes --accept-replay-risk`. It checks the image hash against the MANIFEST, writes the image, re-reads and compares, and moves the Linux Touch ID state files into a dated folder. Reboot. This brings back the APFS and xART files, **not** the enclave's own state, and not the Linux keybag the enclave already holds. Expect the next Linux load to create a new keybag.
4. **Boot macOS** and check it starts. If macOS Touch ID was in use and no longer works, re-enrol it there.

## 7. Desktop path (only after step 7 passed; untested)

No download happens before the user agrees. The Fedora package `aurora-sep` is **not** installed: it also changes the power button action, loads the driver with writes at every boot and installs a login-screen hook. Only the library and a service drop-in are used, and PAM stays password-only (the machine has no fingerprint feature enabled in authselect).

Build in a throwaway container on the M3 (Fedora 44, same C library as the host). The meson options are the ones the aurora README lists, plus a private prefix and no udev files; adjust if meson rejects one:
```
mkdir -p ~/aurora-build/out
podman run --rm -v ~/aurora-build/out:/out:z -v ~/m3gpu/src/linux/tools/aurora-sep/patches:/patches:ro,z \
  registry.fedoraproject.org/fedora:44 bash -c '
  dnf -y install git meson ninja-build gcc gcc-c++ pkgconf-pkg-config glib2-devel libgusb-devel libgudev-devel pixman-devel cairo-devel nss-devel openssl-devel &&
  git clone --depth 1 --branch v1.94.100 https://gitlab.freedesktop.org/libfprint/libfprint.git /src &&
  cd /src && git apply /patches/libfprint-1.94.100-apple-sep.patch &&
  meson setup build -Dprefix=/opt/aurora-sep -Dlibdir=lib64 -Ddrivers=default -Dintrospection=false \
    -Dgtk-examples=false -Ddoc=false -Dinstalled-tests=false -Dudev_rules=false -Dudev_hwdb=false &&
  ninja -C build && meson test -C build --print-errorlogs && DESTDIR=/out ninja -C build install'
```
Install (sudo, with the user's yes): copy `~/aurora-build/out/opt/aurora-sep` to `/opt/aurora-sep`, give it the library label (`semanage fcontext -a -t lib_t '/opt/aurora-sep(/.*)?'` then `restorecon -R /opt/aurora-sep`), and add a fprintd drop-in `/etc/systemd/system/fprintd.service.d/aurora-private.conf` with `Environment=LD_LIBRARY_PATH=/opt/aurora-sep/lib64` and `DeviceAllow=/dev/sep-bio rw`. Test with `fprintd-list`, `fprintd-enroll`, `fprintd-verify` in a test boot after `touchid-3b.sh load` and `open`. SELinux may block fprintd from `/dev/sep-bio`; the fix is a local policy module, which needs its own yes. Undo: remove the drop-in and `/opt/aurora-sep`, `systemctl daemon-reload`.

Not done in this plan, on purpose: enabling fingerprint in PAM, boot-time loading with writes, the greeter hook. They wait until persistence has been shown across at least two reboots.

## 8. What is verified and what is not

Verified offline: the backup, verify and restore logic (synthetic partition, real sudo), the 3b step parsing and verdicts (stubbed logs), the client's struct sizes and ioctl numbers (compiled against the real header), the client logic (fake device). Verified on the M3 in earlier stages: SEP attach, endpoints, xART read-only parse (170 slots, 10 live records, no malformed), sensor power, SPI binding, sensor answer in mode 1.

Not verified: every write; the keybag creation on firmware 15.6; the inherited profile fields; the sensor bring-up with calibration and enclave registration; enrol; match; persistence after reboot; the libfprint build; SELinux behaviour of fprintd with the device.

## 9. First 3b load (2026-10-27 14:06): CREATE_KEYBAG refused, cause and fix

**What happened.** The load ran under the user's answers (backup first, guard on, no macOS Touch ID use). Backup and verify passed, the calibration was installed, and the pre-checks passed. The kernel log then showed: guard level 1 with 8 session records, none created by Linux; xART writes ENABLED; attach with 7 endpoints; the xART reads all with reply status 0; and then `sks: CREATE_KEYBAG reply carried no parsable body: mailbox status -13, response 0 bytes`, `bringup: identity-keybag provisioning failed; no retry this boot`. The script stopped at LOAD, as designed. The partition still hashed equal to the backup afterwards. Diag: keybag=failed, keystore=open, protocol=variant5, sensor=unbound, touchid=failed, xart=enabled.

**It is not the guard.** The guard acts on xART record writes and logs `xART guard: refused ...` when it refuses one. There is no such line, and the trace of xART operations (the load ran with `xarm_trace=1`) shows only reads and acknowledgements, all with status 0, the same sequence as the read-only 3a+ run. The enclave never asked for a write. The -13 is the enclave's own reply status to the key-store create request (a signed byte, 0xF3), with an empty body. So `xart_guard=0` would not change this: the request is refused before any xART write. Guard 0 only matters later, and only if the enclave asks to rewrite a record that predates Linux (the M1 case), which would show as a guard refusal.

**The cause is the key-store dialect in the profile.** The driver's own profile notes record this exact answer: "status -13, empty reply" for the variant-5 create on M2 Pro/Max enclaves with older system firmware (iBoot builds before 26.3's, seen on 26.0 and 26.2). Those enclaves take the 13.5 key store, and the J414s on 26.0 enrols, matches and restores after a reboot that way. This Mac reports iBoot 11881 and system firmware 15.6 (the macOS 15 generation), older still. The J516S profile had inherited the variant-5 create from the M2 profile; the stage 1 notes already listed `keybag_create` and `key_store` as unverified. The 13.5 key store needs the ADT value `cpx-encryption-mode`, which on this Mac is 2 (same as the M1 and M2 boards).

**The "7 endpoints" and "12 endpoints" are consistent.** The attach line counts the endpoints advertised during the first exchange. The remaining five (biometrics, credentials, key store, key derivation, secure-service) appear after the xART reads. The 3a+ read-only run printed the same 7 and ended with 12.

**What the failed attempt left.** Partition: unchanged. Linux state: a small `aurora-sep-keybag.bin` (52 bytes, written at the failed create) and an empty guard list. The driver marks a refused create as "created nothing" and retryable, so the next attempt is allowed in a new boot; these files are in the restore list of `touchid-xart.sh`. The enclave answered with an error status, so no keybag was created; the log cannot prove more than that.

**The fix (built, not loaded).** `T6030_SEPOS13`: key store 13.5 with `cpx-encryption-mode` 2, create encoding version 2 with bag type and parent as on the M1 and the M2 Pro 13.5 profile. It is selected by the same rule as the M2 Pro/Max: an iBoot build before 26.3's takes the 13.5 key store; a missing or newer build keeps the variant-5 profile. The patch carries Mac-specific values, so it stays in the private folder; the module is `apple-sep-3b.ko` (vermagic equals the running kernel, no unresolved symbols). The log will announce `M3 Pro on system firmware 15.6 (...), OS firmware 14.7: using the 13.5 key store` and the profile name `T6030/J516s (13.5 key store)`.

**Next test.** Same flow as step 3 and 4 above, with the new module installed first (`sudo install -D -m 0644 ~/window/touchid/apple-sep-3b.ko /lib/modules/7.2.11-m3gpu+/touchid-test/apple-sep-3b.ko && sudo restorecon -F` the same path). The backup still equals the partition, so `pre` passes without a new backup. Expected: the 13.5 announcement, an endpoint initialisation and environment set (the 13.5 dialect), then `sks: identity keybag provisioned`. If the guard now refuses a write, the log says so: stop and ask the user (guard 0 is a separate decision). If the create is refused again with another status, stop; the profile fields still unverified are then the shared-memory size and the key-store init values, and the next evidence would have to come from a macOS trace.

**Risks that are new with this path.** The 13.5 dialect is hardware-verified on the M1 and on the J414s, not on an M3 Pro. On cold-boot M1 Macs the 13.5 create also rewrites a session record that predates Linux, which the guard refuses; this Mac is warm-attach like the J414s, where the guard stayed on. Both are only known from the driver's notes.

## 10. Second 3b load (2026-10-27 14:15, 13.5 key store): writes accepted, then refused

**What the log shows.** The 13.5 profile was selected (`using the 13.5 key store`, capability word 2, IPC header version 2). After the same xART reads as before, the enclave wrote: three root writes (op 0x01, 850 bytes), one session write (op 0x06, 1583 bytes), then a second session write (op 0x06, 1421 bytes) that the guard refused: `xART guard: refused to rewrite a kind-4 record this Linux install did not create`. The enclave got status 0x16 for that write, and CREATE_KEYBAG failed with mailbox status -1 (no body). `bringup: identity-keybag provisioning failed; no retry this boot`.

**What changed on the partition (measured with `touchid-xart.sh diff`, read-only).** Of all 128000 blocks, exactly 3 differ from the backup, all inside the xART file:
- A new root record (kind 2, length 850, revision 305, CRC valid) in a free slot, and the old kind-2 root (length 753, revision 301) cleared in its slot. This is the enclave's own root update; the write order (new slot, flush, clear the old one) is the driver's.
- A new session record (kind 4, length 1567, revision 303, CRC valid), which the guard had listed as Linux's before the write (the guard list file holds exactly one entry).
- Nothing else. The other root (kind 1) and all 8 session records that existed before are unchanged in every block. The partition has no changes outside the xART file.

So the shared root was rewritten (allowed at guard level 1; level 2 would have refused it), one session record was added, and the one write that touched a record that predates this boot was refused. Revisions 302 and 304 were intermediate root writes that were superseded.

**Which record the refused write targeted.** The store holds two roots (kinds 1 and 2) and session records (one kind 3, seven kind 4 before this run). The record format does not say which OS wrote a session record. The enclave read four session records at attach, every boot (lengths 1334, 136, 441 and 40; each twice). It is told the booted OS identity by the OS-UUID request (the preboot UUID of the install it boots), so these four are most likely the session state of this boot's own OS, not another OS's. The refused write was 1405 bytes of payload; the closest record is the 1334-byte one, which fits a record that grew by one keybag entry. This is inference, not proof: nothing in the store names an owner. It also matches the driver's own note for the M1 family: the 13.5 create rewrites a session record that predates the Linux driver, and with the guard on the keybag cannot be created.

**Is the store safe for macOS as it is?** Structurally yes: every record has a valid CRC, no pre-existing session record changed, and the new state is exactly what the enclave itself wrote and had acknowledged. Whether the enclave's persistent anti-replay state agrees with the store cannot be measured offline. The enclave acknowledged every write except the last, so it most likely holds the root at revision 305; the refused write is the only inconsistent step. A macOS boot would be the only real test.

**Should the backup be restored?** Not now. The partition differs from the backup by writes the enclave made and acknowledged, so the backup (root revision 301) is now older than anything the enclave committed. Restoring it would create exactly the rollback case that anti-replay exists to catch, and the driver's own notes say a restored image does not guarantee the enclave's state follows. Restore is for a store that is actually broken (macOS or the enclave refuses it), and even then it may not heal. A new backup of the current state is the right baseline for any further attempt.

**What guard 0 would change.** The guard has no effect on the enclave's own decisions; it only decides whether a write reaches the disk. With `xart_guard=0` every write passes: the enclave could rewrite any session record, though the trace suggests it only asks for the ones it loaded for this boot. A refusal in the middle of a create (as here) leaves a half-finished sequence in the enclave and on disk, which is worse than letting the create finish. The cost of guard 0 is that nothing protects another OS's session records if the enclave ever asks to rewrite one. The way to check afterwards is the same read-only `diff` against a fresh backup: it must show changes only to the roots and to the session records that were loaded at attach (lengths 1334, 136, 441, 40) plus new records.

**Options (the user decides).**
1. Stop Linux Touch ID here. No restore. The orphan session record and the new root stay; nothing known is broken.
2. Retry with `xart_guard=0`, after a fresh backup and with the diff check afterwards. This is the documented path for this case on the M1 family, but it is untested on an M3 Pro.
3. Build a stricter guard first: allow rewrites only of the records the enclave loaded at attach in this boot (a driver change; offline; not built). It keeps the other session records protected while letting the create finish.
Optionally, one macOS boot to confirm macOS starts, whichever option is chosen.
