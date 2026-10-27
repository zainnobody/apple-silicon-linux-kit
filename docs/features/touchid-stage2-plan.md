# Touch ID Stage 2 plan: dry load of `apple_sep`, rollback, and the m1n1 proxy question

Date: 2026-10-27. Status: **plan only**. No reboot, no sudo, no write to the ESP or to the M3 boot chain was done. Part of [touchid.md](touchid.md). The values (addresses, interrupts, blobs) stay in the private notes folder. This file has none.

## Decision in one page

- **The m1n1 proxy is not needed.** Two routes can reach the dry load. Route A uses the `boot.bin` staging that this M3 already uses (stage C, D, E toggled many times on 2026-10-26). Route B uses the m1n1 proxy over USB. Route A needs no security policy change and no cable. Route B needs both.
- **Recommended: Route A.** It writes one new file to the ESP, switches `boot.bin` with the existing script, and has a rollback by one command, and a second rollback from macOS if the boot fails.
- **The `SEPFW` risk is now low.** The stock stage 1 m1n1 (v1.6.1) chainloads our stage 2 and its `chainload.c` returns an error when `/chosen/memory-map` has no `SEPFW` (read upstream source 2026-10-27). Stage 2 is running, so `SEPFW` was there. I have not proved that stage 1 takes that code path on this Mac, so keep the macOS recovery step ready.
- **Nothing here enrols a finger.** The dry load runs with `xart_writes=0 provision_keybag=0` and never opens `/dev/sep-bio`.
- **Shares this window with the camera proposal.** The camera temporal-filter DTB change also needs a new `boot.bin`, so both use the later boot-file reboot: [Proposal only: switch on the temporal filter in the next boot-file window](audio-camera-video.md#proposal-only-switch-on-the-temporal-filter-in-the-next-boot-file-window-not-done) (audio session commit `56a2f73`, in its own copy of this repo until merged, so the link works after the merge). Combine them in one DTB only if both changes pass A1 together (diff shows added lines only), and keep the rollback to `boot.bin.stageE`.

## What the plan relies on (checked, read-only)

| Fact | Source, date |
|---|---|
| Installed m1n1 stage 2 is `aca1258`. Its `dt_set_sep()` runs only with an `/aliases/sep` entry. It reserves `SEPFW`, copies ADT `lpol` to `local-policy-manifest` and `ibot` to `iboot-manifest`. A failure inside it stops the boot (`bail`). | m1n1 source on the M3, `src/kboot.c`, read 2026-10-27 |
| Device trees are embedded in `boot.bin` on the ESP. All boot entries use the same one. | `/usr/bin/update-m1n1`, read 2026-10-27 |
| `update-m1n1` is paused on the M3 (`M1N1_UPDATE_DISABLED=1`). Staged files exist: `boot.bin.stock`, `.stageC`, `.stageD`, `.stageE`, `.old`. Current `boot.bin` equals `.stageE` (sha256 `f3197272d588f4b0a037c5f81f0cfb2c36dfc6c7398a4205910ed8b9cbaa0725`). | `m3gpu-boot status`, run 2026-10-27 (read-only action) |
| Existing tools: `m3gpu-boot` (`use-stageE`, `use-stock`, `status` need no password), `make-bootbin.sh` and `use-bootbin.sh` (sudo password). `use-bootbin.sh` refuses to run without `boot.bin.stock`. | scripts on the M3, read 2026-10-27 |
| A test DTB built from the **installed** J516S dtb adds exactly 55 lines and removes 0 (SEP DART, SEP, mailbox, spi2 with sensor, `sep` alias). Built with `make-test-dtb.py` (private notes). A DTB built from the live source tree is NOT equal to the installed one (1163 diff lines), so do not build it from source. | M3 scratch folder, 2026-10-27 |
| The partition label the driver opens, `iBootSystemContainer`, exists. | `/dev/disk/by-partlabel` on the M3, 2026-10-27 |
| The driver opens the host state file under `/var/lib` and creates it if absent, even with writes off. | `store.rs`, read 2026-10-27 |
| `boot-args` in the macOS ADT is empty. The stage 1 proxy backdoor needs `-v` plus a lowered policy. | ADT dump, Asahi m1n1 guide read 2026-10-27 |

## Result of steps A0 to A1b (done 2026-10-27, no root, nothing installed)

- A0: `boot.bin` equals `boot.bin.stageE`, `boot.bin.stock` is present, the installed J516S dtb hash is unchanged, the m1n1 file hash matches the one pinned in `m3gpu-boot`.
- A1: the test dtb folder holds 46 dtbs. Only the J516S one differs from the installed folder. That one adds 55 lines and removes none.
- A1b: `apple_sep.ko` builds in a scratch folder in 2 seconds with two jobs, against the existing build folder, without touching it (the dry run wrote nothing outside the scratch folder). Findings:
  - The module needs `fv_shim.o`. In the kernel tree it is built into the kernel only when `APPLE_SEP` is on, and it is off in the running kernel. The scratch build adds `fv_shim.o` to the module, so no kernel rebuild is needed.
  - `vermagic` equals the running kernel. All 261 undefined symbols exist in the running kernel's symbol table. The module depends on `macsmc`, which exists as a module.
  - The module contains the new `T6030/J516s` profile. It has not been loaded.
- A kernel rebuild is not needed for any step of route A.

## Window scripts (prepared 2026-10-27, not run)

The coordinator scheduled the window after the Neural Engine boot, together with the camera temporal-filter change. The steps above are scripted in `~/window/` on the M3 (source copies in the private notes folder):

| Script | What it does |
|---|---|
| `touchid-boot.sh --dry` | Read-only. A0 hash check, builds the merged test DTB (SEP nodes, `sep` alias, `apple,temporal-filter` 0 to 1), proves the diff has 1 removed line and only added lines otherwise, composes the expected `boot.bin.sep`. Writes nothing to the ESP. |
| `touchid-boot.sh` | Does the same, then builds `boot.bin.sep`, proves it equals the base `boot.bin` with only the J516S dtb replaced, switches `boot.bin`, and arms a self-removing unit that puts the base back on the first boot that uses it. A plain reboot is the test boot; the next reboot is normal. It stops if the Neural Engine window is armed or a Touch ID unit exists, and it never reboots. |
| `touchid-check.sh` | After the boot: part 1 SEP manifests in the device tree, part 2 camera property, part 3 camera log and a 5 s capture with a temporal-noise number, part 4 module hash, vermagic and symbols, part 5 the dry load (last, never `rmmod`, never `/dev/sep-bio`). PASS or FAIL per part, log in `~/window/touchid/logs/`. `--baseline` records the camera noise number before the test boot. |
| `touchid-disarm.sh` | Before the reboot: base `boot.bin` back, restore unit removed. |

Self-test results (no root writes, before the window): `--dry` passes with base `boot.bin.stageE`. The check script on the normal boot reports parts 1 and 2 FAIL (correct: the test DTB is not active) and part 4 PASS.

## Window result (2026-10-27, test boot 12:00, run by the coordinator)

| Part | Result | Notes |
|---|---|---|
| 1 SEP manifests in the device tree | PASS | Both manifests present, alias set, reserved region present. Sizes differ from the macOS dump (the Linux boot has its own manifests). |
| 2 camera property | PASS | `apple,temporal-filter` read 1 |
| 3 camera | **FAIL (real)** | No frames, capture hung in the ISP stop path. Kernel: `IO: timed out on request` and `failed to send OPCODE 0x0101` (then 0x0104, 0x0021), `firmware did not suspend, stopping it`. The camera node itself appeared. Baseline on the normal boot: 150 frames in 5 s. |
| 4 module | PASS | Hash, vermagic, 261 symbols |
| 5 SEP dry load | **PARTIAL** | See below |

**Camera.** The firmware hangs when the filter is on. This differs from Asahi issue 630 (the node never appears): here probe works and streaming does not. The kernel recovered by force-stopping the firmware and the machine stayed usable. Decision: the property stays 0 and the proposal is closed. The audio session can go on with its ranks 2 and 3 (the firmware's own denoise controls, or user-space denoise). My log check also matched an `apple-dcp` line as an ISP error (the text `disp` contains `isp`). Fixed.

**SEP.** Kernel lines after the insmod: DART changeset applied (BIT(40) alias window), SEP node enabled, platform device created, profile `T6030/J516s`, xART parsed read-only (170 slots, 10 live records, max revision 301, 0 malformed, 0 duplicate, 0 repaired), "created a new host-state store". Nothing after that for 5 minutes, and no crash, panic, IOMMU fault or UBSAN line. `insmod` returned at once, so probe finished. In the driver, the warm registration is sent in probe and a settle timer then logs either `attach: N endpoints advertised` or `attach: ... no endpoint advertised` within about 3 seconds plus message idle time. Neither line appeared. That means either the timer kept restarting (messages kept arriving) or it did not run. Which one is not known. The check run was cut off by its caller during the poll, so the diag attributes were never read.

What this proves: the device tree, DART, profile choice and the read-only APFS parse work on this Mac, and the load is safe. It does not prove that the SEP answered. **Update: see the next section, the silence has a cause in my test DTB.**

**Changes to the scripts after the window** (carried from the coordinator's fixes plus mine): run as the user, not with sudo (guard added); paths from `UHOME`; the module is loaded from `/lib/modules/.../touchid-test/` (SELinux blocks modules in the home folder; the check installs it if missing); `touchid-boot.sh` builds the SEP-only DTB by default and `--camera` is opt-in and marked do-not-use; the camera log match no longer hits `disp`; the dry load now starts a detached observer that records the kernel log, diag attributes, `/dev/sep*` and hwrng at 1 to 240 seconds into a log file, so a killed caller loses nothing; `xarm_trace=1` is added (opcode and status only, no payload or key material); a PARTIAL verdict exists for "profile and xART fine, no attach line".

**Next step, one more test boot (about 12 minutes):** same plan, SEP only (camera filter stays 0), with the observer and trace above. Needs the user's go and the same recovery readiness. Because the registration is one-shot, the current normal boot cannot retry it.

## Second test boot (SEP only, 12:31) and the cause of the silence (offline analysis, 2026-10-27)

The second boot gave the same result: the same eight `apple_sep` lines, then nothing for 240 s. `xarm_trace=1` printed no trace line, so no mailbox message went out or came in. No `/dev/sep*`, hwrng `none`. The observer found no diag directory.

**Cause (found in the source, not by a test): my test DTB left the SEP mailbox node disabled.** The driver enables only the SEP node and its DART (`enable_sep_and_dart` in `dt.rs`). The M3 Air tree has the mailbox node enabled by default. I copied the `status = "disabled"` line from the t6030 style and the mailbox stayed off. Chain of events:
1. `Mailbox::new_byname` calls `apple_mbox_get_byname`, which calls `of_find_device_by_node` on the mailbox node.
2. A disabled node has no platform device, so it returns `-EPROBE_DEFER`.
3. The driver core prints nothing for `-EPROBE_DEFER`. The module load returns at once, and the probe waits for a mailbox that never appears.
4. This fits every observation: the xART line is printed before the mailbox lookup, and nothing after it runs (no registration message, no settle timer, no attach line, no diag directory, no trace line).

This is not the shared-memory layout. The suspicion about firmware 26.x versus older firmware stays open, but it cannot be judged until a registration is actually sent.

**What changed:**
- `make-window-dtb.py` no longer disables the mailbox node (54 lines added, 0 removed; SEP node and DART stay disabled).
- `touchid-boot.sh` stops if the built DTB has a disabled or missing mailbox node.
- `touchid-check.sh` has a new part 1b: the SEP mailbox platform device must exist and be bound. It runs before the load, so this bug shows up without loading the module. Part 5 is skipped when 1b fails. The observer and the verdict now also read `devices_deferred`, so a deferred probe is reported by name.
- `--dry` passes on the normal boot with the new DTB. Part 1b correctly FAILs on a normal boot.

**Risk of the fix:** the mailbox node is now enabled at boot, so `apple-mailbox` probes it. Its probe only maps registers and requests four interrupts with `IRQF_NO_AUTOEN`; the interrupts stay off until the driver starts the channel. The M3 Air tree does the same. m1n1 has a comment that querying this mailbox before the OS desynchronises the iBoot warm registration, so the first test boot must also show that the SEP still answers.

**What a third test boot needs** (about 12 minutes, one reboot, same recovery readiness):
1. The user's go. The module file is unchanged (same hash), so nothing new is installed. Only the DTB in `boot.bin.sep` changes.
2. `~/window/touchid-boot.sh` (as the user), reboot, `~/window/touchid-check.sh --no-camera`, then read `logs/sep-observe-*.log`.
3. Pass criteria in order: part 1 and 1b PASS (before the load); then at the dry load, a `SEP platform profile` line, then `attach: N endpoints advertised`. That last line is new information. If it says no endpoint advertised, the registration was sent and the SEP stayed silent: then the profile fields (shared-memory layout and size for this firmware) are the next suspect.
4. After the load, no suspend and no sleep until the next reboot. The registration is one-shot.

## Third test boot (13:10): the SEP answers (analysis 2026-10-27, read-only)

Result by the coordinator: overall PASS. Parts 1, 1b (mailbox bound to `apple-mailbox`), 2, 4 and 5 PASS. The attach line came 5 s after the load. The cause of the earlier silence is confirmed: the disabled mailbox node.

**What the kernel log and the diag attributes show** (read with no write and no open of `/dev/sep-bio`):
- Attributes: `attach=attached`, `endpoints=12`, `keystore=open`, `boot=warm`, `protocol=variant5`, `xart=disabled`, `profile=T6030/J516s`, `sensor=unbound`, `touchid=unknown`, `keybag=unknown`.
- The registration of the shared memory worked: the SEP sent its endpoint list within a second. This means the profile's shared-memory layout, copied from the M3 Air recipe, is accepted by this firmware. The worry about firmware 26.x versus older firmware is not confirmed for this step.
- All 12 endpoints match the Asahi SEP notes: control (0x00), sbio (0x08, biometrics), scrd (0x0a, credentials), sse (0x0c), hdcp (0x0e), xars (0x10) and xarm (0x13, the xART manager), sks (0x12, key store), hibe (0x14, hibernation), pnon (0x15, boot policy), skdl (0x17, key derivation) and stac (0x18, trusted accessory).
- xART exchange: the enclave fetched its records through xarm (ops 0x13, 0x00, 0x05 several times, 0x07), all with status 0. No "refused the enclave's write" line appeared, so the enclave did not try to write in this boot. The key store endpoint opened.
- The driver also registered a `trusted` key source `applesep`. Nothing sealed a key.

**hwrng EIO is not a transport fault.** In `get_entropy_word` a lost message would give `ETIMEDOUT` and a stopped driver `ECANCELED`. The only `EIO` in that path is the driver's own check that all four entropy words were zero (`survey_hwrng`). So the SEP answered the `GET_ENTROPY` request every time, with zero data, five attempts of four words. The source says the same happened on the M1 with firmware 13.5. The driver already refuses to use the SEP for random numbers: Touch ID tokens use the kernel RNG (`mint_token_bytes`). So the SEP random source being absent does not block Touch ID. It only means `/dev/hwrng` stays without an SEP source (`rng_current` is `none`). Possible reasons (not tested): this firmware does not implement op 0x36 for this caller, or it returns the word elsewhere in the reply. Low priority.

**Correction to my first research (touchid.md):** I wrote that no libfprint backend exists. The same project ships one: `patches/libfprint-1.94.100-apple-sep.patch`, a Fedora spec (`packaging/fedora/aurora-sep.spec`), the `aurora-touchid` setup, `fprintd` and greeter units, and an installer. Our Fedora has libfprint 1.94.100 and fprintd 1.94.5, the version the patch targets. I have not built or tried any of it.

**What stands between this state and a real Touch ID read**

| Stage | What it needs | Writes? | Risk |
|---|---|---|---|
| 3a, sensor only (read-only) | A J516S sensor block in the device tree: power on the NUB GPIO (the ADT names pin 33, same controller kind as the M3 Air's pin 29), SPI mode (unverified), SPI pin mux (not in the ADT; try without), `firmware-name` for the per-Mac calibration file. The calibration file is carved from the iBoot system container by `extract-mesa-calibration.py` (a raw read of that partition, root, then a file under `/lib/firmware/apple/`). Not yet checked that this Mac's container holds one. Then one open of `/dev/sep-bio` with writes off: the driver enables the SPI bus and the sensor, registers the biometric buffers with the SEP, then stops with "no persisted identity keybag" (ENOENT). No capture is possible (`EROFS`). | No xART write, no keybag. A root-only host-state file already exists | Low. A wrong SPI mode or pin shows as a sensor read error in the log. The sensor power GPIO polarity is copied from the Air (unverified) |
| 3b, enrol and verify | `xart_writes=1` and `provision_keybag=1`, plus **`xart_guard=1` or 2 set explicitly** (in this tree the guard is off by default, which lets the enclave rewrite any OS's session record). The sensor stage working. The patched libfprint and `fprintd` for a real desktop use. A raw copy of the iBoot system container first. | Yes: xART records in the shared `.gl` extent and a Linux identity keybag | High. The driver's own text says a refused save has left the enclave unresponsive until reboot |

**Backup is smaller than I wrote before.** The xART store is one 6 MB file inside the iBoot system container, which is one 500 MB partition (`iBootSystemContainer`). A raw copy of that one partition, with a checksum, is a full undo for the xART state. I wrote earlier that all APFS partitions needed a copy. That is more than needed for this step.

**Recommendation:** do stage 3a next, but only after (1) the calibration file check and the J516S sensor block are prepared offline, and (2) the user agrees to one more test boot. Do not start stage 3b until 3a works and the user has a raw copy of the container. Stage 3b also needs a decision about macOS: it shares the gigalocker.

## Stage 3a: sensor-only open, prepared offline (2026-10-27, not yet booted)

**Goal.** One open of `/dev/sep-bio` with xART writes off and no keybag creation. The driver then brings up the SPI bus, takes the sensor power line, registers the biometric buffers with the enclave, and stops with "no persisted identity keybag" (ENOENT). That ENOENT is the expected end state. No capture is possible (EROFS), and the driver refuses a second open until the next reboot.

**What 3a does not prove.** The sensor identifier read (the proof that SPI mode, pins and power are right) sits in the driver's bring-up, and bring-up runs only after a keybag was recovered. So 3a shows that the sensor node binds, the power line is taken and the enclave accepts the SBIO setup. It does not show that the sensor answers on the bus. That proof needs stage 3b, or a small diagnostic option in the driver that reads only the sensor status (not built; it would be a module rebuild, no kernel change).

**What was prepared.** Scripts live in the private window folder, copies in `~/window` on the M3 (previous versions kept as `*.pre-3a`).

| Piece | What it does |
|---|---|
| `make-window-dtb.py --sensor` | Adds four lines to the sensor node: power line (a GPIO on the always-on "nub" controller, taken from the ADT entry `function-mesa_pwr`), the two chip-select timing values, and the calibration file name. The SPI controller and the node stay disabled. The driver enables them at the open. |
| `touchid-boot.sh --sensor` | Same checks as before, plus: the four lines exist, the power line points at the nub controller and a pin inside its range, SPI controller and node still disabled, nothing removed from the base DTB. `--dry` run on the M3 passed (58 lines added, 0 removed; every other DTB equal to base). |
| `touchid-calib.sh` | Read-only carve of the per-Mac calibration out of the iBoot system container into the user's `touchid/` folder (mode 0600). It prints PASS with size and type (FSCl or FSC2), never the hash. `--install` copies it to the firmware folder. Not needed for 3a, needed from 3b. |
| `touchid-check.sh` part 6 | Runs when the boot was armed with `--sensor`. Loads the module with `sensor_trace=1`, opens `/dev/sep-bio` once, reads the kernel log. |

**Part 6 verdicts.** PASS: open fails with ENOENT, log has the "no persisted identity keybag" line, SBIO accepted, sensor bound, power line taken, no oops. PARTIAL: ENOENT and SBIO fine but the sensor did not bind or has no power line (fix the sensor DT block, test again). FAIL: any other errno, SBIO refused, a host-state error, or an oops.

**Unverified in the sensor block.** SPI mode (the M3 Air value, `spi-cpha`, is used; M1 Pro and M2 Pro use `spi-cpol`; the module has a `sensor_spi_mode` override for a later test), SPI pin mux (the M3 Air DT has none, so none here), power line polarity (active high, as on every other board), no data-ready interrupt (the driver polls).

**Tested offline.** DTB build with and without `--sensor` (exact 4-line difference). DTB check logic against a good case and a case with the node enabled (caught). Calibration script against a synthetic container in a Linux container (PASS, and FAIL for a container with no calibration). Part 6 verdict logic against stubbed kernel logs (PASS, PARTIAL, FAIL). Dry run on the M3.

## Gates before step A2 (all must be true)

1. The user says go in the session that owns reboots. The coordinator pauses the other M3 sessions first.
2. A snapper snapshot of the Linux root exists (the maintenance-window plan already requires it).
3. The M3 is on AC power with more than 50 percent battery.
4. The user knows how to reach the boot picker (hold the power button at power on) and has the macOS password at hand for the recovery step F5.
5. `m3gpu-boot status` shows `boot.bin` equal to `boot.bin.stageE` and a present `boot.bin.stock`. Write the hashes down.
6. Free space on the ESP is at least 40 MB (`make-bootbin.sh` prints it).

## Route A: staged `boot.bin`, no proxy (recommended)

Each step lists who acts, the effect, and what stops the plan.

| Step | Who | What it does | Stop if |
|---|---|---|---|
| A0 | Claude | Re-run `m3gpu-boot status`. Compare hashes with gate 5. Check that the installed J516S dtb still has sha256 starting `18baac96`. | Any hash differs. Ask first. |
| A1 | Claude, no root | Build `inst-plus-sep.dtb` with `make-test-dtb.py` from the installed dtb. Decompile both and diff: expect added lines only. Put the DTB in a scratch folder with a copy of all other `t6*` and `t81*` dtbs from `/boot/dtb-7.2.11-m3gpu+/apple/`. | The diff shows any removed line. |
| A1b | Claude, no root | Build `apple_sep.ko` out of tree from a scratch copy of `drivers/soc/apple` plus `t6030-profile.patch`, against the existing build folder, `nice -n 19`, two jobs. Check `modinfo` vermagic equals `7.2.11-m3gpu+`. **Done 2026-10-27, see the result section.** The dry run `make -n` first confirmed that nothing outside the scratch folder is written. | The build wants to rebuild kernel core files, or the vermagic differs. Then ask the GPU session for a module in its next kernel build instead. |
| A2 | User types the sudo password | `make-bootbin.sh sep <m1n1-aca1258.bin from /usr/local/lib/m3gpu> <scratch dtb folder> chosen.asahi,t6030-gpu=1 chosen.asahi,t6030-dcp=1 chosen.asahi,t6030-dcpext=1`. It writes only `boot.bin.sep`. The three options are the stage E options. | The output lacks a sha256 line, or the file is smaller than `boot.bin.stageE`. Delete `boot.bin.sep`. |
| A3 | Claude | Compare `boot.bin.sep` and `boot.bin.stageE` byte ranges. Only the J516S dtb region may differ. Write both hashes into the private notes. | More than the DTB differs. |
| A4 | Claude | Run `pre-reboot-check.sh` and `health-check.sh`. Report. | Any check fails. |
| A5 | User types the sudo password | `use-bootbin.sh sep`. `boot.bin` becomes `boot.bin.sep`. | Hash after copy differs from `boot.bin.sep`. Run F3. |
| A6 | User says go | One reboot into the current default kernel (`7.2.11-m3gpu+`). The same `reboot` that the maintenance window plans can carry this change, so the user reboots once, not twice. | See F4 and F5. |
| A7 | Claude | After the boot, read only: the SEP node exists and is disabled, `iboot-manifest` and `local-policy-manifest` exist with the lengths of the ADT `ibot` and `lpol`, the `sep-firmware` reserved region exists, `uname -r` is unchanged, GPU and display work as before. | Properties missing: the m1n1 alias path failed. Roll back with F4. |
| A8 | User types the sudo password | `insmod <scratch>/apple_sep.ko xart_writes=0 provision_keybag=0`. Do not install the module. Do not open `/dev/sep-bio`. | The machine freezes: F7. |
| A9 | Claude | Read `dmesg` and `/sys/bus/platform/devices/*.sep/diag/*`. Save to the private notes. Do not `rmmod`. | Never run `rmmod`: the SEP may still hold the registration. A reboot clears it. |
| A10 | User says go | Roll back to the known `boot.bin`: `m3gpu-boot use-stageE`, then reboot. Optionally boot macOS once (`agx-os macos-once`) and check that the macOS login and Touch ID still work (xART was read-only). | |

### Expected result at A9, and what each outcome means

| `dmesg` shows | Meaning | Next |
|---|---|---|
| `SEP platform profile: T6030/J516s`, `xART: ... writes disabled`, SEP DART changeset applied, SEP node enabled, then endpoint discovery lines | Best case. DT, profile, manifests and mailbox work | Record endpoints and the sensor id read if the driver prints it. Decide Stage 3 separately |
| `refusing to attach: device-tree property ... missing` | A7 should have caught this. The alias or m1n1 step did not run | Fix the alias. Nothing reached the SEP |
| `xART gigalocker ... unavailable or invalid` | The read-only APFS parse refused this container layout | Fails before SEP contact. The partition resize on 2026-10-26 may be the cause. Report the exact error |
| `no profile` or `ENODEV` from `detect()` | The profile patch was not in the module | Rebuild |
| Mailbox timeout, no endpoint list | Wrong interrupt order or address in the DT | Swap the interrupt order guess, redo from A1. Safe, SEP is not written |
| The machine hangs | See F7 | |

## Rollback by failure point

| Point | State | Rollback |
|---|---|---|
| F1: A1 or A1b fails | Nothing outside the scratch folder changed | Delete the scratch folder |
| F2: A2 or A3 fails | `boot.bin.sep` exists, `boot.bin` untouched | `sudo rm /boot/efi/m1n1/boot.bin.sep` |
| F3: after A5, before reboot | `boot.bin` is the sep file | `m3gpu-boot use-stageE` (no password). Check the hash equals gate 5 |
| F4: Linux boots, something is wrong | `boot.bin` is the sep file | `m3gpu-boot use-stageE`, reboot. Same for any unexpected behaviour from the alias or the reserved region |
| F5: m1n1 stops, no network after 3 minutes, screen shows m1n1 text or stays black | m1n1 `bail` or a bad payload. ESP still holds `boot.bin.stageE`, `.stock`, `.old` | Hold the power button about 10 seconds to force off. Power on and hold the power button to open the boot picker. Boot **macOS**. In macOS Terminal: `diskutil list` to find the 500 MB EFI partition on the internal disk (confirm the identifier, do not guess), `sudo diskutil mount <that partition>`, copy `m1n1/boot.bin.stageE` over `m1n1/boot.bin`, check with `shasum -a 256` against gate 5, `diskutil unmount`, then boot Linux. The user types the macOS password |
| F6: neither Linux nor macOS boots | Unlikely: stage 1 lives in the APFS container and the picker does not depend on the ESP file | DFU restore, last resort (kit and steps in `m3-restore/`) |
| F7: the machine freezes after A8 | The module touched a bad address or the SEP | Force off, power on. The module is not installed, so it does not load again. `boot.bin` is still the sep file. Run F4. Delete the host state file the driver created only if no sealed blob matters (it holds none yet) |

## Route B: m1n1 proxy over USB (not recommended)

Use it only if the user wants a RAM-only boot (no ESP file written) or a direct ADT read to prove `SEPFW`. Details from the Asahi m1n1 user guide (read 2026-10-27; not tried on this Mac):

1. **Policy change (user only).** In the recovery environment on the Linux stub volume: `csrutil disable` and `nvram boot-args=-v`. The guide says stage 1 only opens the proxy when both are set. This lowers the stub's local security policy, and the local policy hash is data the SEP sees. It changes a security setting, so it needs the user's own go. I do not do it.
2. **Host.** A USB-C to USB-A cable (C end on the Mac) into a Thunderbolt port. The host needs Python with `pyserial` and `construct` (this Mac lacks `pyserial`: the import check failed) and the m1n1 `proxyclient` folder (copy it from the M3 source tree, which holds the fork).
3. **Boot.** Power on with the cable attached. Stage 1 waits about 5 seconds for a proxy. On macOS the host sees `/dev/cu.usbmodemP_01` (proxy) and `P_03` (virtual UART). Set `M1N1DEVICE` to the first.
4. **Use.** Read the ADT (`from m1n1.setup import *`, then `print(u.adt["/chosen/memory-map"])` and look for `SEPFW`). Or run `proxyclient/tools/chainload.py -r <test boot.bin>` to start a test m1n1 from RAM. Nothing is written to the ESP.
5. **Rollback.** Power cycle. Then in the recovery environment: `nvram boot-args=` and `csrutil enable`. At the security prompt do **not** choose full security: the guide says that uninstalls m1n1.

Why not first choice: it needs the policy change and a cable, takes the M3 off the network for the whole session so every other session pauses, and the host lacks the Python packages. Route A has a tested rollback and needs none of that.

## Not verified

- That the module loads and runs. It builds and its symbols resolve, but it was never loaded.
- That stage 1 uses the `SEPFW` check on this Mac (see "Decision").
- The SPI mode, `spi2` pin mux, key store settings (see touchid.md, Stage 1 status). None of them can hurt the dry load. They only decide whether a later sensor read works.
- The recovery steps in F5 and Route B come from general macOS and Asahi knowledge and the guide above. They have not been run on this Mac.
- Whether the maintenance-window reboot can carry A6 too is the coordinator's and the user's call.

## Sources (read 2026-10-27)

- Asahi m1n1 user guide: <https://asahilinux.org/docs/sw/m1n1-user-guide/>
- m1n1 `chainload.c` at v1.6.1: <https://raw.githubusercontent.com/AsahiLinux/m1n1/v1.6.1/src/chainload.c>
- On the M3: m1n1 source (`src/kboot.c`, `src/chainload.c`, `src/main.c`), `/usr/bin/update-m1n1`, `/etc/sysconfig/update-m1n1`, the `m3gpu` scripts (`m3gpu-boot`, `make-bootbin.sh`, `use-bootbin.sh`), driver source (`shmem.rs`, `store.rs`, `xart_store.rs`).
