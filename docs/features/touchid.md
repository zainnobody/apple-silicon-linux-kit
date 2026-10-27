# Touch ID on the MacBook Pro 16-inch M3 Pro (t6030, J516S)

Date: 2026-10-26. Kernel on the machine: `7.2.11-m3gpu+` (private GPU build, source `~/m3gpu/src/linux`, head `0e1f46661376`, 2026-10-19). Every machine check was read-only. Nothing on the M3 was changed, loaded, installed or rebooted.

Question: what does Touch ID need on this Mac, and is there a safe path?

## Short answer

- Touch ID does not work and no stock Asahi code exists for it. Asahi lists SEP and Touch ID as TBA on M3 ("no active work").
- The kernel source on the M3 does hold a large out-of-tree SEP and Touch ID driver (`apple_sep`, Rust, 22k lines in `drivers/soc/apple/`). It is not Asahi code. It has no profile for t6030, so it would refuse to start here (`ENODEV`).
- Four things are missing: a `t6030` device tree node set, a driver profile for t6030, bootloader (m1n1) handoff data, and a userspace bridge to `fprintd`.
- The driver writes to the macOS system container by default. That makes a try-out risky on a machine that still has macOS.
- Recommendation: **wait**. Do not build a staged experiment on the internal disk now. A safe experiment plan is in "Staged experiment" below, for use only if the user wants it later and has a backup.

## What exists

### Upstream Asahi (read 2026-10-26)

- Feature page: SEP = TBA on M3, M3 Pro, M3 Max and M3 Ultra. Touch ID = TBA on the MacBook Pro 14/16-inch (late 2023). The page defines TBA as "active work on this feature is not being undertaken at this time". <https://asahilinux.org/docs/platform/feature-support/m3/> (read 2026-10-26; the page shows no update date).
- SEP notes: community research notes, marked "messy". They describe the mailbox protocol, endpoints (SBIO 0x08 is biometric authentication, SKS 0x12 is the key store, xART 0x13) and the boot flow. They describe no working driver. They warn that a malformed IMG4 panics the SEP until the machine resets. <https://asahilinux.org/docs/hw/soc/sep/> (read 2026-10-26; cites macOS 13.5 as of 2024-11-13).
- Web searches for `sep.rs`, `bio.rs`, `apple,sep` bindings, an Asahi SEP patch, and a libfprint backend for Apple Silicon found nothing upstream on 2026-10-26. The M3 device tree series on the kernel lists (Janne Grunau, t8122 in 2026-03, t6030/t6031 in 2026-07) do not mention SEP: <https://lkml.iu.edu/2607.3/01647.html> (read through search result 2026-10-26, page not opened).
- Conclusion: no upstream Asahi or mainline work for Touch ID exists on any M3 chip. I could not search the private mailing lists beyond these public mirrors.

### Out-of-tree driver in the M3 kernel source

The tree (`origin` is a fork named siliconforest-linux, branch merged from "integration/pr363-complete-20261019") carries a complete driver set. The driver files carry a 2026 copyright by their own authors. Its docs name two project forks, `aurora-linux` and `omacom/linux-aurora`. This is a separate effort from Asahi.

- Code: `drivers/soc/apple/sep.rs` (2512 lines), `bio.rs` (`/dev/sep-bio` enrol and match), `sbio.rs`, `sks.rs`, `xart_*.rs`, `keybag*.rs`, `trusted.rs`, `hwrng.rs`, and others.
- Kconfig `APPLE_SEP`: Touch ID over `/dev/sep-bio`, SEP hardware RNG, and a `trusted` key source for `keyctl`. Default is `m` on Apple. Our staged config sets it off (`# CONFIG_APPLE_SEP is not set`, checked on the M3 and in `agx-linux-kit` docs).
- Dependencies are already met in our config: `RUST`, `RUST_APPLE_MAILBOX`, `TRUSTED_KEYS`, `OF_DYNAMIC`, `CRYPTO_ECDH`, `CRYPTO_GCM`, `RUST_FW_LOADER_ABSTRACTIONS`.
- Device tree: `apple,sep` nodes exist in `t600x-die0`, `t602x-die0`, `t8103`, `t8112`, `t8122` and `t8140` dtsi files. **`t6030.dtsi` and `t6031.dtsi` have none.** The binding is `Documentation/devicetree/bindings/soc/apple/apple,sep.yaml`.
- Supported machines in the driver profile (`profile.rs`): M1 MacBook Air (T8103/J313), M1 Pro 16-inch (T6000/J316s), M2 Pro 14-inch (T6020/J414s, hardware verified), M2 Max, M3 MacBook Air (T8122, J613 and J615 only), M2 Air (T8112), and T8140. Any other SoC is refused: "An unsupported SoC is refused rather than guessed at". t6030 is not in the list.
- Design: the driver does not boot the SEP. It attaches to the SEP that iBoot already started ("warm attach"), talks over the ASC mailbox and a SEP DART, and reads the machine xART gigalocker directly from the iBoot system container through read-only APFS parsing.
- Known project issue: after a content-changing identity-bag save and a reboot, sealed blobs can become permanently unreadable. The project closed that issue as "not planned" and archived the repository on 2026-10-18. Work moved to `omacom/linux-aurora`. <https://github.com/iconidentify/aurora-linux/issues/31> (read 2026-10-26). <https://github.com/iconidentify/aurora-linux> (read 2026-10-26).
- Source of the doc facts above: `Documentation/security/keys/apple-sep.rst`, `Documentation/ABI/testing/sysfs-driver-apple-sep`, `drivers/soc/apple/Kconfig`, `profile.rs`, `dt.rs`, read on the M3 on 2026-10-26.

### Userspace

- `fprintd 1.94.5` and `libfprint 1.94.100` are installed (Fedora packages). `fprintd-enroll` exists. They have no Apple SEP backend, so they find no device.
- The driver comments say its `/dev/sep-bio` interface is shaped for libfprint (enrol stages, touch counts). I found no libfprint merge request or out-of-tree libfprint driver for it (search of gitlab.freedesktop.org/libfprint and the web, 2026-10-26). The bridge would have to be written.
- Sealing keys with `keyctl` works at the kernel level in the driver, but the driver docs say there is no login keyring integration. Unsealing does not need a fingerprint.

## What this machine has, from read-only checks (2026-10-26)

| Item | Result |
|---|---|
| Machine id | `apple,j516s`, `apple,t6030` |
| `CONFIG_APPLE_SEP` | not set |
| Dependencies | `RUST_APPLE_MAILBOX=y`, `TRUSTED_KEYS=y`, `OF_DYNAMIC=y`, `CRYPTO_ECDH=y`, `CRYPTO_GCM=y`, `RUST_FW_LOADER_ABSTRACTIONS=y` |
| `/sys/firmware/devicetree` | no node with `apple,sep`, `apple-sep` mailbox, SEP DART or `apple,mesa-fingerprint` (full-tree string search, no match) |
| `ps_sep` power domain | defined in `t6030-pmgr.dtsi` (`power-controller@c00`, label `sep`). Nothing uses it |
| Mailboxes in the DT | 13 `mbox` nodes (SIO, SMC, AOP, DCP and others). None is labelled SEP. The SEP mailbox address for t6030 is not in our tree |
| `spi@289104000` | bound, holds only an SPI NOR flash. No fingerprint sensor node |
| `chosen` node | no `iboot-manifest` and no `local-policy-manifest` property (the binding says the bootloader adds them; the SEP needs them to open secure storage) |
| Loaded modules | no SEP module. Mailbox and RTKit helper modules are loaded for other devices |
| `/dev/hwrng` | present, current source `none` |
| `dmesg` | no SEP or Touch ID lines (non-root read) |
| `fprintd`, `libfprint` | installed, no Apple backend |
| Firmware versions in the DT | os-fw 14.7, system-fw 15.6 (the driver's profile logic depends on this pair for the key store format) |
| Disk | APFS partitions remain (`Apple Silicon boot` 500 MB, APFS 46.6 GB, APFS 2.3 GB, recovery 5 GB). This is the container the driver would write to |

## What is missing

1. **Device tree.** Needs `sep` (the SEP block), `sep_mbox` (ASC mailbox with four interrupts), `sep_dart` (SEP DART with a restricted DMA window) and a `ps_sep` link. The t8122 nodes in the tree are a template (SEP, mailbox at SEP plus 0x8000, DART). The t6030 addresses and interrupt numbers must come from the Apple device tree (ADT) of this Mac. Guessing them is not safe. Wrong addresses in a DT can hang the boot.
2. **Sensor description.** The Touch ID sensor sits on an SPI bus with GPIOs. The driver can create the node at a fixed address, but the J516S address is unknown. Only J613 and J615 ADTs were read by the driver authors.
3. **Driver profile.** `profile.rs::detect()` has no t6030 entry. Needed: DART window, shared memory geometry, key store variant, keybag encoding, and the `xart_guard` setting for this SoC and for firmware 15.6. These come from tracing macOS on this Mac, which nobody has done.
4. **Bootloader data.** The SEP needs `iboot-manifest` and `local-policy-manifest` in `/chosen`. Our m1n1 does not pass them. Changing m1n1 is a boot-chain change.
5. **Firmware.** No Linux-side SEP firmware is needed. The SEP runs its own signed firmware that iBoot starts. We cannot replace it.
6. **Userspace.** A libfprint driver for `/dev/sep-bio`, a PAM path (`pam_fprintd`), and a policy for the `sudo` and KDE prompts.

## Risks

- **The driver writes to the macOS container.** `xart_writes` and `provision_keybag` default to 1. The driver then writes xART records into the shared APFS system container on the internal disk and creates a Linux identity keybag. The SEP saves anti-replay state after every match, so Touch ID cannot work read-only (the Kconfig text says enrol and verify are refused when writes are off). A wrong write can damage secure storage that macOS uses (FileVault and login keys). The project notes that on the M1 Pro 16-inch, creating the keybag rewrites a pre-Linux session record, and the driver's guard refuses it unless `xart_guard=0`.
- **Secrets cannot be recovered.** The SEP holds the keys. The driver stores a secret identity bag under `/var/lib/aurora-sep-*.bin`. Losing or regenerating these orphans every sealed blob. The upstream project's own issue says blobs can become unreadable after a reboot and the fix was declined.
- **A wrong driver cannot be undone by config.** Removing the module after a bad xART write does not roll back the write. A Btrfs snapshot does not cover the APFS container. Only a raw copy of the APFS partitions taken before the test can undo it, and a macOS Recovery repair may still be needed.
- **A SEP panic needs a reset.** The Asahi notes say a bad IMG4 panics the SEP until reset. This driver does not send IMG4 (warm attach), but a wrong mailbox or DART setup has no proven safe failure mode on t6030.
- **Wrong DT values can hang or reset the boot.** A bad DART or mailbox address on a machine whose only OS is on that disk needs a boot entry and USB recovery to fix.
- **No security gain.** The key source does not require a fingerprint to unseal (the driver docs say so). Fingerprint login would be a convenience, not a lock, until userspace policy is added.
- **Unknown maintenance.** The most active upstream of the driver archived the repository on 2026-10-18. The successor and its state were not readable (the page showed only a generic kernel README).
- **Identifiers.** The ADT of this Mac holds the numbers the port needs. Keep those out of anything shared.

## Effort

| Step | Work | Size |
|---|---|---|
| ADT extraction for SEP, SEP mailbox, SEP DART, sensor SPI and GPIOs on J516S | read only, needs the raw ADT from m1n1 or macOS | small to medium |
| `t6030` device tree nodes (with `status = "disabled"`, enabled by a changeset as in t8122) | edit and build a DTB | small |
| `profile.rs` T6030 profile, with a macOS trace for the key store variant on os-fw 14.7 and system-fw 15.6 | reverse engineering, needs macOS tracing tools | large |
| m1n1 change for the two manifests | boot-chain change | medium |
| libfprint driver and `fprintd` test | new C driver | medium to large |
| Safe test rig (raw backup of APFS partitions, recovery path) | prepare | medium |

Estimate: a first `apple_sep` probe that only attaches and reads the endpoint list is days of work. A Touch ID enrol and login is weeks, with the main risk in the profile.

## Recommendation

Wait for upstream. Reasons:

1. Asahi marks the feature TBA and no t6030 work exists anywhere I could read.
2. The only driver is out of tree, was never run on t6030, and refuses this SoC by design.
3. The driver writes to a container shared with macOS, and the damage cannot be undone with a config change or a Btrfs snapshot.
4. Touch ID is a convenience here. Password login works and the user types all passwords.

Revisit when one of these happens: Asahi moves SEP from TBA to WIP for M3; an `apple,sep` node for t6030 lands in a kernel list or the Asahi tree; the out-of-tree driver gains a T6030 profile with a hardware-verified report.

## Staged experiment (only if the user asks later)

**Read "Stage 1 status" below first: the device tree is shared by all boot entries (one `boot.bin`), so steps 2 and 3 also need a `boot.bin` rebuild with a tested rollback to `boot.bin.old`. A second boot entry covers only the kernel.** Use this only with the user's own go in the session that owns the kernel. Do not run any step before then. Stop at the first failure.

0. **Backup first.** From a live USB or macOS Recovery, make a raw image of the APFS partitions (`Apple Silicon boot`, `Apple APFS` 46.6 GB, 2.3 GB, `recovery`) to an external disk. Verify a checksum. Keep the m1n1 stage 1 and stage 2 files and the current boot entry. Rollback for every step below starts here.
1. **Read-only ADT work (no risk).** Get the ADT of this Mac (macOS `ioreg` or the m1n1 `adt` dump). Keep the SEP, mailbox, DART, sensor SPI and GPIO values in a private location outside the repo. Do not copy them into docs.
2. **Build a test kernel, not the default one.** Add t6030 nodes (SEP disabled by default) and a T6030 profile that stops after the endpoint list. Build `CONFIG_APPLE_SEP=m` as a module only. Install it as a second boot entry. The default entry stays the current `7.2.11-m3gpu+`.
3. **Dry load with writes off.** Boot the test entry. Load the module as `apple_sep xart_writes=0 provision_keybag=0` (user's go, user types the sudo password). Expected result: it attaches, lists endpoints, shows the profile in `/sys/bus/platform/devices/*.sep/diag/`, and refuses Touch ID. If it fails or the machine hangs, power off and boot the default entry. Nothing was written.
4. **Stop here for the first report.** A clean step 3 proves the DT and profile. Do not enable writes in the same session.
5. **Writes on only after a second backup and a second go.** Run `xart_writes=1`, with `xart_guard` left at its default, and try one enrol. If the result is anything but clean, restore the raw APFS images from step 0.
6. **Userspace last.** Write the libfprint backend only after step 5 is stable for several boots.

Rollback summary: remove the test boot entry, restore the default entry, unload and blacklist `apple_sep`, delete `/var/lib/aurora-sep-*.bin` only if no sealed blob matters, and restore the raw APFS images if step 5 ran.

## Stage 1 status (2026-10-26, offline only)

Done, nothing installed, loaded or rebooted. The files hold values from the private ADT dumps, so they live outside the repo (private, gitignored).

- The ADT of this Mac has the SEP, SEP DART, SEP mailbox and the Touch ID sensor on an SPI bus. The SEP block layout matches the M3 Air nodes. The SEP node reports that iBoot booted and loaded its firmware.
- A draft test device tree adds those nodes, all disabled, to the J516S tree. It compiles with `dtc` and adds no new warning. The `dt-validate` check was not run (no `dtschema` on the M3).
- A draft driver patch adds a `T6030/J516s` profile (the M3 Air recipe, guarded xART records) and limits it to the J516S board. `rustfmt` parses it. The full Rust build was not run, because the build directory is shared with the GPU session.
- Unverified: the SPI mode of the sensor, the spi2 pin mux, and the key store settings for firmware 15.6. Only the first matters for the dry load. The other two matter for enrol.
- **Manifest blob identified (read-only):** the driver needs `iboot-manifest` and `local-policy-manifest` on the SEP node. The m1n1 that is installed on the M3 already copies them from the ADT (`ibot` and `lpol` in `/chosen/boot-object-manifests`), but only when the device tree has an `/aliases/sep` entry. Our tree has none, so nothing is passed. The fix for this part is a device tree alias, not an m1n1 source change.
- **Correction to the staged plan:** device trees are not per boot entry. `update-m1n1` embeds all dtbs into one `boot.bin` on the ESP, so every kernel boots with the same DT. A second boot entry does not isolate the DT change. The rollback is the previous `boot.bin` (`boot.bin.old`), and it needs a recovery path ready. The `update-m1n1` rebuild is currently paused on the M3.
- **Open risk:** with the alias, m1n1 stops the boot if it cannot find the SEP firmware region (`SEPFW`) in the ADT. The macOS dumps do not show that entry, which does not prove it is absent. Checking needs the ADT read from m1n1 itself (USB proxy mode, one reboot) or a test `boot.bin`.
- Next: confirm `SEPFW` exists (m1n1 proxy read, needs a reboot and your go), then a kernel build with `APPLE_SEP=m` and the `boot.bin` rebuild with a tested rollback. Steps 2 and 3 of "Staged experiment" need this change: a second boot entry alone does not protect the DT.

## Maintenance window request (for the coordinator, 2026-10-27)

Nothing here runs until the coordinator sends the start signal and the user says go. No separate reboot is wanted. The reboot already planned for the maintenance window carries this change. Full detail and rollback: [touchid-stage2-plan.md](touchid-stage2-plan.md).

**The proxy read of the ADT is not part of the request.** The plan reaches the dry load without it (see the plan, "Decision in one page"). The exact proxy steps are below only so the coordinator and the user can choose it instead.

### What to schedule (route A, no cable, no policy change)

Before the window reboot (no reboot needed, about 15 minutes):
1. A0 to A4, no root: check the boot hashes, build the test DTB from the installed one, check that the diff only adds lines, check the module build (A1b), run the pre-reboot and health checks.
2. A2, user types the sudo password: build `boot.bin.sep` (a new file in the ESP, `boot.bin` untouched).
3. A5, user types the sudo password: `use-bootbin.sh sep`. This must be the last boot.bin change before the window reboot. It must come after the USB4 steps if those also need a clean state, so that a boot failure has only one new cause.

At the window reboot: the same single reboot. If the machine does not come back in 3 minutes, use rollback F5 in the plan (force off, boot macOS from the picker, copy `boot.bin.stageE` back, user types the macOS password).

After the reboot (about 10 minutes):
4. A7, read only: the manifests and the reserved region are in the device tree. If not, run `m3gpu-boot use-stageE` and stop.
5. A8 and A9, user types the sudo password: dry load with `xart_writes=0 provision_keybag=0`, read `dmesg` and the diag files. **Run this last in the window**: the module cannot be unloaded safely, so the SEP stays registered until the next reboot. No sleep tests and no suspend until then.
6. A10 without a reboot: `m3gpu-boot use-stageE` (no password) so the next boot goes back to the known `boot.bin`. The next natural reboot clears the loaded module.

Cost and risk added to the window: two typed sudo passwords before the reboot, one after, one extra failure mode (m1n1 stops on the new device tree, recovery F5 needs the macOS password). No finger is enrolled and no xART write is possible in this run.

### Route B steps, only if chosen instead (m1n1 proxy over USB, not tried on this Mac)

Source: Asahi m1n1 user guide, read 2026-10-27 (<https://asahilinux.org/docs/sw/m1n1-user-guide/>).
1. User only, in the recovery environment on the Linux stub volume: `csrutil disable` and `nvram boot-args=-v`. This lowers a security policy and changes data the SEP sees. It needs the user's own go.
2. Cable: USB-C to USB-A, C end into a Thunderbolt port on the M3, A end into this Mac.
3. Host (this Mac), changes the host, needs the user's OK: `python3 -m pip install --user pyserial construct`, then copy `m3gpu/src/m1n1/proxyclient` from the M3 to a local folder.
4. Power on the M3 with the cable attached. Stage 1 waits about 5 seconds for a proxy. This Mac then shows `/dev/cu.usbmodemP_01` (proxy) and `/dev/cu.usbmodemP_03` (virtual UART).
5. On this Mac: `export M1N1DEVICE=/dev/cu.usbmodemP_01`, then start the m1n1 shell from the copied `proxyclient/tools` folder and read `/chosen/memory-map` for `SEPFW`. The guide documents no shell or ADT commands, so these commands are unverified.
6. Boot back to Fedora: power cycle the M3 (hold the power button about 10 seconds, power on without the cable). Stage 1 then loads `boot.bin` from the ESP and GRUB boots the default kernel. Then, in recovery: `nvram boot-args=` and `csrutil enable` (not full security: the guide says that uninstalls m1n1).
7. Cost: the M3 is off the network for the whole session, so all other sessions pause.

## Window result (2026-10-27, first test boot with the SEP device tree)

Details and per-part results: [touchid-stage2-plan.md](touchid-stage2-plan.md), "Window result".

- **The boot chain worked.** The merged test DTB booted, m1n1 ran its `sep` step, and the SEP node carried both manifests and a `sep-firmware` reserved region. The manifest sizes differ from the macOS ADT dump, because the Linux boot has its own manifests. The restore unit put `boot.bin` back to stageE by itself.
- **SEP dry load: partly proven.** With writes off, the driver loaded without a crash and stayed stable. It enabled the SEP DART and node, selected the `T6030/J516s` profile, parsed the xART gigalocker read-only (170 slots, 10 live records, 0 malformed) and created an empty host-state file. Then it logged nothing more in 5 minutes: no "endpoints advertised" line and no "no endpoint" line, no hwrng, no `/dev/sep-bio`. The code should log one of the two attach lines within about 3 seconds, so the SEP mailbox exchange is **unproven**. Cause found afterwards, in the source: my test DTB left the SEP mailbox node disabled, so the driver's mailbox lookup deferred silently (`-EPROBE_DEFER` prints nothing). A second test boot repeated the silence. See the plan, "Second test boot". The fix is in the DTB script, not in the driver; a third test boot is needed to learn whether the SEP answers.
- **Camera temporal filter 1: FAIL, do not repeat.** The camera node appeared and the property read 1, but a capture delivered no frames and hung. The stop commands to the ISP firmware timed out and the driver stopped it by force. A normal boot gives 150 frames in 5 seconds. This ISP firmware does not accept the filter. The property stays 0.
- **Side effects:** a root-only host-state file now exists under `/var/lib` (no identity in it); `apple_sep` was loaded until the next reboot and the SEP registration is one-shot, so a retry needs a new test boot.

## Sources (all read on 2026-10-26)

- Asahi M3 feature support: <https://asahilinux.org/docs/platform/feature-support/m3/>
- Asahi SEP notes: <https://asahilinux.org/docs/hw/soc/sep/>
- Apple M3 Pro, Max, Ultra device tree series v3 (no SEP): <https://lkml.iu.edu/2607.3/01647.html>
- Aurora Linux archive repository: <https://github.com/iconidentify/aurora-linux>
- Identity bag persistence issue: <https://github.com/iconidentify/aurora-linux/issues/31>
- SiliconForest kernel fork (page showed no SEP text): <https://github.com/iconidentify/siliconforest-linux>
- Successor repository (page showed only a kernel README): <https://github.com/omacom/linux-aurora>
- t2linux Touch ID guide (Intel T2 Macs only, not Apple Silicon): <https://wiki.t2linux.org/guides/touchid/>
- Local: `docs/features/missing-drivers.md` row 5 and "The three most valuable fixes" item 3; `docs/whats-in-the-repo.md`; M3 kernel source files named above.
