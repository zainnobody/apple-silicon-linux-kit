# Devices without a working driver on the M3 Pro 16-inch (J516S, Mac15,7)

Date: 2026-10-26. Machine: `user@<m3-tailscale-ip>`, kernel `7.2.11-m3gpu+` (private GPU build, source `~/m3gpu/src/linux`, head `0e1f46661376`, 2026-10-19). Checks were read-only. Nothing on the M3 was changed.

## How the check was done

- `/sys/bus/*/devices/*/driver` on every bus: 0 unbound devices on PCI (5 of 5 bound). USB bus has 0 devices (nothing plugged in, so USB is untested).
- Every device tree node with a `compatible` and no `disabled` status, compared with the bound devices in `/sys/devices`. Parent nodes that never bind by design (`pmgr`, `cpufreq`, `smbios`, `timer`, `phram`, `genpd`, I2C adapters) are listed once in "Not a problem".
- `lspci -k`, `lsusb -t`, `lsmod`, `journalctl -k -b` for `probe failed`, `deferred`, `Direct firmware load`.
- Kernel source: Kconfig, `of_device_id` tables and the DTS. Online: asahilinux.org feature pages, Phoronix, LWN, lore.kernel.org.
- Not done (needs root, `dmesg_restrict=1`, debugfs is root-only). The user can run this in their own Terminal tab and send the output:

```bash
ssh user@<m3-tailscale-ip> 'sudo cat /sys/kernel/debug/devices_deferred; sudo ls -la /boot/efi/vendorfw'
```

## Table: no working driver

State key: **no driver** = node exists, nothing binds. **probe fails** = driver loaded, probe error. **deferred** = waits forever. **no node** = the device tree has no node, so no driver can bind.

| # | Device | `compatible` | Function | State on this boot | Upstream / Asahi status (links, dates) | User impact | Priority |
|---|---|---|---|---|---|---|---|
| 1 | USB4 / Thunderbolt host (ACIO + NHI, 3 ports) | `apple,t6030-usb4-acio` (`cio@701ac0000`, `@b01ac0000`, `@f01ac0000`), `apple,t6030-usb4-nhi` (child `nhi@f00000`), DARTs, `usb4-pcie-tunnel-0` | USB4, Thunderbolt, DP tunnels, PCIe tunnels | **no driver.** Driver `drivers/thunderbolt/apple.c` is in the tree and lists `t6030`, but `CONFIG_USB4_APPLE_SOC` is **not set** in `/boot/config-7.2.11-m3gpu+`. `/sys/bus/thunderbolt` is empty | Upstream: 19-patch series by Sven Peter posted 2026-08-30 ([Phoronix](https://phoronix.com/news/Linux-USB4-Apple-Silicon)). It covers XDomain and USB3 tunnels. PCIe and DP tunnels and suspend are missing. Asahi M3 page: Thunderbolt = WIP ([feature page](https://asahilinux.org/docs/platform/feature-support/m3/)). Related prep: Dybcio "non-PCIe NHI" v5, 2026-05-21, applied to thunderbolt.git/next ([LWN](https://lwn.net/Articles/1073917/)) | No Thunderbolt or USB4 devices, no tunnelled displays or docks. Probably also the cause of row 2 | **P1** |
| 2 | USB-C PD controllers on 3 ports | `apple,sn201202x` (`spmi 1-0a`, `1-0c`, `2-08`) and their `usb-c-connector` children | USB-C role, power, alt modes | **deferred**: `deferred probe pending: (reason unknown)` at 20:43:08. Controller `1-06` (role not checked) is bound (`tps6598x_source_psy_1_06`). No `usb-c-connector` device exists | Driver `drivers/usb/typec/tipd-m3/` is built (`CONFIG_TYPEC_SN201202X=m`). `core.c` returns `-EPROBE_DEFER` when the Thunderbolt switch is missing (`cd321x_tbt_switch`, lines about 1578 to 1656). **Likely cause is row 1 (source reading, not run-tested).** Asahi page: USB-PD = linux-asahi, DP Alt Mode = WIP | USB-C displays (DP alt mode), USB-C data and charging through these ports are untested or not working. Already seen: USB-C to HDMI shows nothing (see [display-hdmi.md](display-hdmi.md)) | **P1** (same fix as row 1) |
| 3 | Video decode (AVD) | `apple,t6030-avd`, `apple,t8122-avd` (`avd@30a000000`) | Hardware H.264, HEVC, VP9, AV1 decode | **probe fails**: `Direct firmware load for apple/avd-fw-v4-t0.bin failed with error -2`, then `probe with driver avd failed with error -2`. Module `apple_avd` loaded, `CONFIG_VIDEO_APPLE_AVD=m` | Upstream: 14-patch V4L2 stateless decoder series, 2026-09-18 ([Phoronix](https://www.phoronix.com/news/Apple-Video-Decode-AVD-Linux), [lore](https://lore.kernel.org/all/20260918-avd-v1-0-49977931f455@icloud.com/)). Firmware is built from [AsahiLinux/avd-fw](https://github.com/AsahiLinux/avd-fw) (MIT). Asahi page: Video Decoder = linux-asahi ([page](https://asahilinux.org/docs/platform/feature-support/m3/)). Phoronix (date not read) also reports M3 AVD firmware progress ([article](https://phoronix.com/news/Asahi-Linux-AVD-Firmware-M3), could not be fetched, 403) | No hardware video decode. 4K video and browser playback use the CPU (12 cores). Software AV1 1080p works ([audio-camera-video.md](audio-camera-video.md)) | **P1** (cheapest) |
| 4 | Video encode, ProRes | none found in the DT | H.264/HEVC/ProRes encode | **no node** | Asahi page: Video Encoder = TBA, ProRes = TBA | No hardware encode. Screen recording and streaming use the CPU or GPU | P4 |
| 5 | Touch ID / Secure Enclave (SEP) | none in the DT (only power domain `ps_sep` in `t6030-pmgr.dtsi`). Driver wants `apple,sep` | Fingerprint login, SEP RNG, SEP-sealed keys | **no node, driver off.** `drivers/soc/apple/sep.rs` and `bio.rs` exist in the tree, `CONFIG_APPLE_SEP` is off in the staged config, and `dt.rs` logs "no device-tree node with compatible 'apple,sep'" without a node | Asahi page: SEP = TBA, Touch ID = TBA ([page](https://asahilinux.org/docs/platform/feature-support/m3/)). Protocol notes only: [SEP doc](https://asahilinux.org/docs/hw/soc/sep/) | No Touch ID in KDE or `sudo`. Password login still works | P3 |
| 6 | Neural Engine (ANE) | none in the DT | ML accelerator (`/dev/accel`) | **no node, driver off.** `drivers/accel/ane/` supports only `t8103`, `t6000` and M2 `t6021` (`apple,t8103-ane`, `apple,t6000-ane`). `CONFIG_DRM_ACCEL_ANE` is off. No `t6030` support | Asahi page: ANE = TBA ([page](https://asahilinux.org/docs/platform/feature-support/m3/)). No M3 patch found | No ANE for local LLM or ML. GPU (Vulkan) and CPU remain. See `ane-linux/README.md` | P3 (large work) |
| 7 | Trackpad haptic actuator and accelerometer | HID `0019:05AC:0353.0004` "Apple MTP actuator" and `.0005` "Apple MTP tp_accel" (children of `dockchannel_hid`) | Haptic click feedback, trackpad motion data | **no driver** (the keyboard and touch HID `.0001` to `.0003` are bound) | No upstream work found. Not in the Asahi M3 table | Likely no haptic click feel (not tested by hand). Pointer and clicks work | P4 |
| 8 | Display extras on DCP | `apple,t6030-dcp`, `apple,t6030-dcpext`, `apple,panel-j516` | Internal panel works. Extras: external DP through `dcpext`, mini-LED dimming and HDR, ProMotion, True Tone | **partly bound.** `dcp`, `dcpext0/1`, crossbars and `appledrm` bind. Brightness works (`apple-panel-bl`). The `panel` node has no device. DCP log noise `RTKit: Unknown oslog message` and `set_run_mode_safe: deferring` | Asahi page: DCP = WIP, Brightness = WIP (page), Main display = framebuffer/WIP. Source here carries `drivers/gpu/drm/apple-m3` (private tree) | Internal screen and HDMI-A-1 work. USB-C external displays fail (rows 1, 2). HDR, local dimming, True Tone are not tested and have no known driver | P2 |
| 9 | Bluetooth and Wi-Fi extras (bound, with errors) | `hci_bcm4377`, `brcmfmac` | Codec capability read, Wi-Fi P2P | **bound, errors:** `Failed to read codec capabilities (-22)` x10, `Opcode 0x0c01 failed: -110`, `brcmf_p2p_set_firmware ... -52`, `add iface p2p-dev-wld0 failed -52` | Known on all Apple Silicon (`-52` P2P firmware gap). No M3-specific item found | Wi-Fi and Bluetooth work. Wi-Fi Direct (P2P) does not. A BT command timeout appeared twice (21:14, 21:16) | P4 |

## Working, listed because it was on the question list

| Device | Driver and result | Note |
|---|---|---|
| Camera ISP | `apple_isp` bound, `/dev/video0` "apple-isp", firmware `isp_*.dat` present | Capture works. Quality poor, only 2 V4L2 controls (see [audio-camera-video.md](audio-camera-video.md)). Asahi page: Webcam = linux-asahi |
| Ambient light sensor | `aop_als` bound. `iio:device1` `in_illuminance_input` = 7.57 | Works. Calibration file `aop-als-cal.bin` present. Lid-angle sensor (`aop_las`) reads 108 |
| SMC, fans | `macsmc_hwmon`, `macsmc_power`, `rtc_macsmc`, `macsmc_reboot`, `macsmc_input`. Fans 1 and 2 report 0 rpm (idle), `fanN_min` 1350 and 1458, `fanN_max` 5349 and 5777 | Works. Manual fan control was not tested |
| Thermal sensors | 9 SMC temperatures (NAND, battery, WiFi/BT, 5 SoC die), 7 `apple_pmp` temperatures, 3 thermal zones (`macsmc-battery`, `macsmc_soc_die`, `apple_pmp_hotspot`) | Works. There is no per-core CPU thermal zone |
| Audio | Cards `macaudio` (J516) and `aop_audio` (HPAI). 6 `tas2764` amps, Speaker controls, headphone jack | Works. Speaker listening test is still open (see audio doc). DP/HDMI audio not tested |
| GPU | `asahi-g15` on `card1`, `renderD128` | Works on this kernel |
| Backlight | `apple-panel-bl` | Works (the stock 7.1.13 kernel had none) |

## Not a problem (no driver by design)

`phram` flash nodes (2), `smbios`, `timer`, `genpd` and `genpd_provider`, the four `pmgr` parent nodes and two `cpufreq` parent nodes (the CPUs use `apple_soc_cpufreq`), `dcp:piodma` (2), I2C adapter class devices, `iio` class devices, `spmi_nvmem0`, `mtd0`, the `aic3` interrupt controller node (built in), the `simple-framebuffer` node (replaced by `appledrm`), `fixed-clock` and `asc-mem` reserved-memory nodes. Kernel messages `always-on domain ... is not on at boot` and `RTKit: Unknown oslog message` are harmless. There is no `/dev/tpm*` (the J516S has none exposed).

## Firmware check

- Asahi firmware extraction **ran** at install time. Evidence: `/usr/lib/firmware/vendor` is a tmpfs mount of `vendorfw` (built from `/boot/efi/vendorfw`, not readable without root) and holds `apple/aop-als-cal.bin`, `apple/HmCA-070105899A750901`, `apple/isp_1820_01XX.dat`, `isp_1822_02XX.dat`, `isp_1921_01XX.dat`, `isp_1922_02XX.dat`, `isp_8720_01XX.dat`, `isp_8723_01XX.dat`, `apple/tpmtfw-j516s.bin` (multitouch) and 437 `brcm/` files. File dates are 2026-10-17.
- The installed extractor (`python3-asahi_firmware 0.9.1`) has modules for `als`, `isp`, `multitouch`, `wifi`, `bluetooth`, `kernel` and `asmedia`. **It has no AVD module.** So `apple/avd-fw-v4-t0.bin` is never created by the extraction.
- Missing and required: `apple/avd-fw-v4-t0.bin` (the t8122 variant in `avd-drv.c` line 739). The driver also names v2-t0, v3-t0, v3-t1, v5-t0, v5-t1 for other SoCs. The kernel cannot find it in `/lib/firmware/apple` (that directory does not exist) or in the vendor mount.
- Source of the file: Asahi builds it from [AsahiLinux/avd-fw](https://github.com/AsahiLinux/avd-fw) (Cortex-M3 firmware source, MIT, has `avd-cm3.ld`, `arm-none-eabi-gcc.ini`, `meson.build`). The repo page shows no README or install steps, and the exact output file name was **not verified**. Next step: clone it on the M3, read the `Makefile`, build with `arm-none-eabi-gcc` or `llvm`, check the file name against `avd-fw-v4-t0.bin`, then install it with sudo (user types the password).
- Other firmware files the kernel did not request and did not fail: none found in the log.

## The three most valuable fixes

1. **Enable `CONFIG_USB4_APPLE_SOC=m` and retest USB-C (rows 1 and 2).** The driver is already in the tree and lists `t6030`. One kernel config line plus a rebuild may unblock all three USB-C ports, DP alt mode and Thunderbolt USB3 tunnels. Dependencies (`PCIE_APPLE`, `TYPEC`, `APPLE_RTKIT`, `APPLE_TUNABLE`) are already built. Risk: the driver is new (series posted 2026-08-30) and PCIe or DP tunnels are incomplete upstream. **Owner:** the GPU session ([asahi-m3-pro-gaps-and-ba](#local_61bbf2b0-61fa-4531-a361-8d7e4468a6af)) owns kernel config and boot. Test: [m3-usbc-usb4-gap](#local_f9746235-ad2b-4c94-877a-1f1367a33bda), which already works on this gap. The user must approve any reboot.
2. **Build and install the AVD firmware (row 3).** The module is loaded and only the file is missing. No kernel change, no reboot needed to try (module reload is enough, but a reload needs the user's go). **Owner:** the audio, camera and video session ([m3-audio-camera-video](#local_08dc64de-f910-4bcb-aa52-26241f1db629)) builds the file. The user types the sudo password to copy it to `/lib/firmware/apple/`. Open risk: the decode of 4K H.264 is working downstream, HEVC, VP9 and AV1 are still in progress.
3. **Try Touch ID (SEP) enablement (row 5).** Needs a `t6030` `apple,sep` DT node and `CONFIG_APPLE_SEP=m`. The driver code exists in the tree but is untested on M3 and talks to the Secure Enclave, so it carries more risk and cannot be reverted by a config change alone. **Owner:** the GPU session for kernel and DT, with the user's explicit go. The ANE (row 6) is larger work (no M3 driver exists) and stays below this.

## Root reads (done 2026-10-26 after the 21:59 reboot, kernel still `7.2.11-m3gpu+`)

- `/sys/kernel/debug/devices_deferred` lists exactly `1-0c`, `1-0a`, `2-08`, with no reason text. This matches the journal and the three PD rows. It does not name the missing dependency, so the link to the USB4 driver stays a source-reading inference.
- `CONFIG_USB4_APPLE_SOC` is still not set in `/boot/config-7.2.11-m3gpu+`. `thunderbolt_apple` is not loaded.
- `/boot/efi/vendorfw` holds `firmware.cpio`, `firmware.tar`, `manifest.txt` (447 lines) and `u-boot/`. The manifest and the tar list 9 `apple/` files only (tpmtfw, 6 ISP, HmCA, aop-als-cal). **No `avd-*` file.** This confirms the extraction never made the AVD firmware.
- After the reboot, `avd 30b080000.avd` fails again with `-2`, and `pmgr ... sync_state() pending due to 30b080000.avd` also appears (the failed AVD probe keeps one power domain pending).

## Open items

- `dmesg` itself was not read (journal covers the kernel log).
- Not tested by hand: haptic click, HDR and True Tone, fan control, DP/HDMI audio, USB devices on any port.
- The Phoronix AVD firmware article and the lore thread returned HTTP 403. Their content is known only from search summaries. Re-check them in a browser.
