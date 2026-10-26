# Install and first test boot: plan

Date: 2026-10-26. Status: **plan only. Nothing is changed yet.** Each stage needs your go-ahead.

> Paths: this plan was written before the repository layout. The scripts it names were in `~/m3gpu/scripts/` on the M3. In this repository they are in `install/` (stages, `make-bootbin.sh`, `use-bootbin.sh`, `setup-nopasswd.sh`), `system/` (templates for `m3gpu-boot` and the sudoers rule) and `build/`. The results of every stage are in the sections below and in `README.md`.

## 1. How the M3 boots today (read on the M3, read only)

```
Apple stub (macOS 14.7 firmware, APFS nvme0n1p3)
  -> m1n1 stage 1 v1.6.1
  -> ESP nvme0n1p4 (vfat, /boot/efi, PARTUUID <esp-partuuid>)
       /m1n1/boot.bin = m1n1 stage 2 + device trees + U-Boot + m1n1.conf options
  -> U-Boot -> GRUB (/boot, nvme0n1p5) -> kernel
```

Facts that shape the plan:

- **One device tree for all kernels.** m1n1 picks the DTB for `apple,j516s` from `boot.bin`, edits it, and passes it on. GRUB cannot give a different DTB to each kernel without losing m1n1's edits. So a new DTB in `boot.bin` also reaches the Fedora fallback kernel.
- **`boot.bin` is rebuilt automatically.** `update-m1n1` runs from the kernel-install hook `15-update-m1n1.install` and on m1n1 or U-Boot updates. It reads `/etc/sysconfig/update-m1n1` (`DTBS=/boot/dtb`) and `/etc/m1n1.conf`. It keeps the previous file as `boot.bin.old`.
- **`kernel-install` would also move `/boot/dtb` and the default boot entry** (`10-devicetree.install`, `95-set-boot-entry.install`). So we install the new kernel by hand, not with `kernel-install`.
- **Firmware match with SiliconForest's tested J516S release** (`v2026.10.19-j516s-pr363.1`, `release.json`):

| Item | Our M3 | SiliconForest release | Match |
|---|---|---|---|
| Board | `apple,j516s` | `apple,j516s` | Yes |
| OS firmware (stub) | 14.7 | 14.7 | Yes |
| iBoot2 | iBoot-10151.140.19.700.2 | iBoot-10151.140.19.700.2 | Yes |
| m1n1 stage 1 | v1.6.1 | v1.6.1-dirty | Close, not exact |
| `t6030-j516s.dtb` SHA-256 | `18baac96...47c` | `18baac96...47c` | **Yes, identical** |
| m1n1 stage 2 SHA-256 | `3118c16f...` (our build) | `db98796e...` (their build) | No (separate builds of the same commit) |
| Boot loader after m1n1 | U-Boot + GRUB | U-Boot + Limine (UKI) | Different |

- Their m1n1 options for J516S: `chosen.asahi,t6030-gpu=1`, `chosen.asahi,t6030-dcp=1`, `chosen.asahi,t6030-dcpext=1`.
- Their report says hardware OpenGL and Vulkan, the internal panel at 3456x2234 120 Hz, and 0 GPU faults. Their own `profiles.json` still says `"qualified": false` for this profile. Treat the claims as unverified until our own test.

## 2. Stages

Each stage changes one thing. Stop at any stage and roll back.

### Stage A: backups and a rollback rehearsal (no boot change)

In Fedora (needs your Fedora password once):

1. Copy `/boot/efi/m1n1/boot.bin` to `/boot/efi/m1n1/boot.bin.stock`. Record its SHA-256.
2. Copy the same file to `/root/m3gpu-backup/` and to this Mac (the host).
3. Back up `/etc/m1n1.conf`, `/etc/sysconfig/update-m1n1`, `/boot/loader/entries/`, `/boot/grub2/grubenv`.
4. Pause automatic `boot.bin` rebuilds for the test: add `M1N1_UPDATE_DISABLED=1` to `/etc/sysconfig/update-m1n1`. Without this, a Fedora kernel update would silently replace our test `boot.bin`. We remove this line at the end.

Rollback rehearsal from macOS (needs your macOS password once, and you at the Mac):

5. Hold the power button, choose Macintosh HD.
6. From the host, `ssh m3` over the USB-C link. Run `diskutil list` and find the ESP by its partition UUID `<esp-partuuid>-...`.
7. Mount it (`sudo diskutil mount diskXsY`), check `m1n1/boot.bin.stock` and its SHA-256, then unmount. **Change nothing.**
8. Boot back into Fedora (the default).

**Done when:** the backup hashes match, and the ESP was mounted and read from macOS.

### Stage B: install Mesa and the kernel, keep booting the stock setup

1. Copy Mesa to `/opt/mesa-m3`. No system file points to it, so nothing uses it yet.
2. Install the kernel by hand: `/lib/modules/7.2.11-m3gpu+`, `/boot/vmlinuz-7.2.11-m3gpu+`, `/boot/dtb-7.2.11-m3gpu+`, an initramfs from `dracut`, and one GRUB entry. **Do not** run `kernel-install`. **Do not** change `/boot/dtb` or the default entry.
3. (Dropped: `blacklist apple_sep`. The test kernel has no SEP module, and a blacklist would also change the Fedora kernel.)
4. Boot the new kernel once with `grub2-reboot` (the next boot only). `boot.bin` is still stock, so it gets Fedora's DTB and no GPU.

**Checks:** it boots to the desktop, Wi-Fi, keyboard, trackpad, USB work, no kernel oops in `journalctl -k`.
**Rollback:** reboot. The default is still the Fedora kernel.

**Stage B result (2026-10-26, 11:30): passed.** `7.2.11-m3gpu+` booted once via `next_entry` to the KDE login. No failed units, no kernel oops. Wi-Fi, Tailscale, keyboard, trackpad, camera, Bluetooth and both sound cards present. Display on simpledrm (expected with Fedora's DTB; log: "apple-t6030-display: not enabling: need exactly one apple,t6030-dcp node"). `avd` needs `apple/avd-fw-v4-t0.bin`, which is not installed. Correction after stage C: this is **not** a regression. The same error is in every Fedora 7.1.13 boot with the stock m1n1 (boots at 10:54 and 11:30). Hardware video decode does not work on this machine with either kernel. Default entry still Fedora 7.1.13.

**Helper check:** `make-bootbin.sh` uses the same assembly as `update-m1n1`. A user-space rebuild with Fedora's m1n1, DTBs and U-Boot matched `boot.bin.stock` exactly (`00efa22c...`).

### Stage C: new m1n1 with Fedora's DTB, no options

1. Build `boot.bin.stageC` = our m1n1 + Fedora's DTBs + Fedora U-Boot + current `m1n1.conf`. Copy it to `boot.bin`.
2. Boot the **Fedora** kernel.

This tests only the new m1n1 code on our firmware (its self-relocation, display log reservation and DART lock), with nothing else new.

**Checks:** it boots, `/proc/device-tree/chosen/asahi,m1n1-stage2-version` shows the SiliconForest version, the screen and USB work.
**Rollback:** from Fedora, copy `boot.bin.stock` back. If Fedora does not boot: use the macOS steps in section 3.

**Stage C result (2026-10-26, 11:57): passed.** `boot.bin.stageC` SHA-256 `bccf316d...32c3` (8,836,770 bytes): our m1n1 `3118c16f...` + Fedora DTBs + Fedora U-Boot, no options. The Fedora 7.1.13 kernel booted to the KDE login in under 1 minute. `chosen` shows `asahi,m1n1-stage2-version = aca1258`, plus the new `asahi,t6030-pmp` and `asahi,t6030-display-facts` exports. New `dcp-oslog@...` reserved-memory nodes (3). No failed units, no oops, Wi-Fi, Tailscale, sound and camera present, 33 °C.

### Stage D: new m1n1 with the SiliconForest j516s DTB, no options

1. Build `boot.bin.stageD` = our m1n1 + our `t6030-j516s.dtb` (identical to theirs) + U-Boot + `m1n1.conf`. Copy it to `boot.bin`.
2. Boot the new kernel once (`grub2-reboot`). m1n1 runs the GPU code as a dry run only, and the GPU stays off.
3. Then boot the **Fedora** kernel once, to test the fallback with the new DTB.

**Checks:** both kernels boot; the GPU node exists but is disabled; the new kernel log names the GPU firmware.
**Rollback:** copy `boot.bin.stageC` or `boot.bin.stock` back.

**Stage D result, test kernel (2026-10-26, 12:13): passed, with one regression.** `boot.bin.stageD` SHA-256 `fa029bd2...c3d3` (9,481,785 bytes), DTB hash check passed (`18baac96...`). `7.2.11-m3gpu+` booted to the login, no failed units, no oops, Wi-Fi up, 40 °C.

- GPU node present: `/soc/gpu@292400000`, `apple,agx-t6030 apple,agx-g15x apple,agx-g15s`, `status=disabled` (expected without the option).
- Display: "the boot loader did not set apple,t6030-handoff", so the DCP stays disabled and simpledrm is used (expected without `t6030-dcp=1`). `chosen` now has `asahi,t6030-dispext = 1`.
- **Regression:** the AOP firmware (`RTKit-2419.140.12.debug`, `mac15saop`) crashes at start: data abort, ESR `0x96000007`, FAR `0x10e0000`. `apple_aop` probe fails with -62, and the "J516 HPAI" sound card (internal microphones) is gone. With Fedora's DTB on the same kernel (stage B) the AOP started normally. So the SiliconForest j516s DTB's AOP description does not fit this machine. Not needed for the GPU. Resets on reboot.

**Stage D result, Fedora fallback (2026-10-26, 12:18): passed.** Fedora 7.1.13 booted with `boot.bin.stageD` to the KDE login, no failed units, Wi-Fi up, simpledrm. The AOP started normally and both sound cards (including "J516 HPAI") are present. So the AOP crash happens only with the test kernel **and** the j516s DTB together (test kernel + Fedora DTB: fine; Fedora kernel + j516s DTB: fine).

### Stage E: turn the GPU and the native display on

1. Add SiliconForest's three options to a copy of the config: `chosen.asahi,t6030-gpu=1`, `chosen.asahi,t6030-dcp=1`, `chosen.asahi,t6030-dcpext=1`. Build `boot.bin.stageE`. Copy it to `boot.bin`.
2. Boot the new kernel once (`grub2-reboot`).

**Checks:**

- `/dev/dri/renderD*` exists and its device is `apple,agx-t6030`.
- The kernel log shows the G15 firmware identified, no GPU faults.
- With the new Mesa for one program only:
  `LD_LIBRARY_PATH=/opt/mesa-m3/lib64 VK_DRIVER_FILES=/opt/mesa-m3/share/vulkan/icd.d/asahi_icd.aarch64.json glxinfo -B` and `vkcube`.
- The desktop still uses Fedora's Mesa. Fedora's Mesa will most likely refuse the new GPU interface and use software rendering. If the desktop fails to start, use a text console (Ctrl+Alt+F3) or roll back.

**Rollback:** copy `boot.bin.stageD` back and boot the Fedora kernel. If Fedora does not boot: section 3.

**Known risk:** with the native display handoff on, the Fedora 7.1 kernel may not drive the screen. Do not use stage E's `boot.bin` with the Fedora kernel.

**Stage E result (2026-10-26, 12:28): native display works, GPU blocked by firmware identity.**

- `boot.bin.stageE` SHA-256 `f3197272...0725`, options `chosen.asahi,t6030-gpu=1`, `t6030-dcp=1`, `t6030-dcpext=1`. Test kernel booted in about 75 s to the login. No failed units.
- **Native display: works.** `apple-drm` (`apple,t6030-display-subsystem`) on `card1`, `eDP-1` connected at 3456x2160, simpledrm gone. **Brightness control works**: `/sys/class/backlight/apple-panel-bl` = 140/500. dcpext0/dcpext1 enabled with Type-C routes. PMP started.
- **GPU: refused, safely.** `asahi-g15 292400000.gpu`:
  - "unsupported GPU firmware build: TEXT 0x5c000 DATA 0x114000 GKTS 0x58e88 sha256 cd05af6a828b52e4c2fed20086d3d18a7db42e03a8fd6f8354f9f06e0a61363e; to have it supported, report this line and the macOS version of the boot chain that loaded it"
  - "supported: macOS 14.7-14.8.x stub firmware (iBoot-10151.140.19.700.2)" and "supported: J516S B0 RTKit-2419.140.12 (maintained 14.x handoff)"
  - "loaded GFX TEXT identity mismatch: EINVAL", probe failed -22. No `renderD*` node. The GPU firmware was not started.
  - The j516s DTB says `apple,firmware-version = 14 8 3`. Our stub is 14.7, iBoot2 `iBoot-10151.140.19.700.2` (matches the listed one), system firmware 15.6.
- AOP started normally on this boot (both sound cards present), so the stage D AOP crash is intermittent.
- Mesa tests not possible without a render node.
- After the checks, `boot.bin` was switched back to stage D (`fa029bd2...`) so a Fedora-kernel boot stays safe.

## 3. Rollback from macOS (when Fedora does not boot)

1. Hold the power button until the startup options appear. Choose Macintosh HD.
2. From the host: `ssh m3`.
3. `diskutil list`, find the ESP (`<esp-partuuid>-...`), then `sudo diskutil mount diskXsY` (you type the macOS password).
4. `sudo cp <ESP>/m1n1/boot.bin.stock <ESP>/m1n1/boot.bin`, check the SHA-256, `sudo diskutil unmount diskXsY`.
5. Restart. Fedora boots with the stock setup.

macOS stays offline the whole time. The USB-C link does not need Wi-Fi.

**Rehearsed on 2026-10-26 (stage A).** In macOS 15.6.1 the ESP is `disk0s4`, volume "EFI - FEDOR", UUID `<esp-partuuid>`. A read-only mount showed `boot.bin` and `boot.bin.stock`, both SHA-256 `00efa22c96ecba6718e880d74578dd61546ecae7553a69c003f2c0d5879f555d`. Exact rollback command, typed in a host terminal tab:

```
ssh -t m3 'sudo diskutil mount disk0s4 && cp "/Volumes/EFI - FEDOR/m1n1/boot.bin.stock" "/Volumes/EFI - FEDOR/m1n1/boot.bin" && shasum -a 256 "/Volumes/EFI - FEDOR/m1n1/boot.bin" && sudo diskutil unmount disk0s4'
```

Expected hash after the copy: `00efa22c...555d`. A fourth copy is on the host: `m3gpu/backup/boot.bin.stock`.

## 4. What I need from you

- Your Fedora password at stages A, B, C, D and E (in a terminal tab).
- Your macOS password once in stage A, and again only if a rollback needs macOS.
- To be at the Mac for stage A's rehearsal and for any boot that may fail.

## 5. Clean-up after testing

- Keep or remove the test kernel and `/opt/mesa-m3`.
- Put back the chosen `boot.bin` permanently, or restore `boot.bin.stock`.
- Remove `M1N1_UPDATE_DISABLED=1`, so Fedora updates work normally again. Note: with that line removed, the next Fedora kernel update rebuilds `boot.bin` with Fedora's m1n1 and DTB, which turns the GPU setup off again.
