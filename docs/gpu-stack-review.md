# Review: SiliconForest / linux-aurora M3 Pro GPU stack

Review date: 2026-10-26. Scope: the SiliconForest qualified set for J516S with OS firmware 14.7 (catalog v2026.10.19.2).

| Part | Repo | Commit reviewed | Compared with |
|---|---|---|---|
| Kernel | iconidentify/siliconforest-linux (from omacom/linux-aurora) | `0e1f4666` (7.2.11) | Upstream v7.2.11 and AsahiLinux/linux `asahi` (7.1.13) |
| Boot loader | iconidentify/siliconforest-m1n1 | `aca1258c` | AsahiLinux/m1n1 `25b1d89c` |
| Mesa | iconidentify/siliconforest-mesa | `7515336b` | Upstream Mesa main (merge base `ab0ab220`, 2026-10-01) |

Method: read-only git diffs on the host. No code from these repos was built or run. Pattern scans plus targeted reading. A full line-by-line review of about 418,000 added kernel lines was not possible.

## Kernel

### Size and authors

- 1,942 files differ from upstream 7.2.11, not counting `tools/testing` and `Documentation`.
- 1,674 of the changed files are not changed by Asahi's own branch.
- Top authors since 7.2.11: Ryan Murray (1,262 commits), Chris Kearney (940), DjDeveloperr (596). Asahi developers appear much less (Sven Peter 27, Janne Grunau 15).
- No binary files in the diff.

### GPU driver (the part we want)

- A separate Rust driver, `drivers/gpu/drm/asahi-m3/` (183 files), with G15 code for T6030.
- J516S is named directly: "G15 GPU support (T6030, M3 Pro: J514S, J516S; firmware RTKit 2419, the macOS 14.7-14.8 stub)" (`drivers/gpu/drm/asahi-m3/g15/mod.rs:3`).
- A firmware entry names "J516S B0 RTKit-2419.140.12 (maintained 14.x handoff)" for `apple,j516s` (`g15/hw.rs:155`).
- Our M3 runs the 14.7 stub, so this matches.
- Selected by `CONFIG_SILICONFOREST_NATIVE_GPU` (default N, needs EXPERT). The help text says it needs the matching native Mesa and must not be mixed with other Mesa builds.
- `CONFIG_SILICONFOREST_M3` is a different, development-only stack. We do not use it.

### Finding 1 (high): Secure Enclave driver writes to storage shared with macOS by default

- The SEP driver (`CONFIG_APPLE_SEP`, default `m` on Apple) opens `/dev/disk/by-partlabel/iBootSystemContainer` (`drivers/soc/apple/xart_store.rs:16`).
- That partition holds the xART "gigalocker". Its own guard file says the gigalocker "is shared by every OS installed on the Mac" (`drivers/soc/apple/xart_guard.rs`).
- Module defaults in `drivers/soc/apple/sep.rs:2467-2482`:
  - `xart_writes` default 1 (writes on).
  - `provision_keybag` default 1 (creates a keybag on first boot).
  - `xart_guard` default -1, which means "off in SiliconForest". The guard protects macOS records only when it is on.
- It also opens files as the kernel (root) user under `/var/lib/aurora-sep-*.bin` (`drivers/soc/apple/store_shim.c`). The comments say this is deliberate.
- Risk: on our dual boot Mac, loading this module could change Secure Enclave anti-replay records that macOS uses. Effects on macOS Touch ID or FileVault are unknown.
- **Action: build with `CONFIG_APPLE_SEP=n`.** The GPU does not need it. Also blacklist `apple_sep` in case a module from another kernel loads.

### Finding 2 (medium): large experimental memory-management changes

- The "user4k" work (4K user pages on a 16K kernel) changes core memory code: `mm/` (about 50 files), `arch/arm64/mm`, `fs/exec.c`, `kernel/fork.c`, `kernel/events`, `net/ipv4/tcp.c`, `net/tls`, `security/tomoyo`.
- About 65 commits, mostly from 2026-10-06 to 2026-10-19.
- It is gated by `CONFIG_ARM64_USER4K_EXPERIMENTAL` (in `arch/arm64/Kconfig.debug:25`, **`default y`**) and a boot option ("keep 4K userspace off unless booted with user4k=on"). Because the default is y, we must turn it off by hand.
- Many commits restore native behaviour when the feature is off, but the edited code paths are still compiled and run.
- Risk: memory-management bugs can crash the system or open security holes. Fast, recent changes have little test history.
- **Action: build with `CONFIG_ARM64_USER4K_EXPERIMENTAL=n`.** Do not boot with `user4k=on`.

### Finding 3 (low): test-only code with powerful calls

- `arch/arm64/mm/user4k-test.c` uses `call_usermodehelper` and `kernel_write`, and `user4k-data-test.c` opens kernel sockets. These are KUnit tests.
- **Action: keep KUnit off (`CONFIG_KUNIT=n`), as in the Fedora kernel.**

### Other notes

- New drivers: Neural Engine (`drivers/accel/ane`), video decode and encode (`drivers/media/platform/apple/avd`, `ave`), MediaTek MT7932 Wi-Fi and Bluetooth, TI TPS Type-C for M3, T6030 panel backlight.
- `request_firmware()` calls load files from `/lib/firmware`. This is normal.
- The AVD Kconfig points to firmware built from `github.com/aurora-silicon/avd-fw`. Not needed for the GPU. We do not install it.
- No network calls to outside hosts, no `kallsyms_lookup_name`, no `set_memory_rw`, no `commit_creds` found in added code.
- `prepare_kernel_cred` is used only in the SEP store shim (Finding 1).
- The SiliconForest reference kernel config has `CONFIG_MODULE_SIG` off and `CONFIG_SECURITY_LOCKDOWN_LSM` off. We can choose our own.

## Boot loader (m1n1)

Reviewed by a helper agent with read-only git diffs. 93 commits, 126 files, about 25,000 added lines.

**Verdict: try with care. Nothing malicious found.**

- No network code, no binary blobs, no writes to NVRAM, storage, boot policy or the Secure Enclave. All changes last for one boot only.
- The fork removes the upstream m1n1 call to `sep_init()` and seeds the random number generator from the device tree (ADT) on M2 and later (`src/kboot.c:408`). This means less Secure Enclave contact.
- The upstream "no AI" policy file (`AGENTS.md`) is replaced. `CODEOWNERS` is the fork owner only. 67 of 93 commits come from one author.
- All upstream CI workflows are deleted. No CI builds `boot.bin`. **We must build it ourselves from `aca1258c`.**

What changes on a j516s boot:

- **Self-relocation (every boot):** on M3 CPUs, `src/start.S:83-171` moves stage 2 to avoid a display log buffer. This is the most invasive new code. A failure here would most likely hang the boot.
- **Display (every boot):** reserves display log buffers and locks the display DART (`kboot_display_handoff.c:1427`). The real display handoff needs `chosen.asahi,t6030-dcp=1`.
- **GPU (off by default):** without `chosen.asahi,t6030-gpu=1`, it is a dry run that touches no GPU hardware (`src/kboot_gpu.c:2291-2299`). When on, it powers the GPU, reads the leakage fuse, and builds power tables from the ADT (400 to 1500 mV). On any failure it turns the GPU off again.
- **Firmware gate:** the GPU starts only if the GPU firmware matches one of two hard-coded G15S image UUIDs, which the code labels as macOS 14.8.3 (`src/firmware.c:333-338`). Our stub is 14.7. The kernel says it supports "the macOS 14.7-14.8 stub", and SiliconForest reports a 14.7 J516S as qualified. Whether our GPU firmware UUID is in that table is **not checked**. If it is not, the GPU stays off safely.
- m1n1 does not set voltages or clocks. It does not touch the speaker amps.

Risks:

- Brick risk is low, because nothing persistent changes. Recovery: boot macOS from the boot picker and restore `/boot/efi/m1n1/boot.bin`.
- The fork's GPU power model (G15S formula, 70 A limit, `kboot_gpu.c:1015-1055`) is not confirmed on hardware. The code says values marked TODO are unconfirmed (`kboot_gpu.c:502`). A wrong model is a heat and performance risk.
- Their own validation file reports "65 pass, 10 fail" for the G15 test suite (`SILICONFOREST-VALIDATION.md:12`).

Not reviewed line by line: hypervisor changes, `kboot_atc.c`, `kboot_gpu26.c`, T8122 and T6031 files (not on the j516s path).

Suggested first boot: set none of the `chosen.asahi,t6030-*` options. Check the log for "FDT: GPU: dry run OK" and "FW: GFX: identified image". Only then set `chosen.asahi,t6030-gpu=1`.

## Mesa

Reviewed by a helper agent with read-only git diffs. 260 commits, 664 files, about 696,000 added lines (most are generated tables).

**Verdict: safe to build into a separate folder (`/opt/mesa-m3`), with care. Nothing malicious found.**

- No network, telemetry, `exec` or `dlopen` in added code. No binary files.
- The build does not download anything or run fork scripts. `tools/siliconforest/` is not used by meson.
- Debug environment variables can read or write files or inject GPU addresses (for example `ASAHI_G17P_RQ_BODIES_PATH`, `ASAHI_MESH_MARKER_VA`). Most are reachable only on G17P (M4), not on M3. Do not set any `ASAHI_*` variables.
- `agx3b_tables.c` and `agx3c_tables.c` (about 500,000 lines) are plain data. The README says they are "generated from Apple's own llvm::AGX3 encoder tables". The generator is not in the repo. This is a copyright and provenance concern. Keep the build private and do not redistribute it.
- 242 of 260 commits are unsigned. 137 come from DjDeveloperr.

M3 support:

- Mesa admits G15S only for chip 0x6030 with 1 die, 2 clusters and USC generation 3 (`src/asahi/lib/agx_chip.c:279-285`).
- It needs the fork's kernel interface. On the Fedora kernel it fails safely at start-up (`agx_device.c:878`).
- The kernel has the matching header `include/uapi/drm/asahi_m3_drm.h`. The Mesa README links it to `CONFIG_SILICONFOREST_M3`. The kernel's `SILICONFOREST_NATIVE_GPU` option uses the same `asahi-m3` driver. Which option matches this Mesa build must be confirmed at run time.

Risks:

- The Mesa repo's own validation file says "No physical Apple GPU ... was qualified" (tests on x86_64 with a fake DRM device, at an older commit). This conflicts with the SiliconForest J516S report, which claims hardware OpenGL and Vulkan pixel readback.
- GPU hangs are likely during testing. On Asahi, a GPU firmware crash usually needs a reboot.
- Changes outside the Asahi driver (zink, Vulkan runtime and WSI, NIR, util) look like correctness fixes.

Build settings (from `tools/siliconforest/build.sh`, read only):

- `-Dgallium-drivers=asahi,zink,softpipe -Dvulkan-drivers=asahi -Dplatforms=x11,wayland -Dglx=dri -Degl=enabled -Dgbm=enabled -Dglvnd=disabled -Dllvm=enabled -Dmesa-clc=enabled -Dprecomp-compiler=enabled -Dvideo-codecs= -Dgallium-va=disabled`
- Add `--prefix=/opt/mesa-m3 -Dbuild-tests=false`.
- Needs LLVM and Clang 22, SPIRV-LLVM-Translator, libclc, glslang, Meson 1.10, Mako, PLY, PyYAML, SPIRV-Tools, libdrm. No Rust.
- Do not use `build-targets.py`. It expects x86_64 file names.

## Conflicts to check on the hardware

| Claim | Source | Conflict |
|---|---|---|
| J516S with 14.7 has working hardware OpenGL and Vulkan | SiliconForest report 2026-10-19 | Mesa validation file: no physical GPU qualified (older commit) |
| GPU firmware support | Kernel: "macOS 14.7-14.8 stub" | m1n1 table lists two images labelled 14.8.3. Our stub is 14.7. |
| m1n1 G15 tests | SiliconForest m1n1 | Their own file: "65 pass, 10 fail" |

## Verdict

**Try with care, with our own build settings. Do not use the SiliconForest installer or their prebuilt packages.**

Nothing malicious was found in any of the three parts. The code is large, very new, mostly AI-assisted, and not reviewed by Asahi. The main dangers are the Secure Enclave driver and the core memory changes. We can turn both off.

Required kernel settings (start from Fedora's own config, then change these):

| Option | Value | Reason |
|---|---|---|
| `CONFIG_SILICONFOREST_NATIVE_GPU` | y | The M3 Pro GPU driver |
| `CONFIG_SILICONFOREST_M3` | n | Development-only stack |
| `CONFIG_APPLE_SEP` | n | Finding 1: writes to storage shared with macOS by default |
| `CONFIG_ARM64_USER4K_EXPERIMENTAL` | n | Finding 2: default y, core memory changes |
| `CONFIG_KUNIT` | n | Finding 3: test code |
| `CONFIG_LOCALVERSION` | `-m3gpu` | Keeps the new kernel apart from Fedora's |

Also add `blacklist apple_sep` to `/etc/modprobe.d/`, in case another kernel loads a module of that name.

Order for the hardware tests:

1. Build the kernel, m1n1 (`aca1258c`) and Mesa on the M3, from source.
2. Back up `/boot/efi/m1n1/boot.bin` and the Fedora DTBs.
3. Boot once with no `chosen.asahi,t6030-*` options. Check the m1n1 log for "FDT: GPU: dry run OK" and "FW: GFX: identified image".
4. If the GPU firmware is identified, set `chosen.asahi,t6030-gpu=1` and boot the new kernel.
5. Test with the new Mesa for one program at a time (environment variables), not system-wide.
6. Roll back with the GRUB menu (kernel) or by restoring `boot.bin` from macOS (m1n1).

Not checked: full line-by-line review of about 418,000 added kernel lines and 500,000 lines of Mesa tables, commit signatures, and our GPU firmware UUID.
