# Extra drivers and fixes for the MacBook Pro M3 Pro on Fedora Asahi Remix

A how-to guide for the `agx-linux-kit` project and its sibling repositories `distro-pack` and `ane-linux`.

Contents:

1. [What this is](#1-what-this-is)
2. [Who it is for](#2-who-it-is-for)
3. [Status of each feature](#3-status-of-each-feature)
4. [Before you start](#4-before-you-start)
5. [Step by step](#5-step-by-step)
6. [Touch ID](#6-touch-id)
7. [Known problems and troubleshooting](#7-known-problems-and-troubleshooting)
8. [Credits](#8-credits)

## 1. What this is

This guide helps you add GPU support, fixes and extra features to a MacBook Pro M3 Pro that already runs Fedora Asahi Remix.

> **Not official. Not endorsed. Use at your own risk.**
>
> - This project is not Asahi Linux. The Asahi Linux project does not support it, review it or endorse it.
> - The steps change the boot files, the kernel and (for Touch ID) the Secure Enclave storage that macOS shares.
> - A mistake can leave Linux unbootable. A mistake in the Touch ID steps can also harm macOS secure storage.
> - Nobody gives a guarantee. You are responsible for your Mac and your data.
> - Report a bug to Asahi Linux only when you can repeat it on the stock Asahi kernel and the stock Asahi Mesa. Do not report a problem that comes from these patches to the Asahi project.
> - To test on stock first, boot the stock kernel with `sudo -n /usr/local/sbin/agx-boot use-stock` (see Step 5).

Asahi Linux has supported the M3 family since September 2026. The official release gives you the installer, a working desktop and many drivers. At the time of writing it has no 3D acceleration for the M3 GPU, no sleep and no HDMI on MacBooks. See the [Asahi M3 feature page](https://asahilinux.org/docs/platform/feature-support/m3/) for the current state.

This project adds these parts on top of the official install:

- GPU work: kernel patches for the G15 GPU driver, Mesa patches for the AGX3 compiler (including the Q3_K fix for llama.cpp), and a llama.cpp patch for `iq2_s` models.
- A fix for an out-of-range array index in the AV1 hardware decoder.
- A load order for the DART (IOMMU) driver.
- A Bluetooth fix for the resume after sleep.
- A fan control patch and a fan curve service.
- A memory floor patch (PMP) that raises memory speed from about 32 GB/s to above 100 GB/s.
- USB-C displays and Thunderbolt host-to-host links.
- Touch ID through the Secure Enclave for the lock screen and the login screen (with `fprintd` and a private `libfprint`). Sudo stays password-only. The power key is protected.
- A Fedora kernel RPM build (in `distro-pack`).
- A macOS-style KDE desktop and a flat lock screen.
- File sharing with LocalSend and AirDrop options.
- Research on the Neural Engine.

Rules you must know:

- The kernel, m1n1 and Mesa come from the community SiliconForest fork. The kit builds them from pinned commits.
- The SiliconForest Mesa has instruction tables whose license is unclear. Build it for yourself. Do not share the binaries.
- The kit never ships Apple firmware. The Asahi installer copies it from your own macOS.
- No license is chosen yet for the kit scripts and documents. The kernel, m1n1 and Mesa sources keep their own licenses.

Paths in this guide are relative to the `agx-linux-kit` folder, unless a path starts with `distro-pack/` or `ane-linux/`. Those are sibling folders.

## 2. Who it is for

**Tested machine:** MacBook Pro 16-inch with M3 Pro (Mac15,7, board J516S, chip revision B1, 18 GB memory), Fedora Asahi Remix 44 with KDE Plasma.

Other machines are untested:

- The MacBook Pro 14-inch M3 Pro (J514S) has the same chip. The GPU driver names it. Nobody has tested it. The kit has no profile for it.
- Other M3 Macs (M3, M3 Max) need new GPU data. Do not use this guide on them.
- A machine with a different amount of memory may have a different GPU firmware build. Read `docs/gpu-firmware-investigation.md` before you go on.

The install scripts check the board name and refuse other machines. To see your board name, run:

```bash
tr '\0' '\n' < /proc/device-tree/compatible
```

The tested board shows `apple,j516s` in the output.

Use this guide only on a Mac that you own and control.

## 3. Status of each feature

Status on the tested J516S. "Works" means it passed the tests in this project. "Partly" means it works with limits. "Not done" means it is not finished, not tested or research only.

| Area | Feature | Status | Summary |
|---|---|---|---|
| Graphics | GPU (OpenGL 4.6, Vulkan 1.4) | Works | Needs the kernel, m1n1 and Mesa from this kit. Short bursts of work drop to a low GPU clock after about 20 s. |
| Graphics | Memory speed | Works | CPU reads 108 to 126 GB/s on many threads. GPU reads about 134 GB/s. It needs the PMP memory floor patch. |
| Graphics | Built-in display | Works | Native 3456x2160. Brightness works. |
| Graphics | 120 Hz (ProMotion) | Partly | A fixed 120 Hz works. The refresh rate is not adaptive. |
| Graphics | HDMI port | Works | Mirror, extend and hot plug work. 4K at 60 Hz and HDMI audio are not tested. |
| Graphics | USB-C displays | Works | DisplayPort over USB-C works on all three ports. It needs the `thunderbolt_apple` module. |
| Ports | Thunderbolt and USB4 | Works | Host-to-host link at 20 Gb/s on all three ports. Thunderbolt devices and 40 Gb/s are not tested. |
| Ports | USB-C data speed | Works | USB 3 works on all three ports. |
| Ports | SD card slot | Works | Tested with an old card only. |
| Ports | Internal SSD | Works | Passes the read and write test. |
| Wireless | Wi-Fi | Partly | Works. A refused suspend can leave it down until you reload the driver (see section 7). |
| Wireless | Bluetooth | Works | AirPods Max work through LibrePods with three local patches. The resume fix is in the kernel patch. |
| Wireless | AirDrop | Partly | Works in three directions. It stays off by default until a Wi-Fi coexistence test passes. |
| Power | Sleep and lid | Partly | Lid close suspends and resumes. Only `s2idle` sleep is offered. |
| Power | Battery | Works | Charge level, health and charger events work. A live MagSafe plug test is open. |
| Audio and video | Speakers | Partly | They play sound. The listening test is not complete. |
| Audio and video | Microphones | Works | They record clearly. |
| Audio and video | Headphone jack | Not done | Not tested. |
| Audio and video | Webcam | Works | A clean PipeWire camera tool cuts noise and colour cast. No exposure or gain control exists. |
| Audio and video | Hardware video decode | Works | H.264, HEVC, VP9 and AV1 through a VA-API layer. It needs a firmware file and a layer you build. |
| Audio and video | Video encode and ProRes | Not done | Research only. The CPU encodes. |
| Other | Ambient light sensor | Works | It reads values. |
| Other | Keyboard light and trackpad | Not done | The devices are present. The hand check is open. |
| Other | Touch ID | Works | Lock screen works with one enrolled finger. A wrong finger is refused. See section 6. |
| Other | Neural Engine | Not done | Research only. An early test made the Mac reset. |
| Other | Fans and heat | Works | A kernel patch and the fan curve service make the fans spin. Without them the fans stay off. |

The full reports are in `docs/features/`. The numbers are in `docs/performance.md`.

## 4. Before you start

Do all of these first.

1. **Back up your data.** Make a Time Machine backup of macOS. Copy your personal files to another disk.
2. **Keep macOS installed.** You need it for firmware updates, for the rollback path and (for Touch ID) because it shares the Secure Enclave storage.
3. **Know your macOS admin password.** The Asahi installer and the rollback ask for it.
4. **Use the official Asahi installer.** Follow the instructions at [asahilinux.org](https://asahilinux.org/). The installer for the M3 asks for its Expert mode. Read the installer launcher before you run it, because it downloads files and runs as root. The kit has no script for this step.
5. **Learn how to reach the startup options.** Hold the power button until the startup options appear. You use them to boot macOS.
6. **Connect the charger.** Keep it connected for every build and every boot step. Turn off automatic sleep during builds.
7. **Free about 40 GB** in your home folder for the sources and builds.
8. **Have a second computer** or a phone to read this guide. A second computer with SSH access to the Mac also helps for the rollback.
9. **Rehearse the rollback** (below) before you run stage C.

### Rollback from macOS (when Fedora does not boot)

This puts the saved stock boot file back. The kit saves it in stage A as `boot.bin.stock`.

1. Hold the power button until the startup options appear. Choose macOS.
2. Open Terminal in macOS. Find the EFI partition of the Fedora install:

   ```bash
   diskutil list
   ```

3. Mount it. Use the disk name from the list for `diskXsY`. You type the macOS password.

   ```bash
   sudo diskutil mount diskXsY
   ```

4. Copy the stock file back and check its hash. The volume name can differ on your Mac.

   ```bash
   cp "/Volumes/EFI - FEDOR/m1n1/boot.bin.stock" "/Volumes/EFI - FEDOR/m1n1/boot.bin" && shasum -a 256 "/Volumes/EFI - FEDOR/m1n1/boot.bin"
   ```

5. Unmount it and restart.

   ```bash
   sudo diskutil unmount diskXsY
   ```

On the first rehearsal, only mount the volume and read the hash. Change nothing. Fedora then boots with the stock setup.

Stage A also puts a copy of `boot.bin.stock` in `~/agx-work/backup`. Copy that file to another computer.

## 5. Step by step

Each step has four parts: what it does, the commands, how to verify and how to undo.

Run the steps in order. Run every command as your normal user, in the `agx-linux-kit` folder, unless the command starts with `sudo`. Do not go on to the next step if a verify check fails.

### Step 0. Official Asahi install

**What it does.** It gives you Fedora Asahi Remix 44 with KDE, the stock Asahi kernel and the stock boot chain.

**Commands.** The kit has no script for this step. Follow the official instructions at [asahilinux.org](https://asahilinux.org/). Then update the system:

```bash
sudo dnf upgrade --refresh
```

Restart after the update.

**Verify.** The machine boots to the KDE desktop. Run the board check from section 2. The output must show your board name.

Also note your firmware identity now. The GPU driver admits only firmware builds that it knows. Read these two values:

```bash
cat /proc/device-tree/chosen/asahi,iboot1-version
```

```bash
cat /proc/device-tree/chosen/asahi,iboot2-version
```

The tested Mac showed system firmware 15.6 and an OS stub from macOS 14.7. A different stub can change the GPU result. See `docs/gpu-firmware-investigation.md`.

**Undo.** The kit has no script to remove Linux. Use the official Asahi instructions.

### Step 1. Get the kit and choose the profile

**What it does.** It sets your work folder, your machine profile and your names.

**Commands.** Copy the kit folder to your Mac. Then:

```bash
cp config.local.example.sh config.local.sh
```

Open `config.local.sh`. Set `AGX_PROFILE=j516s`. Read the other lines. They are comments with the names of the first test install (`~/m3gpu`, `/opt/mesa-m3`, `-m3gpu`). The defaults are `~/agx-work`, `/opt/mesa-agx` and `-agx`.

If you plan to use Touch ID, set `LOCALVERSION=-m3gpu`. The Touch ID scripts expect the kernel release `7.2.11-m3gpu+`. With another name you must pass `TI_KREL=<your release>` to every Touch ID script (see section 6). After the build, `cat ~/agx-work/out/kernel-release` shows the real release.

**Verify.** `config.sh` loads without an error when you run any build script.

**Undo.** Delete `config.local.sh`.

### Step 2. Fetch the sources and install build tools

**What it does.** It downloads the pinned kernel, m1n1 and Mesa trees (SiliconForest commits) and installs build packages. Only `build/deps.sh` asks for the sudo password.

**Commands.**

```bash
build/fetch-sources.sh
```

```bash
build/deps.sh
```

**Verify.** `build/fetch-sources.sh` prints one line for each tree with its commit. The kernel line must start with `0e1f4666`.

**Undo.** Delete `~/agx-work`. The installed build packages can stay.

### Step 3. Patch and build the kernel

**What it does.** It builds a kernel with the GPU driver, the display driver, USB4 and the fixes in this project. It installs nothing.

**Commands.** Apply the kernel patches in this order. They are the series that `distro-pack` uses.

```bash
KIT=$PWD
```

```bash
git -C ~/agx-work/src/linux apply "$KIT/patches/m3-kernel-tree-2026-10-26.patch"
```

```bash
git -C ~/agx-work/src/linux apply "$KIT/patches/g15-perf-tgt-util.patch"
```

```bash
git -C ~/agx-work/src/linux apply "$KIT/patches/g15-recovery-drain-halt.patch"
```

```bash
git -C ~/agx-work/src/linux apply "$KIT/patches/macsmc-hwmon-ftst-unlock.patch"
```

What these patches give you:

| Patch | What it does |
|---|---|
| `m3-kernel-tree-2026-10-26.patch` | GPU firmware identity for the J516S, the PMP memory floor and the Bluetooth resume fix. It contains the single patches listed in the next paragraph. |
| `g15-perf-tgt-util.patch` | A GPU module parameter. It changes nothing by default. |
| `g15-recovery-drain-halt.patch` | GPU fault recovery. The driver drains and halts instead of a fail-stop. |
| `macsmc-hwmon-ftst-unlock.patch` | Fan control on the M3. |

Do not apply these separately. The first patch already holds them: `g15-j516s-b1-pin.patch`, `g15-fw-digest-diag.patch`, `g15-fw-masked-identity.patch`, `t6030-pmp-memory-floor.patch` and `hci-bcm4377-j516s-resume-recovery.patch`. A second apply fails.

Optional: the AV1 decoder fix. Apply it the same way.

```bash
git -C ~/agx-work/src/linux apply "$KIT/patches/avd-av1-ref-idx-bounds.patch"
```

The project tested this patch as an external module. Applying it before the kernel build is the same source change. That route is not tested.

Do not apply these patches in this step: `g15-perf-boost-base.patch` (a test) and `patches/touchid/` (Touch ID, section 6). `build/build-apple-sep.sh` applies the Touch ID patches to a copy.

Check the configuration first. This changes nothing outside the build folder:

```bash
CONFIG_ONLY=1 build/build-kernel.sh
```

Then build. This runs detached, so a closed terminal does not stop it. Stay logged in on the desktop while it runs.

```bash
systemd-run --user --unit=agx-kernel build/build-kernel.sh
```

The build log is `~/agx-work/logs/kernel-build.log`.

**Verify.**

- The config check prints `ok: CONFIG_... off` lines and ends without `CONFIG CHECK FAILED`. The script turns off the SEP driver (it writes to the xART storage that macOS shares), the 4K user page mode, livepatch and KUnit.
- The build prints `Kernel staged in <folder>`.
- `cat ~/agx-work/out/kernel-release` shows the release name.

**Undo.** Nothing is installed. Delete `~/agx-work/out` and `~/agx-work/build-linux`.

### Step 4. Patch and build m1n1 and Mesa

**What it does.** It builds the boot loader stage (m1n1) and the Mesa GPU stack. It installs nothing.

**Commands.** Apply the two Mesa patches first, in this order. The second needs the first.

```bash
git -C ~/agx-work/src/mesa apply "$KIT/patches/mesa-agx3-fmul-narrow-wait.patch"
```

```bash
git -C ~/agx-work/src/mesa apply "$KIT/patches/mesa-agx3-inplace-multislot-wait.patch"
```

- The first patch makes llama.cpp flash attention work.
- The second patch is the Q3_K fix. Without it, llama.cpp fails on `q3_K` models.
- Do not apply `mesa-asahi-lost-context-noop.patch`. The test showed that it does not help.

Build m1n1, then Mesa:

```bash
build/build-m1n1.sh
```

```bash
build/build-mesa.sh
```

**Verify.** `build/build-m1n1.sh` makes a file `~/agx-work/out/m1n1/m1n1-aca1258c2d7daad7db7079d4f89bb8217659f7ac.bin`. `build/build-mesa.sh` stages Mesa in `~/agx-work/out/mesa-stage`.

**Undo.** Nothing is installed. Delete the build folders.

### Step 5. Install in stages (A to E)

**What it does.** It installs the kernel and Mesa next to the stock ones. Then it turns on the GPU and display options in small steps. Each stage backs up first and prints what it changed. The stock kernel stays installed and stays the default boot.

Read each script before you run it. Check the output of each stage before the next one. Save your work before a stage that reboots.

| Stage | Command | What it does | Reboot |
|---|---|---|---|
| A | `sudo install/stage-a.sh` | Backs up the boot files. Pauses automatic `boot.bin` rebuilds. | No |
| B | `sudo install/stage-b.sh` | Installs Mesa into `/opt/mesa-agx`. Installs the test kernel as an extra GRUB entry. Selects it for the next boot only. | No |
| C | `sudo install/stage-c.sh` | Installs the new m1n1 with the distribution DTBs and no new options. | Yes, stock kernel |
| D | `sudo install/stage-d.sh` | New m1n1 with the test kernel DTBs. The GPU stays off. | Yes, test kernel once |
| E | `sudo install/stage-e.sh` | Turns on the GPU and display options. | Yes, test kernel once |

**Stage A.** Run it, then rehearse the rollback from section 4.

```bash
sudo install/stage-a.sh
```

- Verify: the output ends with `STAGE_A_DONE`. The hashes of `boot.bin` and `boot.bin.stock` match. A copy exists in `~/agx-work/backup`.
- Side effect: it adds `M1N1_UPDATE_DISABLED=1` to `/etc/sysconfig/update-m1n1`. A Fedora kernel update then does not replace your boot file. Remove this line when you finish testing.
- Undo: remove that line. Delete `/root/agx-backup` if you want.

**Stage B.** Boot the stock Fedora kernel first. Then:

```bash
sudo install/stage-b.sh
```

- Verify: the script prints its results. The next boot (only that one) uses the test kernel. After it boots, the desktop, Wi-Fi, keyboard, trackpad and USB work. `journalctl -k -b` shows no kernel oops. Mesa is in `/opt/mesa-agx`, and no system file points to it yet.
- Undo: reboot. The default is still the stock kernel.

**Stage C.**

```bash
sudo install/stage-c.sh
```

- It reboots by itself only if every step succeeded.
- Verify: the stock kernel boots to the desktop. This shows the new m1n1 version:

  ```bash
  cat /proc/device-tree/chosen/asahi,m1n1-stage2-version
  ```

  It must print `aca1258`.
- Undo: `sudo install/use-bootbin.sh stock`.

**Stage D.**

```bash
sudo install/stage-d.sh
```

- It reboots once into the test kernel. The GPU is still off.
- Verify: the test kernel boots to the desktop (`uname -r` shows the kit release). `ls /sys/bus/platform/devices | grep gpu` shows a GPU node. The node is disabled.
- Known problem: on some boots the microphone card is missing, because the audio coprocessor firmware crashes at start. It is intermittent and a reboot clears it.
- Undo: `sudo install/use-bootbin.sh stageC`, or `sudo install/use-bootbin.sh stock`.

**Stage E.**

```bash
sudo install/stage-e.sh
```

- It reboots once into the test kernel with the GPU and display options on.
- Verify, after that boot:
  - `ls /dev/dri/` shows a `renderD*` node.
  - `ls /sys/class/backlight/` shows `apple-panel-bl`.
  - `journalctl -k -b` has no GPU fault lines.
- If the log says `unsupported GPU firmware build`, the driver refuses your firmware. This is safe: the GPU stays off. Read `docs/gpu-firmware-investigation.md`. Never force an unknown build.
- Undo: turn the GPU options off for every kernel.

  ```bash
  sudo -n /usr/local/sbin/agx-boot use-stageD
  ```

Stage F replaces the installed test kernel after a rebuild. Boot the stock kernel first. Run `sudo install/stage-f.sh`.

**Boot actions without a password.** `install/setup-nopasswd.sh` (stage G runs it too) installs `/usr/local/sbin/agx-boot` and a sudoers rule for exactly these actions. Read the script before you accept the rule.

```bash
sudo install/setup-nopasswd.sh
```

```bash
sudo -n /usr/local/sbin/agx-boot status
```

Other actions: `build-stageE`, `use-stock`, `use-stageC`, `use-stageD`, `use-stageE`, `test-once`, `mesa-select`, `restart-login` and `cleanup`.

**A GPU boot.** After stage E, this boots the test kernel once with the GPU options on:

```bash
sudo -n /usr/local/sbin/agx-boot use-stageE && sudo -n /usr/local/sbin/agx-boot test-once && sudo -n systemctl reboot
```

A normal reboot afterward gives the stock kernel again.

**The default boot.** The kit has no generic script to make the GPU kernel the default boot. Stage K does it for the author's machine. It has fixed hashes, a fixed user name and the old names. Do not run it unchanged. Use the `test-once` boot above, or copy stage K and adapt it after you read it.

**Stages H to P.** Stages H, I, J, K, L, M, N, O and P are copies from the author's machine. They read your user name and work folder from `config.sh`. You do not need most of them:

| Stage | What it installs | Do you need it? |
|---|---|---|
| H, I, J | Test kernel images (firmware digest log, masked identity, memory floor) | No. The patch in Step 3 holds these changes. Use stage F. |
| L | The USB4 module and the Bluetooth resume fix | No. Step 3 builds both. Stage F installs them. |
| O | The GPU fault recovery fix (`g15-recovery-drain-halt.patch`) | No. Step 3 applies it. Stage F installs it. |
| K | The default boot | Do not run it. It calls `m3gpu-boot`, and stage G removes that file. Use the `test-once` boot above. |
| M, N, P | GPU clock experiments (Mesa wait fix, `tgt_util`, DVFS boost) | No. Do not run them. |

If you run one anyway, these rules apply. Each script stops before any change when a rule is not met:

- The kernel release must be `7.2.11-m3gpu+`. Set `LOCALVERSION=-m3gpu` in `config.local.sh` (Step 1).
- The script reads a staged folder next to the one that `build/build-kernel.sh` writes. The names are `kernel-7.2.11-m3gpu+-memfloor` (J), `-usb4-bt` (L), `-tgt-util` (N), `-recovery` (O) and `-boost` (P). H and I read `kernel-7.2.11-m3gpu+`. Make a variant after a build with the patch applied:

  ```bash
  cp -a ~/agx-work/out/kernel-7.2.11-m3gpu+ ~/agx-work/out/kernel-7.2.11-m3gpu+-recovery
  ```

- The script checks the SHA-256 of the staged image. The default is the author's hash. Give the hash of your image in `AGX_IMAGE_SHA`. Stage K also reads `AGX_STAGEE_SHA` (the hash of `boot.bin.stageE`). Run the script with `sudo env`, so that the variable reaches it:

  ```bash
  sudo env AGX_IMAGE_SHA="$(sha256sum ~/agx-work/out/kernel-7.2.11-m3gpu+-recovery/boot/vmlinuz-7.2.11-m3gpu+ | cut -d' ' -f1)" install/stage-o-recovery.sh
  ```

  The other stages use the same form with their own script name: `stage-h-diag.sh`, `stage-i-masked.sh`, `stage-n-tgt-util.sh` and `stage-p-boost.sh`. Stages J and L check no image hash. Run them as `sudo install/stage-j-memfloor.sh` and `sudo install/stage-l-usb4-bt.sh`. Stage L needs a staged image equal to the installed image. Stage M reads `~/agx-work/out/mesa-stage-fa/opt/mesa-m3` and `/opt/mesa-m3`: `sudo install/stage-m-gpu-idle-mesa-fa.sh`.

### Step 6. Desktop on the native Mesa (stage G)

**What it does.** The desktop and the login screen use the native Mesa, only on GPU boots. A user environment generator and a linker cache entry do this. KWin ignores `LD_LIBRARY_PATH`, so a linker entry is needed. Stage G also runs `install/setup-nopasswd.sh`.

**Commands.** Run it in a GPU boot (the test kernel with stage E active):

```bash
sudo install/stage-g.sh
```

**Verify.**

1. Build the tests:

   ```bash
   tests/build-tests.sh
   ```

2. Run the render check and the compute check:

   ```bash
   ~/agx-work/out/gles-readback
   ```

   ```bash
   cd ~/agx-work/out && ./vk-compute
   ```

   The compute check prints `VK_COMPUTE_PASS`. In an SSH shell, select the native Vulkan driver first. The desktop session does this for you.

   ```bash
   export VK_DRIVER_FILES=/opt/mesa-agx/share/vulkan/icd.d/asahi_icd.aarch64.json
   ```

3. Optional long test. It runs a 10 minute stress test, an idle soak of 60 minutes and a kernel log check:

   ```bash
   nohup setsid tests/soak.sh >/dev/null 2>&1 < /dev/null &
   ```

   The result is in `~/agx-work/logs/soak-<time>/summary`. The last line is `SOAK_DONE`.

4. Optional full check of the machine (one line for each check, about 20 s of GPU load):

   ```bash
   tests/m3-selftest.sh
   ```

   It is written for the tested machine.

**Undo.**

- Turn off the native Mesa for every boot: `sudo touch /etc/agx-native-mesa.off`, then reboot. Remove the file to turn it on again.
- If the desktop does not start, press Ctrl+Alt+F3 for a text console and create that file.
- At the end of all testing: `sudo -n /usr/local/sbin/agx-boot cleanup` removes the no-password rule. Remove `M1N1_UPDATE_DISABLED=1` from `/etc/sysconfig/update-m1n1` only if you do not use Touch ID.

### Step 7. Feature fixes

Each fix is separate. Do them one at a time. Reboot only when the step says so.

#### 7.1 DART load order

**What it does.** It loads `apple_dart` early, so the audio, `aop` and USB drivers find their IOMMU. It removes the "late IOMMU probe" warning.

```bash
sudo install/dart-order/install-dart-order.sh
```

**Verify.** Reboot. Then:

```bash
journalctl -k -b | grep -c "late IOMMU probe"
```

The count must be 0.

**Undo.**

```bash
sudo install/dart-order/install-dart-order.sh --undo
```

The script saves the old initramfs as `/boot/initramfs-<release>.img.pre-dart-order`.

#### 7.2 Memory floor (PMP)

**What it does.** The kernel patch from Step 3 asks the power management processor for a memory floor. Without it, memory reads about 32 GB/s. With it, the P cores read above 120 GB/s.

**Commands.** None. It is in the kernel.

**Verify.** After the build tests from Step 6:

```bash
tests/mem-shared.sh ~/agx-work/out
```

Expect about 120 GB/s for the P cores and about 130 GB/s for the GPU.

**Undo.** Add `pmp_report.memory_floor=0` to the kernel command line. To try it for one boot, press `e` on the kernel entry in the GRUB menu and add it there. Or boot the stock kernel.

#### 7.3 Bluetooth resume fix

**What it does.** After sleep, the BCM4388 Bluetooth chip can time out on its first command. The patch turns on the driver's one-time recovery for the J516S.

**Commands.** None. It is in the kernel patch from Step 3.

**Verify.** Suspend and resume. Then:

```bash
journalctl -k -b | grep "recovering transport"
```

The line `recovering transport once after resume command timeout` appears on a resume where the fault happens. Bluetooth works again about 1 s later.

**Undo.** Boot the stock kernel.

#### 7.4 Fans

**What it does.** The Linux kernel does not ask the SMC for cooling. Without help, the fans stay off even at a 100 C hotspot. The kernel patch from Step 3 unlocks fan control. The service `m3-fancurve.service` sets the fans between 1500 and 5000 rpm from the temperature. It goes back to automatic on any failure.

**Commands.** Find the patched `macsmc-hwmon.ko` in the staged kernel tree (`~/agx-work/out/kernel-<release>/lib/modules/`). The docs do not name the exact path. Then:

```bash
sudo tools/m3-fancurve-install.sh /path/to/patched/macsmc-hwmon.ko
```

The module goes to `/lib/modules/<kernel>/updates/`. It applies only to that kernel. Every new kernel build must carry the patch.

**Verify.** The service runs after a reboot:

```bash
systemctl is-active m3-fancurve.service
```

Under heavy load, the fans spin.

**Undo.**

```bash
sudo tools/m3-fancurve-install.sh --undo
```

#### 7.5 Hardware video decode and the AV1 fix

**What it does.** It gives apps hardware decode for H.264, HEVC, VP9 and AV1 through VA-API. It needs three things: the firmware file, the AV1 fix (optional, in Step 3) and a VA-API layer.

**Commands.**

1. Build the decoder firmware from the AsahiLinux `avd-fw` repository. The script builds only. It prints the install command.

   ```bash
   build/build-avd-fw.sh
   ```

2. Run the install command that the script prints. It looks like this:

   ```bash
   sudo install -D -m 0644 ~/agx-work/avd-fw/build/apple/avd-fw-v4-t0.bin /lib/firmware/apple/avd-fw-v4-t0.bin && sudo restorecon -v /lib/firmware/apple/avd-fw-v4-t0.bin
   ```

3. Reload the driver (the script suggests this):

   ```bash
   sudo modprobe -r apple_avd && sudo modprobe apple_avd
   ```

4. Build the VA-API layer. It installs under `~/.local` and needs no root.

   ```bash
   build/build-libva-v4l2-request.sh
   ```

5. Use the layer in the programs that you start from a shell:

   ```bash
   export LIBVA_DRIVERS_PATH=$HOME/.local/lib64/dri LIBVA_DRIVER_NAME=v4l2_request
   ```

   GStreamer needs `GST_VA_ALL_DRIVERS=1` as well.

**Verify.** The kernel log shows `booting hw version` for the `avd` device and no error. There is no `/dev/video*` check script. The project tested with GStreamer (`vah264dec`, `vah265dec`, `vavp9dec`, `vaav1dec`) and `ffmpeg -hwaccel vaapi`. Browsers and mpv are not tested.

**Undo.** Remove the layer from `~/.local`. Remove the firmware file: `sudo rm /lib/firmware/apple/avd-fw-v4-t0.bin`. The Touch ID step also keeps a file in `/lib/firmware/apple/`, so do not delete the folder blindly.

#### 7.6 USB-C displays and Thunderbolt

**What it does.** The kernel build turns on `CONFIG_USB4_APPLE_SOC=m`. The `thunderbolt_apple` module then starts the USB-C controllers. DisplayPort over USB-C, USB 3 and host-to-host Thunderbolt work.

**Commands.** None. It is in the kernel from Step 3.

**Verify.**

```bash
lsmod | grep thunderbolt_apple
```

The module is loaded. A display on a USB-C port appears in the display settings.

**Undo.** Boot the stock kernel. Or add a modprobe file with the line `blacklist thunderbolt_apple` and reboot.

Limit: the display driver refuses sleep while a USB-C display is attached. See section 7.

#### 7.7 Wi-Fi recovery after a failed suspend

**What it does.** It installs a systemd sleep hook. If a suspend fails, the hook switches the Wi-Fi radio off and on. A good suspend does nothing.

```bash
tools/sleep-wifi-hook.sh print
```

```bash
sudo tools/sleep-wifi-hook.sh install
```

**Verify.** `tools/sleep-wifi-hook.sh status` prints `installed`. A logic test passed. The real test with a USB-C display is not done.

**Undo.**

```bash
sudo tools/sleep-wifi-hook.sh undo
```

#### 7.8 Clean camera

**What it does.** It reads the camera, removes noise and corrects colour with ffmpeg. It publishes a PipeWire source named `M3-Clean-Camera`.

```bash
tools/camera-clean.sh
```

It runs in the foreground. Ctrl+C stops it. Close other camera apps first. It needs `ffmpeg` and `pipewire-gstreamer`.

Do not turn on the ISP temporal filter in the device tree. The camera firmware hangs with it on.

**Undo.** Stop the script.

#### 7.9 Boot macOS once from Fedora

**What it does.** It installs `asahi-bless` and `/usr/local/sbin/agx-os`, with a sudoers rule for three subcommands. The default boot volume does not change.

```bash
sudo install/setup-macos-switch.sh
```

```bash
sudo -n /usr/local/sbin/agx-os macos-once && sudo -n systemctl reboot
```

**Verify.** `sudo -n /usr/local/sbin/agx-os status` shows the default and next boot volumes. `agx-os clear-next` cancels the next macOS boot.

**Undo.**

```bash
sudo rm /usr/local/sbin/agx-os /etc/sudoers.d/agx-os
```

#### 7.10 Local AI with llama.cpp on the GPU

**What it does.** It builds llama.cpp with Vulkan and runs `llama-bench` on the GPU and the CPU. It lives in the sibling repository `ane-linux`. Use it on a GPU boot.

```bash
ane-linux/llm/stage0.sh deps
```

```bash
ane-linux/llm/stage0.sh build
```

```bash
ane-linux/llm/stage0.sh models
```

```bash
ane-linux/llm/stage0.sh bench
```

```bash
ane-linux/llm/stage0.sh check
```

`models` downloads about 7 GB. `check` runs the same prompt on the GPU and the CPU. The text must match. On the tested Mac, Llama 3.1 8B (Q4_K_M) runs at about 150 tokens/s for the prompt and 22.7 tokens/s for the output.

**The `iq2_s` fix.** Honeykrisp refuses the `iq2_s` mat-vec shader with three or more columns. The patch `ane-linux/llm/llama-vk-honeykrisp-iq2s-matvec-cols.patch` sends those widths to the matrix path. The script does not apply it. Apply it to the llama.cpp tree before you build, if you use `iq2_s` models:

```bash
git -C ~/llm-work/llama.cpp apply /path/to/ane-linux/llm/llama-vk-honeykrisp-iq2s-matvec-cols.patch
```

**Undo.** Delete `~/llm-work`.

### Step 8. Fedora kernel RPM (preview)

**What it does.** The sibling repository `distro-pack` has one tool, `agx`. It can plan and build this kernel as a Fedora RPM. It uses the same patch series as Step 3. The real install (`--apply`) is not enabled. Nothing from the RPM is installed on a real boot yet. Use Step 3 and Step 5 for a working install.

Safe commands (they change nothing):

```bash
distro-pack/agx detect
```

```bash
distro-pack/agx plan-install
```

Check that the patches apply on the pinned kernel (nothing is built):

```bash
distro-pack/agx build-kernel --src ~/agx-work/src/linux
```

Build the package (it installs nothing):

```bash
distro-pack/agx build-kernel --build --family fedora
```

On the tested Mac the build took about 18 minutes with stripped modules and made an RPM of about 95 MB. Never install the `kernel-headers` package from that build. It belongs to the C library.

### Step 9. Mac-like KDE desktop and flat lock screen

**What it does.** It restyles KDE Plasma 6 to look like macOS Sonoma and Sequoia. It is flat. It has no blur and no glass. The scripts run at user level. They need no root and install no package. Each stage makes a dated backup and an undo script in `~/desktop-design-backups/`.

You need KDE Plasma 6 on Wayland, `git`, `kwriteconfig6` and the `plasma-apply-*` tools. The first stage downloads one GPL-3.0 theme repository (WhiteSur-kde, about 26 MB). Close Dolphin and Konsole before stage 50.

**Commands.**

```bash
cd distro-pack/desktop && ./apply-all.sh light
```

Use `dark` instead of `light` for the dark look. Switch later with `m3-appearance light` or `m3-appearance dark`.

Optional stages:

```bash
./90-fit16.sh
```

It sets the display scale to 2 (1728x1080 on the 3456x2160 panel), makes one flat wallpaper and makes the dock 68 tall. Undo the scale with `kscreen-doctor output.eDP-1.scale.2.7`.

```bash
./85-motion.sh light
```

It sets a faster animation speed. It loads no new effect.

```bash
./86-icons.sh install
```

It installs the original M3 Flat icons. Other icons come from KDE Breeze.

**Flat lock screen** (not part of `apply-all.sh`):

```bash
./80-lockscreen.sh build
```

```bash
./80-lockscreen.sh test flat
```

```bash
./80-lockscreen.sh install
```

`build` makes test packages only. `test flat` shows a test window for 20 seconds without a lock. `install` makes a backup and uses the flat lock screen for real. Change its colour with `./80-lockscreen.sh colour '#0b3d91'`. It does not change PAM, `fprintd` or the login screen.

A Plasma update can change the lock screen files. A guard script then removes the user copy at login, and the stock lock screen returns. Run `./80-lockscreen.sh install` again after a big Plasma update.

The login screen needs root. `root-options/plasmalogin-flat.sh` is a draft. It is not tested.

**Verify.** The top bar, the dock and the window buttons show the new look. After `80-lockscreen.sh install`, lock the screen with Meta+L.

**Undo.**

- Run the `*-undo.sh` of the stage from `~/desktop-design-backups/`. Log out first, or run it from SSH.
- `undo-10-themes.sh` removes the downloaded themes.
- `./80-lockscreen.sh remove` brings the stock lock screen back.
- If the lock screen is stuck, run `loginctl unlock-session` over SSH.

Limits:

- The Cmd key remap needs root (keyd or kinto). The pack does not install it. A draft is in `root-options/keyd-cmd-as-ctrl.conf`. It is not applied and not tested.
- The pack uses Adwaita Sans and Hack fonts. It never uses or ships SF Pro.
- The pack does not install the WhiteSur icon and cursor sets, because they copy Apple artwork. Do not set `M3_APPLE_LOOKALIKE=1` for a build that you share.

### Step 10. File sharing

#### LocalSend (recommended)

**What it does.** LocalSend is an open-source app. It sends files over normal Wi-Fi with HTTPS. It does not use the AirDrop radio mode, so it cannot upset the Wi-Fi firmware. It needs the app on each device.

```bash
build/localsend-install.sh fetch
```

```bash
build/localsend-install.sh list
```

```bash
build/localsend-install.sh install
```

`fetch` downloads the GitHub release tarball and checks its size and SHA-256. It installs to `~/.local/opt` and needs no root. It checks for missing libraries.

The app needs TCP and UDP port 53317 in firewalld. The kit has no script for this. Open that port in the zone of your Wi-Fi interface only.

**Verify.** `build/localsend-install.sh status`. Another device on the same Wi-Fi sees the Mac. A guest network with client isolation breaks discovery.

**Undo.**

```bash
build/localsend-install.sh undo
```

#### AirDrop (optional, advanced)

**What it does.** The Broadcom BCM4388 firmware has its own AWDL engine. The kit uses it through the OpenDrop-based projects `omdrop-awdl` and `omdrop-plugin`. The Mac then shows in the AirDrop share sheet of an iPhone or Mac.

**Read the limits first.**

- It is off by default. The project keeps it off until a Wi-Fi coexistence test passes.
- A wrong state can wedge the Wi-Fi firmware. Recovery can need the console.
- During a window the radio leaves the home channel. Wi-Fi gets slower.
- "Contacts Only" is not possible. The iPhone must be on "Everyone for 10 Minutes".
- The design blocks sleep after the first window until reboot.

All steps are subcommands of one script. Nothing runs without a subcommand. See `docs/features/airdrop.md` for the details.

```bash
build/airdrop-setup.sh fetch
```

Other subcommands are `deps`, `mac`, `up`, `firewall`, `receiver`, `window N`, `send ADDR FILE`, `notify`, `status` and `undo`. Subcommands marked (root) in the script header need `sudo`. To make AirDrop survive a reboot, run `build/airdrop-persist.sh` with `root`, `user` or `ui`.

**Verify.** `build/airdrop-setup.sh status` (read-only).

**Undo.**

```bash
sudo build/airdrop-setup.sh undo
```

```bash
sudo build/airdrop-persist.sh remove
```

### Step 11. Research items (do not run)

These parts are research. They do not give you a feature.

- **Neural Engine** (`ane-linux`): no ANE code runs. An early test powered the ANE domain on and off five times. Then the Mac reset. The rollback worked. Do not load the probe module.
- **Video encode and ProRes** (`research/ave-m3/`, `docs/features/video-encode.md`): offline research. The CPU encodes.
- **GPU clock tests** (stages M, N and P): they did not give a gain, or they are not done.

### Step 12. Touch ID

Last. It needs its own preparation. Read section 6.

## 6. Touch ID

### What it gives you

- The right index finger (or the finger you choose) unlocks the KDE lock screen.
- At the login screen, a typed password logs in at once. Press Enter with an empty password field, and the screen asks for the finger for up to 5 seconds.
- Sudo, the login console and SSH keep using the password only. The files `system-auth`, `password-auth`, `login`, `sudo` and `sshd` are never edited.
- The password always works. A fingerprint line that finds no reader, no finger, no match or a timeout falls through to the password.

### Read these warnings first

> **Touch ID writes to the Secure Enclave storage (the xART store) that macOS shares.**
>
> - Linux must write xART records to make Touch ID work. The enclave saves anti-replay state after every match. A read-only mode cannot work.
> - A wrong write can damage secure storage that macOS uses. That storage holds keys for FileVault and the login.
> - A Btrfs snapshot does not cover this storage. Removing the driver does not undo a write.
> - **Take the xART backup first.** Do not start without it.
> - **Never restore an older backup.** The enclave keeps its own anti-replay state. A restored image is older than what the enclave committed. This is the rollback case that anti-replay exists to catch. Do not restore because of a PAM problem or a boot problem. Restore only for damage that the alarm check shows, and only after you read the script text.
> - **After you boot macOS or the startup options, take a new backup before the next alarm check.** Those systems write xART legitimately. Without a new backup, the alarm check shows a false alarm. Take the new backup in a boot without the driver (see "After macOS" below).
> - **The power key is the fingerprint sensor.** A short press can open the KDE logout screen or power the Mac off. Install the power key safety (below) before you enable Touch ID.
> - The project tested this on one Mac that did not use Touch ID in macOS. Macs that use Touch ID in macOS may need to enrol again there. Nobody confirmed this.
> - The false accept rate is not measured with many trials. This is why sudo stays password-only. If a wrong finger ever unlocks the lock screen or the login screen, undo the PAM steps at once (see "Switch it off and undo").
> - The backup folder holds private keys and device data (root, mode 0600). Copy it to a second computer. Never share it. Never commit it.

### What you need first

- The GPU kernel, m1n1 and desktop from section 5, with `boot.bin.stageE` made by stage E.
- The Mac on the charger.
- Packages: `fprintd`, `fprintd-pam`, and the SELinux tools the preflight names (`checkmodule`, `semodule_package`, `semodule`, `semanage`).
- No armed Touch ID or Neural Engine test window.
- Updates of m1n1 paused (stage A does it).

The Touch ID scripts expect the author's file names. They also check fixed hashes. Your builds have other hashes. See the notes under each part.

**Gaps in the docs.** Read these before you start:

- `ti-install.sh` pins the module hash, the RPM hash, the hash of `boot.bin.stageE` and the hash of the base device tree. Your files differ. See "Part 5" below for the `TI_*` overrides.

### Part 1: Install the power key safety

The sensor is the power key. A short press must never power off. The kit has a file for this. It has no install script.

1. Copy `install/power-key/50-m3-power-key.conf` to `/etc/systemd/logind.conf.d/`. The file sets a short press to "ignore" and a hold of about 5 seconds to "poweroff".
2. In KDE, set the power button action to "lock the screen". The file `~/.config/powerdevilrc` needs `PowerButtonAction=32` for AC, battery and low battery. The kit has no script for this edit.
3. Reboot.

**Verify.** A short press on the key locks the screen. A hold of about 5 seconds powers off. A hold of 10 seconds is Apple's hardware power-off.

**Undo.** Remove the file from `/etc/systemd/logind.conf.d/` and set the KDE action back.

### Part 2: Sensor calibration file

The driver needs a per-device calibration file. It is in your Mac's iBootSystemContainer partition. The file never leaves your Mac. Do not commit it.

The scripts expect the folder `~/window`. Copy the files from the kit folder:

```bash
mkdir -p ~/window/touchid ~/window/integration && cp tools/touchid/window/* ~/window/ && cp -R tools/touchid/integration/. ~/window/integration/ && cp tools/touchid/sepbio.py ~/window/touchid/
```

First run the read-only check. It writes nothing to the partition:

```bash
~/window/touchid-calib.sh
```

It prints PASS or FAIL. Then install the file:

```bash
~/window/touchid-calib.sh --install
```

This writes `/lib/firmware/apple/mesacal-j516s.bin`.

**Verify.** The file exists. **Undo.** `sudo rm /lib/firmware/apple/mesacal-j516s.bin`.

### Part 3: Take and keep the xART backup

```bash
~/window/touchid-xart.sh backup
```

It reads the partition only. It checks the APFS layout and copies the partition to `/data/touchid-backup` (change the folder with `TOUCHID_BACKUP_DIR`). It reads the partition again and compares the hashes. It writes a MANIFEST.

Look for `BACKUP PASS`. If step 1 of 4 says FAIL, stop. The driver would refuse writes too.

```bash
~/window/touchid-xart.sh verify
```

It must print `VERIFY PASS`. Copy the backup folder to a second computer. Keep it private.

Other commands: `touchid-xart.sh diff` lists the xART slots that changed against the backup (it shows kind, length and revision, never contents).

### Part 4: Build the inputs

1. **The kernel module.** `build/build-apple-sep.sh` builds it. It needs the kernel tree (`build/fetch-sources.sh`) and the kernel build folder (`build/build-kernel.sh`) from section 5. It copies `drivers/soc/apple` to `~/agx-work/apple-sep-build`, applies the patches of `patches/touchid/` in this order: `t6030-profile`, `t6030-sepos13`, `sensor-probe`, `guard-loaded-only`, `sensor-poll-trace`, `sensor-rearm` and `sensor-rearm-settle`. It builds the module against your build folder. The kernel tree and build folder stay unchanged.

   To check only that the patches apply, run it with `PATCH_ONLY=1`.

   ```bash
   PATCH_ONLY=1 build/build-apple-sep.sh
   ```

   Then build the module.

   ```bash
   build/build-apple-sep.sh
   ```

   The script checks that the vermagic equals your kernel release. The module is `~/agx-work/out/touchid/apple-sep.ko`. The last lines show the two `TI_*` variables for the installer. Keep them for Part 5. The hash of your module differs from the author's hash that the installer pins. `WITH_ENTROPY_TRACE=1` adds the diagnostic patch `sep-entropy-trace.patch`. Leave it off for normal use. The module must have the parameter `sensor_rearm_mode`. The installer checks for it. Do not unload the module after it loads. Reboot instead.

   Build the module again after each kernel rebuild. A module for another kernel release does not load.
2. **The private libfprint RPM.** The recipe is `tools/touchid/packaging/libfprint-aurora.spec`. It builds libfprint 1.94.100 with the aurora Apple SEP driver under `/opt/aurora-sep`. The distro `libfprint` is not touched. The patch is in your SiliconForest kernel tree: `~/agx-work/src/linux/tools/aurora-sep/patches/libfprint-1.94.100-apple-sep.patch`. The full build plan with every command is `docs/features/touchid-libfprint-build-plan.md`. In short:

   ```bash
   mkdir -p ~/aurora-build && cp tools/touchid/packaging/libfprint-aurora.spec ~/aurora-build/
   ```

   ```bash
   sudo dnf builddep ~/aurora-build/libfprint-aurora.spec
   ```

   Read the transaction before you answer yes. Stop if it removes or upgrades an installed package.

   ```bash
   mkdir -p ~/aurora-build/srpm ~/aurora-build/rpmbuild/SOURCES ~/aurora-build/rpmbuild/SPECS && cd ~/aurora-build/srpm
   ```

   ```bash
   dnf download --source libfprint
   ```

   ```bash
   rpm -K libfprint-*.src.rpm
   ```

   The digests and signatures must be OK. The version must equal `rpm -q libfprint`. Then follow sections 5 and 6 of the build plan (unpack the tarball, copy the patch, copy the spec, check `git apply --check`, run `rpmbuild`). The RPM appears in `~/aurora-build/rpmbuild/RPMS/aarch64/`. It must list files only under `/opt/aurora-sep`.

### Part 5: Install

Authenticate sudo first, so that `sudo -n` works. The install checks the charger, takes a backup, builds the new boot file as a dry run and then runs the root installer.

The installer pins the author's files by hash. Your builds have other hashes. Set the `TI_*` variables below in your shell. `ti-run.sh` and `ti-install.sh` read them. `ti-run.sh` passes every `TI_*` variable, and `TOUCHID_BACKUP_DIR`, through `sudo` to the installer.

| Variable | Meaning | Default |
|---|---|---|
| `TI_MODULE` | Path of your `apple-sep.ko` | `~/window/touchid/apple-sep-3f.ko` |
| `TI_MODULE_SHA` | SHA-256 of your module | The author's module |
| `TI_RPM` | Path of your `libfprint-aurora` RPM | `~/aurora-build/rpmbuild/RPMS/aarch64/libfprint-aurora-1.94.100-1.fc44.aarch64.rpm` |
| `TI_RPM_SHA` | SHA-256 of your RPM | The author's RPM |
| `TI_STAGEE_SHA` | SHA-256 of `/boot/efi/m1n1/boot.bin.stageE` | The author's file |
| `TI_BASE_DTB_PFX` | First 8 characters of the SHA-256 of `/boot/dtb-<release>/apple/t6030-j516s.dtb` | The author's value |
| `TI_KREL` | Your kernel release | `7.2.11-m3gpu+` |
| `TI_BOOT_NEW`, `TI_BOOT_DTB` | The new boot file and merged device tree that the boot script builds | `~/window/touchid/dry/expected-boot.bin.sep` and `~/window/touchid/work/merged.dtb` |
| `TI_ALLOW_BATTERY` | `1` allows an install on battery power at 80 % or more | Off |
| `TI_UHOME` | The home folder that holds the files above | The home folder of the sudo user |
| `TI_WINDOW` | The window folder (`ti-run.sh` only) | `~/window` |
| `TOUCHID_BACKUP_DIR` | Folder of the xART backup | `/data/touchid-backup` |

Set them, then run the installer. Replace the values with your own:

```bash
export TI_MODULE=~/agx-work/out/touchid/apple-sep.ko
export TI_MODULE_SHA=$(sha256sum "$TI_MODULE" | cut -d' ' -f1)
export TI_RPM=$(ls ~/aurora-build/rpmbuild/RPMS/aarch64/libfprint-aurora-*.rpm)
export TI_RPM_SHA=$(sha256sum "$TI_RPM" | cut -d' ' -f1)
export TI_STAGEE_SHA=$(sha256sum /boot/efi/m1n1/boot.bin.stageE | cut -d' ' -f1)
export TI_BASE_DTB_PFX=$(sha256sum /boot/dtb-$(uname -r)/apple/t6030-j516s.dtb | cut -c1-8)
export TI_KREL=$(uname -r)
```

Run the checks first. They change nothing. Fix every `FAIL` line first.

```bash
cd ~/window/integration && sudo env TI_MODULE="$TI_MODULE" TI_MODULE_SHA="$TI_MODULE_SHA" TI_RPM="$TI_RPM" TI_RPM_SHA="$TI_RPM_SHA" TI_STAGEE_SHA="$TI_STAGEE_SHA" TI_BASE_DTB_PFX="$TI_BASE_DTB_PFX" TI_KREL="$TI_KREL" ./ti-install.sh preflight
```

Then install. `ti-run.sh` takes the xART backup, builds the boot file as a dry run and runs the root installer:

```bash
cd ~/window/integration && ./ti-run.sh install
```

The installer runs eight steps in order: `module units selinux libfprint dropin pam-lock pam-login bootbin`. The boot file step is last. If a step fails, the script undoes the steps of that run. After `pam-login` it runs a password test. You type your account password. A wrong password must be refused and the right one accepted, for the services `kde` and `plasmalogin`. If the test fails, everything of the run is undone.

Stop rules:

- Any `FAIL` in preflight: nothing changed. Fix the cause or stop.
- `STEP FAILED` or `PASSWORD TEST FAILED`: the script undoes the run. Do not retry by hand.
- A prompt that asks for anything else than your account password: stop.

The output ends with `ALL STEPS APPLIED`. Nothing is loaded and nothing is rebooted.

**What each step does:**

| Step | What it does |
|---|---|
| `module` | Puts the module in `/lib/modules/<release>/updates/apple_sep.ko` and runs `depmod`. |
| `units` | Installs `m3-touchid-load`, the unit `m3-touchid.service` (enabled), `/etc/m3-touchid.conf` and a copy of the installer. |
| `selinux` | Installs the policy module `m3touchid`. Labels `/opt/aurora-sep` as `lib_t`. |
| `libfprint` | Installs the `libfprint-aurora` RPM. |
| `dropin` | Adds a `fprintd` drop-in with the private library path and device access. |
| `pam-lock` | Replaces `/etc/pam.d/kde-fingerprint`. The original is saved. |
| `pam-login` | Creates `/etc/pam.d/plasmalogin` from the vendor file with two added lines. |
| `bootbin` | Writes `boot.bin.stageS` (stageE with only the J516S device tree replaced) and makes it `boot.bin`. `boot.bin.stageE` stays as the fallback. |

### Part 6: Reboot, verify, enrol

Reboot once. The boot uses `boot.bin.stageS`. Log in with the password. Then:

```bash
cd ~/window/integration && ./ti-run.sh verify
```

This runs the checks and the alarm check. Look for `VERIFY AND ALARM CHECK OK`. If it says NOT OK, do not enrol. The verify step reads `TI_KREL`. If your release is not `7.2.11-m3gpu+`, export `TI_KREL` again in a new shell.

Then check by hand:

1. Log out. The password must log in.
2. Lock the screen with Meta+L. The password must unlock it.

Then enrol:

```bash
cd ~/window/integration && ./ti-run.sh enroll right-index-finger
```

The script stops `fprintd` and lists the identities in the enclave. On a fresh install the list is empty, and the script goes on to the enrolment. If the list holds an identity, the script asks you to type `DELETE`. It then removes all identities, because an identity made outside `fprintd` would win the match and break it. If you answer anything else, the script stops and does not enrol. Then it runs `fprintd-enroll`. Touch and lift as asked. Stop after 3 failed tries. Then it runs `fprintd-verify`.

Last checks by hand. Lock the screen and rest the finger on the key for about 2 seconds without pressing. It unlocks. A wrong finger must not unlock.

### Daily use and limits

- Rest the finger on the key for about 2 seconds. A late touch can need a second try.
- The lock screen checks the finger and the password field at the same time.
- A fingerprint cannot unlock KWallet. The first app that asks for a stored secret asks for the wallet password.
- Suspend and resume with Touch ID loaded are not tested. Use the password after a resume if the finger does not work.
- Each boot with the driver writes xART records. The alarm check must say OK after the first boot.
- A kernel update does not change `boot.bin`. But the new kernel has no `apple_sep` module, so Touch ID does nothing there. Build and install the module for the new kernel first.
- Making `boot.bin.stageE` the boot file again (for example with the author's `m3gpu-default gpu`) removes the Secure Enclave from the next boot. `sudo m3-touchid-install verify` then says `boot.bin is not stageS`.
- Tune the capture rest time with `sudo m3-touchid-install settle MS` (300 to 3000). The tested value is 1800.
- `sudo m3-touchid-install relogin` re-applies only the login screen step, with the password test.

### Switch it off and undo

From the mildest to the strongest. Each level needs less than the one above.

1. **Stop loading the driver, keep everything installed.**

   ```bash
   sudo touch /etc/m3-touchid.off
   ```

   Reboot. The password still works. The fingerprint lines find no reader and fall through. To switch it on again, remove the file and reboot. A one-boot alternative is to add `m3.touchid=off` to the kernel command line in the GRUB menu (press `e`).

2. **Undo one step or all steps.** It works from a text console (Ctrl+Alt+F3) or over SSH. No working Touch ID is needed.

   ```bash
   sudo m3-touchid-install status
   ```

   ```bash
   sudo m3-touchid-install undo pam-lock pam-login
   ```

   ```bash
   sudo m3-touchid-install undo
   ```

   The same through the wrapper: `ti-run.sh undo [STEP ...]`. The `bootbin` undo copies `boot.bin.stageE` back to `boot.bin`.

3. **Put the old boot file back by hand.**

   ```bash
   sudo cp /boot/efi/m1n1/boot.bin.stageE /boot/efi/m1n1/boot.bin
   ```

4. **Linux does not boot.** Use the macOS rollback from section 4. It puts `boot.bin.stock` back.

Undo does not remove the identities in the enclave or the records that Linux wrote to the xART store. The docs describe no way to remove the records. **Never restore an xART backup as part of an undo.**

### After macOS or the startup options

The startup options and macOS write xART records. This makes the alarm check fail against the old backup. This is a false alarm. Do this:

1. Create the off switch: `sudo touch /etc/m3-touchid.off`.
2. Reboot.
3. Take a new backup: `~/window/touchid-xart.sh backup`.
4. Remove the off switch: `sudo rm /etc/m3-touchid.off`.
5. Reboot.

Then run the alarm check:

```bash
~/window/touchid-3b.sh alarm
```

It compares the partition with the newest backup. The result must be OK. An ALARM means: stop. Switch Touch ID off. Do not restore anything. Ask the project.

### Touch ID troubleshooting

| Problem | What to do |
|---|---|
| Preflight says a hash differs | Your files are not the author's. Pass your own hashes (Part 5). Check that you really use your own files. |
| `m3-touchid.service` is not active | `journalctl -u m3-touchid` shows the cause. The boot may not have the Secure Enclave nodes (boot file is not stageS). |
| `verify` says `boot.bin is not stageS` | Another step changed `boot.bin`. Run the `bootbin` step again: `sudo ./ti-install.sh step bootbin apply`. |
| `fprintd-list` sees no reader | `fprintd` must start after the unit. Check the drop-in with `systemctl show fprintd.service -p Environment`. |
| SELinux denial | `ausearch -m avc -ts boot` shows the detail. `verify` lists denials for `fprintd` and `sep-bio`. |
| The finger does not match | Rest the finger for about 2 seconds. Try `settle` with another value. Use the password. |
| The finger works over SSH tests | It does not. `pam_fprintd` refuses remote sessions. Test from a local session. |
| The lock screen does not accept the finger after a test | A test can hold the reader. Unlock once with the password. |
| The alarm check says ALARM | See "After macOS". If the cause is not macOS, stop and ask the project. |

## 7. Known problems and troubleshooting

### Known problems

| Area | Problem | What to do |
|---|---|---|
| Sleep | Only `s2idle` sleep is offered, not deep sleep. Expect the battery to drain while the Mac sleeps. The project did not measure how fast. Idle power with the memory floor can also be higher than on the stock kernel (not measured). | Treat sleep as a short pause. Shut down for long breaks. |
| Sleep | Lid close suspends (it does not power off). A suspend with a USB-C display attached is refused on purpose (error -16). | Unplug the USB-C display before sleep. |
| Network | After a refused suspend, Wi-Fi can stay down. In one case NetworkManager kept Wi-Fi asleep for about 26 minutes. A driver reload brought it back. | Install the Wi-Fi hook (Step 7.7). Or reload the driver. |
| Network | After each resume the log shows `p2p-dev` errors (-52 and -16). They are harmless while AirDrop is off. | Ignore them. |
| Network | AirDrop can disturb Wi-Fi. | Keep AirDrop off. Use LocalSend. |
| Power | Once, the SMC stopped seeing the charger for about 30 minutes under heavy GPU load. The cause was not found. Unplugging and plugging the charger fixed it. | Replug the charger. Use a charger rated for the Mac. |
| Bluetooth | The chip can time out after a resume. The patched driver resets it in about 1 s. | Part of the kernel patch. |
| GPU | A GPU fault could crash KWin and the desktop in earlier builds. The recovery patch (stage O content) fixed it in the forced fault test. | Keep `g15-recovery-drain-halt.patch` in every kernel build. |
| GPU | Bursts of GPU work can drop to the lowest clock after about 20 s of a program's life. Stop-and-go work is up to 4 times slower. Full load stays at the top clock. | No fix yet. |
| GPU | The driver refuses unknown GPU firmware builds. The GPU stays off. | See `docs/gpu-firmware-investigation.md`. |
| Display | 120 Hz is fixed. No adaptive refresh. Colour is sRGB only. No HDR. | No fix planned. |
| Display | HDMI 4K at 60 Hz and HDMI audio are not tested. | |
| Boot | In some stage D boots the microphone card is missing (audio coprocessor crash). It is intermittent. | Reboot. |
| Boot | `M1N1_UPDATE_DISABLED=1` stops automatic m1n1 updates. | Keep it while you use these boot files. |
| Kernel | A kernel update installs a stock kernel. It has no GPU driver, no fan patch and no Touch ID module. | Boot your kernel from the GRUB menu. Rebuild for new kernels. |
| Memory | The tested Mac has 18 GB. Builds and local AI can cause out-of-memory events. | Close other heavy programs. |
| Camera | The sensor grain stays. The driver has no exposure or gain control. | Use `tools/camera-clean.sh`. |
| Audio | The listening test of the speakers is not complete. The headphone jack is not tested. | |
| Touch ID | See section 6. | |
| Neural Engine | Not usable. | Do not load the probe module. |

### Troubleshooting

**The desktop does not start after stage G.** Press Ctrl+Alt+F3. Log in. Run `sudo touch /etc/agx-native-mesa.off`. Reboot.

**The GPU does not start.** Look for the line `unsupported GPU firmware build` in `journalctl -k -b`. It prints the hash of your firmware. Read `docs/gpu-firmware-investigation.md`. Do not force an unknown build with the prefix override.

**The Mac boots to the stock kernel.** This is the default. Use the `test-once` boot from Step 5 for a GPU boot.

**Check the boot setup.**

```bash
sudo -n /usr/local/sbin/agx-boot status
```

```bash
grub2-editenv list
```

**Turn the GPU options off for every kernel.**

```bash
sudo -n /usr/local/sbin/agx-boot use-stageD
```

Or `use-stock` for the stock boot file.

**Linux does not boot at all.** Use the rollback from macOS in section 4.

**Read the kernel log for GPU or display problems.**

```bash
journalctl -k -b
```

**The lock screen is stuck.** Run `loginctl unlock-session` over SSH.

**A bug report.** First boot the stock kernel with `sudo -n /usr/local/sbin/agx-boot use-stock`. Repeat the problem there. If it happens on stock Asahi, report it to the Asahi Linux project. If it happens only with the kit kernel, Mesa or patches, do not report it to Asahi Linux. Ask the community projects named in section 8.

## 8. Credits

This project stands on the work of many people. Thank you to:

- **The Asahi Linux developers and community.** They made Linux on Apple silicon possible: the installer, m1n1, the kernel drivers, the firmware handling and the documentation. See [asahilinux.org](https://asahilinux.org/) and the [M3 feature support page](https://asahilinux.org/docs/platform/feature-support/m3/).
- **The Linux kernel developers.**
- **The Mesa developers.** The GPU stack builds on Mesa and the Asahi Mesa work.
- **The SiliconForest projects.** The kernel, m1n1 and Mesa trees come from `iconidentify/siliconforest-linux`, `siliconforest-m1n1` and `siliconforest-mesa`. They are based on `omacom/linux-aurora` ([github.com/omacom/linux-aurora](https://github.com/omacom/linux-aurora)).
- **The aurora Apple SEP work.** The Secure Enclave driver and the libfprint driver patch come from the aurora projects ([github.com/iconidentify/aurora-linux](https://github.com/iconidentify/aurora-linux)).
- **libfprint and fprintd.** Fingerprint support for Linux ([gitlab.freedesktop.org/libfprint/libfprint](https://gitlab.freedesktop.org/libfprint/libfprint)).
- **KDE and the Plasma developers.** The desktop, the lock screen and the Plasma Login Manager.
- **WhiteSur-kde** by vinceliuice. The colours and window shapes ([github.com/vinceliuice/WhiteSur-kde](https://github.com/vinceliuice/WhiteSur-kde), GPL-3.0).
- **llama.cpp.** The local AI runs on its Vulkan backend.
- **AsahiLinux/avd-fw.** The video decoder firmware source ([github.com/AsahiLinux/avd-fw](https://github.com/AsahiLinux/avd-fw)).
- **libva-v4l2_request** (sofus13 and the earlier work it builds on). The VA-API layer for the decoder.
- **LibrePods** ([github.com/kavishdevar/librepods](https://github.com/kavishdevar/librepods)). AirPods features on Linux.
- **omdrop-awdl and omdrop-plugin** by netmojo-systems, and the OpenDrop work behind them. AirDrop on Linux.
- **LocalSend** ([github.com/localsend/localsend](https://github.com/localsend/localsend)).
- **aquarat/apple-m-series-ave-driver.** The video encoder driver that the encoder research builds on.

Apple, macOS, AirDrop and Touch ID are names of Apple products. This project is not affiliated with Apple.
