# Touch ID Stage 2 plan: dry load of `apple_sep`, rollback, and the m1n1 proxy question

Date: 2026-10-27. Status: **plan only**. No reboot, no sudo, no write to the ESP or to the M3 boot chain was done. Part of [touchid.md](touchid.md). The values (addresses, interrupts, blobs) stay in the private notes folder. This file has none.

## Decision in one page

- **The m1n1 proxy is not needed.** Two routes can reach the dry load. Route A uses the `boot.bin` staging that this M3 already uses (stage C, D, E toggled many times on 2026-10-26). Route B uses the m1n1 proxy over USB. Route A needs no security policy change and no cable. Route B needs both.
- **Recommended: Route A.** It writes one new file to the ESP, switches `boot.bin` with the existing script, and has a rollback by one command, and a second rollback from macOS if the boot fails.
- **The `SEPFW` risk is now low.** The stock stage 1 m1n1 (v1.6.1) chainloads our stage 2 and its `chainload.c` returns an error when `/chosen/memory-map` has no `SEPFW` (read upstream source 2026-10-27). Stage 2 is running, so `SEPFW` was there. I have not proved that stage 1 takes that code path on this Mac, so keep the macOS recovery step ready.
- **Nothing here enrols a finger.** The dry load runs with `xart_writes=0 provision_keybag=0` and never opens `/dev/sep-bio`.

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
| A1b | Claude, no root | Build `apple_sep.ko` out of tree from a scratch copy of `drivers/soc/apple` plus `t6030-profile.patch`, against the existing build folder, `nice -n 19`, two jobs. Check `modinfo` vermagic equals `7.2.11-m3gpu+`. **Not tried yet.** First run `make -n` and confirm it would not touch the shared build folder. | The build wants to rebuild kernel core files, or the vermagic differs. Then ask the GPU session for a module in its next kernel build instead. |
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
