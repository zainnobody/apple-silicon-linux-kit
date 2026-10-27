# Display, HDMI and external displays on the M3 Pro (J516S)

Tested 2026-10-26 over SSH (`user@<m3-tailscale-ip>`) on Fedora Asahi Remix 44, KDE Plasma 6.7.5 (Wayland).
**Kernel tested: `7.2.11-m3gpu+`** (the one-boot test kernel, not the stock 7.1.13). The test kernel has the native display stack on (`apple-drm`, `apple-dcp`, `dcpext0` and `dcpext1`), so these results do not apply to the stock kernel.
No kernel, boot entry, firmware or m1n1 change was made. The only changes were desktop display settings (HDMI mode, mirror or extend) and brightness values, all set back or chosen by the user.
Asahi status column: from `docs/asahi-m3-pro-status.md`.

**Update (2026-10-26 23:05 to 23:08): USB-C DisplayPort now works on all three USB-C ports with `thunderbolt_apple` loaded** (`DP-3` right, `DP-2` left front, `DP-1` left back; see `usbc-usb4-gap.md` sections 6c to 6e). The USB-C rows below record the first test, before the module was loaded.

## Results

| Feature | Test run | Result | Evidence | Asahi status |
|---|---|---|---|---|
| Built-in panel resolution | `/sys/class/drm/card2-eDP-1/modes`, DRM `GETCONNECTOR` ioctl as root, `/sys/kernel/debug/dri/2/state` | **Works.** 3456x2160, native | Kernel log: "T6030 display started: 3456x2160@120, 74 notch rows hidden, 346x216 mm". Panel is one KDE output at scale 2.7. The firmware reports a 3456x2234 surface and refuses to create the default FB surface ("Creating default FB surface failed - width = 3456, height = 2234"); the driver hides the 74 notch rows instead | Boot framebuffer only. Full support WIP |
| 120 Hz (ProMotion) | Same ioctl and debugfs state | **Works as a fixed 120 Hz. Not adaptive.** | The panel exposes exactly one mode: `3456x2160 vrefresh 120, clock 1042130 kHz, htotal 3536, vtotal 2456` (1042130000 / (3536 x 2456) = 120.0). No 60 Hz mode exists and the refresh rate options list is that one entry. `kscreen-doctor` shows `Vrr: Never` for the panel, so there is no variable refresh | Not supported (progress report 6.19, Feb 2026). **Differs here** |
| Panel: Linux against macOS 15.6.1 (same Mac, read-only data from the macOS side, 2026-10-27) | `system_profiler SPDisplaysDataType`, `ioreg -l` timing lines and the WindowServer displays plist, read by the coordinator session | **Linux matches macOS on size and base rate. Linux lacks variable refresh.** | macOS: native 3456 x 2234 (Linux shows 3456 x 2160, the 74 notch rows hidden), `Hz = 120`, **`IsVRR = 1`**, horizontal total 3536 and active 3456 (same as Linux), `QMSVRREnableConfig = 0`, `IOMFBDisplayRefresh` max interval 178928337 and min interval 35785667 (ratio 5.0, consistent with a 24 to 120 Hz range; the unit and the exact range are not confirmed), "Automatically Adjust Brightness: Yes". `system_profiler` prints no refresh rate on this macOS version. The macOS `PixelClock` entry of 712000000 does not match the Linux pixel clock of 1042130 kHz, so it is probably a different quantity (not compared further). Vertical timing values were not read | n/a |
| Panel brightness (sysfs) | As root: wrote 100, 250, 43 to `/sys/class/backlight/apple-panel-bl/brightness`, read back, restored 43 | **Works** | `max_brightness` 500, `scale` linear, `type` platform. Each write showed the same value in `actual_brightness`. The DCP logged `brightness_changed: brightness value: 6553600` for 100 (value times 65536), 16384000 for 250, 2818048 for 43. The device is `28ec00000.dcp` | WIP. No date |
| Panel brightness (desktop) | Brightness keys (user), `kscreen-doctor output.eDP-1.brightness.70/50/28` over SSH | **Works** | Sysfs followed KDE: 70% gave 350, 50% gave 250, 28% gave 141. The System Settings slider also works; it only acts after "Apply" is clicked (user error, not a bug). Powerdevil logs `Permission denied opening /dev/i2c-0, i2c-1, i2c-2` (DDC search for external monitors). The TV gets a software brightness (`allowSdrSoftwareBrightness: true`), not a DDC one | WIP |
| Keyboard and desktop on the panel | `loginctl`, `kscreen-doctor -j` | Works | `kwin_wayland` owns the panel and composes on the native GPU. Panel at 3456x2160 at 120 Hz | n/a |
| HDMI port: kernel view | `/sys/class/drm/card2-HDMI-A-1`, kernel log | **Works** | Connector present, `disconnected` with nothing plugged in. Reports `connected` and `enabled` after a cable. `DP2HDMI HPD irq, connected:1` then `display attached: starting the external display processor`. HDMI is driven by `dcpext0` (`2d2c00000.dcp`, `conn_type=11`, `atc=3`, `route=fixed`). The firmware of the external display processor loads on first use (about 1 s) | Disabled on MacBooks until DCP work lands (Phoronix, The Register) |
| HDMI image on a monitor | Vizio M65Q6-J09 TV (EDID: made 2021, 142 x 80 cm, 297 MHz 3840x2160 timing, max pixel clock 300 MHz). KDE chose 2560x1440 at 59.95 Hz | **Works. Image stable (user report).** | `mode_set_gated: 2560x1440@59 Hz DSC=NO VRR=NO link: 1`, then `swap 1..3 complete`. Audio over HDMI not tested (kernel module option `hdmi_audio` exists) | Disabled |
| HDMI mode changes | `kscreen-doctor output.HDMI-A-1.mode.N` over SSH, 6 s apart: 1920x1080@60, 3840x2160@30, 4096x2160@30, 1280x720@60, 2560x1440@59.95, then 3840x2160@30 | **Driver accepted every mode** | Each change logged `display mode ...` and `mode_set_gated: WxH@R Hz DSC=NO`. 3840x2160@30 uses a 297 MHz clock. User confirmed the first image (2560x1440); the stability of the other five modes is **to be confirmed by the user** | Disabled |
| HDMI 4K at 60 Hz | EDID parse of the TV | **Not tested.** The TV offers no 4K60 mode | The EDID lists 4K only at 24, 25, 30 Hz (CTA VSDB max TMDS 300 MHz, so HDMI 1.4 class). That is a TV limit, not a driver limit. A monitor with an HDMI 2.0 EDID is needed | n/a |
| Mirror and extend | KDE `kscreen-doctor -j`, Command+P popup (user) | **Mirror works. Extend works.** | Start state was mirror (`replicationSource` = panel). `kscreen-doctor` has no mirror option. System Settings did not save the change at first (the config file kept its 21:03:35 time stamp). The Command+P popup "Extend to Right" worked: TV at 0,0 (3840x2160, scale 1.5), panel at x=2560 | n/a |
| HDMI hot plug | Plugged the cable while the desktop ran, later removed it | **Works** | The external display processor starts on plug. No crash, no hang. After the cable was removed `card2-HDMI-A-1` read `disconnected` and KDE kept one output | WIP |
| Suspend with a display attached (side finding) | Not planned. The M3 slept by itself from about 21:14:55 to 21:16:21 (`tailscaled`: "slept 1m26s") while the HDMI cable was being moved | **Suspend and resume worked once** | `PM: suspend exit`, `resume devices took 2.013 seconds`, `HDMI: setting up the output again (after system sleep)`. After the resume the panel and SSH worked and the desktop stayed up. The Wi-Fi firmware logged `brcmf_p2p ... err=-52` at resume. Who started the sleep is not known (the sleep session of this group may have). Not a full sleep test | Sleep: press says it does not work |
| USB-C DisplayPort Alt Mode | User plugged a USB-C to HDMI dongle into a USB-C port (port not named). Read `card2-DP-1..3`, `/sys/class/typec`, `/sys/bus/spmi`, the kernel log | **Fails without the `thunderbolt_apple` module (first test). Works once it is loaded; see the update above.** | `DP-1`, `DP-2`, `DP-3` stay `disconnected` with 0 modes. No kernel message appeared for the plug. Cause found: of the four USB-PD controllers (`sn201202x`) only `1-06` is bound and has a Type-C port (`port0`, role sink, the DisplayPort-only PHY `1303000000.phy`, so it is the HDMI path). The three that serve the real USB-C ports (`1-0a`, `1-0c`, `2-08`) have **no driver bound**: `spmi 1-0c: deferred probe pending: (reason unknown)` (same for `1-0a`, `2-08`). They wait for suppliers, among them the three `cio` devices (`701ac0000.cio`, `b01ac0000.cio`, `f01ac0000.cio`, compatible `apple,t6030-usb4-acio`), which have **no driver** because the kernel config leaves the driver out (`# CONFIG_USB4_APPLE_SOC is not set`; see `usbc-usb4-gap.md`). The USB (`dwc3-apple`) and PHY (`phy-apple-atc`) suppliers and the `dcp-typec*-mux` devices exist. Without a Type-C connector there is no hot plug signal, so the DCP routes (`typec-routes/route@0..2`) never fire. `lsusb` shows no device either | WIP. "Done when it's done" |
| Thunderbolt / USB4 display | Not run separately | **Not possible on this boot (first test, module not loaded). Later Thunderbolt tests: `usbc-usb4-gap.md` sections 6f to 6h.** | Same cause: the ACIO (USB4/Thunderbolt `cio`) driver is not built, `/sys/bus/thunderbolt/devices` is empty. Tunneled DisplayPort cannot start | WIP |
| Kernel messages (DCP, apple-drm) | `journalctl -k -b` filtered for `dcp\|apple-drm` and warnings | **Works, but noisy.** See the list below | 168 DCP lines at boot, more after each plug or mode change | n/a |
| Color management | `kscreen-doctor -o`, `colormgr get-devices` | **sRGB only** | Color profile source sRGB on both outputs. No ICC profile. `colord` lists no devices. `kscreen-doctor` shows `HDR: incapable` and `Wide Color Gamut: incapable` for the panel and the TV. The panel shows `Allow EDR: always` (KDE policy), but no HDR path works | Not listed |
| HDR | `kscreen-doctor -o` | **Not available** | `HDR: incapable` on both outputs. The Liquid Retina XDR panel runs as an SDR sRGB panel here | Not listed |
| Night light | KWin D-Bus `org.kde.KWin.NightLight` | **Available. Not switched on in this test.** | `available=true`, `enabled=false`, `mode=1`, `currentTemperature=6500`, `targetTemperature=6500`. Turning it on changes the user's KDE setup, so I did not | n/a |
| Automatic brightness | `kscreen-doctor -o` | Listed as supported, disabled | `Automatic brightness: supported, disabled` on both outputs. No ambient light sensor test was done | n/a |

## Kernel warnings and errors (test kernel 7.2.11-m3gpu+)

At boot, panel (`28ec00000.dcp`):

- `RTKit: Unknown oslog message` (4 lines). Harmless log decode gap.
- `IOMFB LACS_ERROR: DCP took too long to respond to LAS stats`, `BLM LTS data hasn't been read in more than 10 secs`. Ambient light and backlight support code in the firmware.
- `Could not find Backlight service`, `Could not find nvram service`, `Could not find Product service` (firmware wants macOS services).
- `Could not find table 'display-backlight-compensation-v1'` (uses a default table).
- `minimum-frequency property not found`, `vid-clock-to-disp-clock-factor read failed, using default`.
- `late_init_ios: Realtime Bandwidth setup failed`.
- `load_ca_data: Unrecognized data version 0 (expected 1 or 2)`.
- `create_default_fb_surface: Creating default FB surface failed - width = 3456, height = 2234`.
- `panel charge parity violation [0xf933d0e]`.
- `copy_edid failed: -ENODEV`, repeated (the internal panel has no EDID).
- `apple-pmgr-pwrstate ... always-on domain atc3_common is not on at boot` (once).
- `apple-display-crossbar ...: T602X route -2, clocks disabled` (12 lines, before the first plug).
- Many `Fixed dependency cycle(s)` lines from device tree links between `usb-pd` connectors, `dcpext` and the PHYs. Normal on this tree.

After the HDMI plug (`2d2c00000.dcp`):

- `DPTX message 0x85000000000000` repeats about 10 times per second while a display is attached. 2958 lines in the first 5 minutes. This floods the journal (219.7 MB in use). The first lines after the plug show five other message codes (`0xa0...08`, `0x89...cafe`, `0x8a...cafe`, `0x8b...cafe`, `0x86...`) once each.
- `IOMFB: Could not find Product / Backlight / nvram service` (as above).
- `setup_video_limits called on secondary display with no timing set`.
- `HPD not present, skipping mode export` (during start, before the link is up).
- `read_pmu_data_sync: pmu ram read error (e00002d8)` at each mode change (7 times).
- `IOMFB WARNING: set_timings() called after timings were started` at each mode change (7 times).
- `ERROR: Modeset done, but pipe not enabled: fSoftPowerState=0, fDisplayPowerState=0, fHardPowerState=1` at each mode change (7 times). The image still came up. This may match a short black flash on the TV; not measured.

At 20:43:08 (USB-C, see the table): `spmi 1-0c: deferred probe pending: (reason unknown)`, same for `1-0a` and `2-08`.

At resume (21:16:21): `PCC2DBLMMailboxHandler::eventq_callback_notify_gated: busy descriptor, dropping` (6 times), `LACS_ERROR` again, `brcmf_p2p_set_firmware: failed to update device address ret -52`.

No oops, no hung task, no GPU fault and no `drm` error was logged during the tests.

## Open tests (need the user's hands)

1. **USB-C display on each of the three USB-C ports.** Done once on one port (fails). The cause is shared by all three USB-C controllers, so a retry on the other ports should fail the same way. A retry after a fix (see next steps) needs the user to plug the dongle again and name the port.
2. **Thunderbolt / USB4 display.** Blocked until a kernel with `CONFIG_USB4_APPLE_SOC=y` boots.
3. **HDMI 4K at 60 Hz.** Needs a monitor whose EDID lists 3840x2160 at 60 Hz.
4. **Stability of the five HDMI modes** I switched on 2026-10-26 21:01 (user to confirm what the TV showed).
5. **HDMI unplug**, and a second external display at the same time (the machine has two external display processors).
6. **HDMI audio.**

## Next steps

- **Unblock USB-C displays (kernel work, GPU session owns it).** Root cause, found by the USB-C session and confirmed on the M3 (`/boot/config-7.2.11-m3gpu+`): `# CONFIG_USB4_APPLE_SOC is not set`. The tree already has `drivers/thunderbolt/apple.c`, which matches `apple,t6030-usb4-acio`, but it is not built. The PD controllers wait for the Thunderbolt switch that this driver registers. The fix is one config line plus a kernel rebuild, so it needs the user's go. No new driver code is needed. Details, patch list and test plan: `docs/features/usbc-usb4-gap.md`. After the rebuild, rerun the USB-C dongle test, then a Thunderbolt display test.

- Report the `DPTX message 0x85...` flood and the "pipe not enabled" error at modeset to the display driver authors. They are log noise or a harmless race, but a flood of 10 lines per second will fill the journal.
- Compare the stock kernel 7.1.13: it has no `dcpext` support, so HDMI and the DP connectors should be absent there. A boot into the stock kernel needs the GPU session and the user's go.
- The 120 Hz claim is checked: the Asahi status says 120 Hz is not supported, and this kernel runs the panel at a fixed 120 Hz. macOS on the same Mac runs 120 Hz with variable refresh on (`IsVRR = 1`). So the open gap is variable refresh (ProMotion, down to about 24 Hz), and a 60 Hz option for battery saving. Both need DCP driver work. Check first whether the driver can pass a lower refresh interval to the DCP (the firmware reports a minimum interval, so the hardware supports a range).
- Find out why the System Settings screen layout did not save mirror to extend at the first attempt (QML warning `Panel.qml:112:13 Parameter "button" is not declared` was logged). Probably a KDE bug, not an Asahi bug.
- Try `colormgr` and an ICC profile for the panel if color accuracy matters. No profile is installed.
