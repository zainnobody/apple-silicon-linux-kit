# USB-C display, USB-C data and Thunderbolt/USB4 on the M3 Pro 16-inch (J516S): root cause and fix plan

Researched 2026-10-26. Read-only work on the M3 (over SSH). No kernel, boot entry, m1n1 or firmware change. No reboot. No sudo.
Kernel under test: `7.2.11-m3gpu+` (build `#6`, 2026-10-26 20:18 PDT). Source tree: `~/m3gpu/src/linux`, tag `v2026.10.19-pr363-native.1`, origin `iconidentify/siliconforest-linux`.

## Short answer

**The driver exists. The kernel config does not build it.** `CONFIG_USB4_APPLE_SOC` is `not set` in the running kernel. The source tree has the full ACIO/NHI driver (`drivers/thunderbolt/apple.c`, 3277 lines) and it already matches `apple,t6030-usb4-acio`. The device tree nodes exist. m1n1 already filled the tunables. No firmware file is needed.

Without that driver, nothing registers the "thunderbolt switch" that the PD controller driver waits for. The three PD controllers return `-EPROBE_DEFER` forever. That is the "deferred probe pending: (reason unknown)" line. The same missing driver blocks USB-C data, USB-C charging control, DisplayPort Alt Mode and Thunderbolt on all three ports.

**Fix: one config line (`CONFIG_USB4_APPLE_SOC=m`) in `agx-linux-kit/build/build-kernel.sh`, then one rebuild.** A dry run on a scratch copy of the config changes that one symbol and nothing else.

The earlier note in `display-hdmi.md` ("add the T6030 compatible to the ACIO driver") is not needed. The compatible is already in the driver table.

## Results at a glance (after `thunderbolt_apple` was loaded by hand, 2026-10-26)

| Test | Left back (`1-0c`, atc0) | Left front (`1-0a`, atc1) | Right (`2-08`, atc2) |
|---|---|---|---|
| PD controller binds (`sn201202x`) | Yes | Yes | Yes |
| USB-C data (USB 3) | Dongle hub, Ethernet, SD reader | Samsung T7 at 10 Gbps | Samsung T7 |
| USB-C power (PD) | Not measured | Charger online | Not measured |
| DisplayPort Alt Mode (dongle to TV) | Yes, `DP-1`, 3840x2160@30 | Yes, `DP-2`, 3840x2160@30 | Yes, `DP-3`, 3840x2160@30 |
| USB4 host-to-host (Mac17,2) | Yes, 20 Gb/s link, ping 0 % loss, 3.78 Gbit/s | Yes, 20 Gb/s, 3.84 Gbit/s | Yes, 20 Gb/s, 4.13 Gbit/s |

Not tested: Thunderbolt dock or display (DP and PCIe tunnels), 40 Gb/s link, two displays at once, 4K60, sleep with a cable, permanent module install.

## 1. Device table (M3, kernel 7.2.11-m3gpu+)

| Device (path) | `compatible` | Driver bound? | Notes and exact lines |
|---|---|---|---|
| `spmi 1-06` (`/soc/spmi@364908000/usb-pd@6`) | `apple,sn201202x` | **Yes**, `sn201202x` (module `tps6598x_core`) | No `connector` node in the device tree. Has `typec/port0` and power supply `tps6598x-source-psy-1-06`. DisplayPort-only PHY `1303000000.phy`. This is the HDMI path. |
| `spmi 1-0c` (`usb-pd@c`, label "USB-C Left Back", ATC0) | `apple,sn201202x` | **No** | `spmi 1-0c: deferred probe pending: (reason unknown)` at 20:43:08. `waiting_for_supplier` is 0. Supplier links list `701ac0000.cio`, `702280000.usb`, `703000000.phy`, `2d2c00000.dcp`, `2d6c00000.dcp`, `dcp-typec0-mux` (both DCPs). |
| `spmi 1-0a` (`usb-pd@a`, left front, ATC1) | `apple,sn201202x` | **No** | `spmi 1-0a: deferred probe pending: (reason unknown)`. Suppliers: `b01ac0000.cio`, `b02280000.usb`, `b03000000.phy`, `dcp-typec1-mux`. |
| `spmi 2-08` (`/soc/spmi@364a08000/usb-pd@8`, right, ATC2) | `apple,sn201202x` | **No** | `spmi 2-08: deferred probe pending: (reason unknown)`. Suppliers: `f01ac0000.cio`, `f02280000.usb`, `f03000000.phy`, `dcp-typec2-mux`. |
| `spmi 0-0b` (`pmic@b`) | `apple,chapel-pmic`, `apple,spmi-nvmem` | Yes, `apple-spmi-nvmem` | Not related. |
| `701ac0000.cio`, `b01ac0000.cio`, `f01ac0000.cio` | `apple,t6030-usb4-acio`, `apple,t8103-usb4-acio` | **No driver** | Devlink `platform:701ac0000.cio--spmi:1-0c` is `dormant` (same for the other two). Live device tree has `apple,tunable-rc` (360 bytes), `apple,tunable-pcie-adapter` (12 bytes), `apple,pcie-tunnel`, `mboxes`, `power-domains`, `resets`. `/sys/bus/thunderbolt/devices` is empty. |
| `cio/nhi@f00000` (x3) | `apple,t6030-usb4-nhi`, `apple,t8103-usb4-nhi` | No driver | Has `apple,tunable-nhi` (2712 bytes) and `apple,thunderbolt-drom` (76 bytes). |
| `cio/iommu@a80000` (x3) | `apple,t6030-dart`, `apple,t8110-dart` | Device present (`702f00000.iommu`, `b02f00000.iommu`, `f02f00000.iommu`) | Not checked for driver state. |
| `cio/thunderbolt-switch` (x3) | (no compatible; graph endpoint `cio/ports/port@1`) | n/a | Linked to the connector `ports/port@2`. This link is what the PD driver waits on. |
| `usb4-pcie-tunnel-0/pcie@730000000` | none read | No device bound | Only `580000000.pcie` (Wi-Fi/SD) is bound. The tunnel root port comes after ACIO. |
| `702280000.usb`, `b02280000.usb`, `f02280000.usb` | `apple,t6030-dwc3`, `apple,t8103-dwc3` | Yes, `dwc3-apple` | Bound, but no USB-C connector drives a role. `lsusb` shows no port device. |
| `703000000.phy`, `b03000000.phy`, `f03000000.phy`, `1303000000.phy` | `apple,t6030-atcphy`, `apple,t8122-atcphy` | Yes, `phy-apple-atc` | `typec_mux`/`typec_switch` devices exist for all four. One log line: `apple-pmgr-pwrstate 350700000.power-management:power-controller@4f8: always-on domain atc3_common is not on at boot` (once). |
| `2d2c00000.dcp`, `2d6c00000.dcp` (dcpext0, dcpext1) | `apple,t6030-dcpext`, `apple,dcpext` | Yes, `apple-dcp` | `dcp-typec0..2-mux` exist for both. Log: `apple-dcp 2d2c00000.dcp: typec_mux_set() returned: 0` (20:42:57). HDMI works through `atc=3 route=fixed`. |

Loaded modules that matter: `tps6598x_core`, `phy_apple_atc`, `dwc3_apple`, `typec`, `mux_apple_display_crossbar`, `appledrm`, `pcie_apple`, `apple_tunable`. **Not loaded and not built:** `thunderbolt_apple`.

Kernel log: there is **no** error line from `sn201202x`, `thunderbolt` or `cio`. The three PD devices and the three `cio` devices are silent because their probe never starts or never reports a reason. The log also holds many `Fixed dependency cycle(s)` lines between `usb-pd@*/connector`, `cio@*`, `phy@*`, `usb@*` and `dcp@*/typec-routes`. They are normal. They are the reason `waiting_for_supplier` reads 0: fw_devlink broke the cycle, so the block comes from inside the PD probe, not from devlink.

Not read: `/sys/kernel/debug/devices_deferred` (needs root). It would only repeat "reason unknown", because `sn201202x` does not call `dev_err_probe` on this path.

## 2. Root cause with evidence

Chain of events on each of the three ports:

1. The device tree gives every USB-C connector a graph link to the ACIO router: `t603x-j514s-j516s-usb4.dtsi` sets connector `ports/port@2` to `cio/ports/port@1` (`T603X_USB4_GRAPH(0..2)`). The `cio` node has a `thunderbolt-switch` property.
2. `cd321x_register_port()` in `drivers/usb/typec/tipd/core.c` (line 1802) calls `fwnode_typec_thunderbolt_switch_get(fwnode)`.
3. That function (`drivers/usb/typec/mux.c`, line 612) returns `ERR_PTR(-EPROBE_DEFER)` "when a connection was found but the switch has not been enumerated yet".
4. Only `drivers/thunderbolt/apple.c` registers that switch (`typec_thunderbolt_switch_register`, line 3181). That module is not built.
5. So probe is deferred with no message. The kernel prints `deferred probe pending: (reason unknown)`.

Why `1-06` works: its device tree node has no `connector`, so `fwnode_connection_find_match()` finds no connection and the getter returns `NULL`.

Why the driver is missing from the kernel: `agx-linux-kit/build/build-kernel.sh` line 11 copies `/boot/config-$(uname -r)`, which is the stock Fedora Asahi 7.1.13 config. Kernel 7.1 has no `USB4_APPLE_SOC` symbol. `make olddefconfig` sets new symbols to their default, `n`. The script then sets only GPU options. Evidence:

- `~/m3gpu/build-linux/.config` line 12206: `# CONFIG_USB4_APPLE_SOC is not set`.
- `/boot/config-7.2.11-m3gpu+`: `# CONFIG_USB4_APPLE_SOC is not set`.
- `arch/arm64/configs/asahi.config` line 67 has `CONFIG_USB4_APPLE_SOC=m`. The build script does not merge that file.
- Dry run (scratch copy in `/tmp`, deleted): `scripts/config -m USB4_APPLE_SOC` then `make ARCH=arm64 O=<tmp> olddefconfig` exits 0. The only diff is that one line. Dependencies hold: `APPLE_RTKIT=y`, `TYPEC=m`, `PCIE_APPLE=m`, `APPLE_TUNABLE=m`, `RESET_APPLE_CIO=y`, `USB4=y`.

### Classification

| Candidate cause | Verdict | Evidence |
|---|---|---|
| Missing driver | **No** (driver exists) | `apple.c` has `apple,t6030-usb4-acio` and `apple,t6030-usb4-nhi` data (`apple_cio_t6030_hw`, `apple_dpin_m3`), plus `t6030` in the DP-IN qualified list. |
| **Driver not built (config gap)** | **Yes. This is the root cause.** | Config line above. |
| Missing device tree node | No | All three `cio`, `nhi`, `iommu`, `thunderbolt-switch` and PCIe tunnel nodes are in `/proc/device-tree`. |
| Missing tunables from m1n1 | No | `apple,tunable-rc`, `-pcie-adapter`, `-nhi` and the DROM are present and non-empty. The driver refuses to probe without them (line 3048). |
| Missing firmware file | No | `apple.c` has no `request_firmware`. The ACIO Cortex-M3 firmware is already on the SoC. The driver only boots its RTKit and waits for "firmware ready". |
| Bind order | Symptom only | The PD deferral is a bind order effect, but its cause is that the provider never exists. |

Confidence: high that this is the first blocker. It is inferred from source plus sysfs, not from a trace, because root is needed for debugfs and a trace changes nothing here. It is fully confirmed only when the module is built and the PDs bind. A second blocker may appear after that (see risks).

## 3. Patches and sources (names and dates)

Commit hashes are from the local fork tree (`git log --all` in `~/m3gpu/src/linux`). Hashes in other trees can differ. I could not open lore.kernel.org (HTTP 403), so I did not read the cover letter itself.

| Date | Author | Commit or event | Role |
|---|---|---|---|
| 2025-10-15 | Sven Peter | `0ec946d32ef7` usb: dwc3: Add Apple Silicon DWC3 glue layer driver | USB3 controller glue (bound here) |
| 2025-12-14 | Sven Peter | `8e98ca1e74db` phy: apple: Add Apple Type-C PHY | ATC PHY (bound here). LKML v3 series: <https://lkml.iu.edu/hypermail/linux/kernel/2512.1/05858.html> |
| 2026-01-31 | Janne Grunau | `d47497647a46` arm64: dts: apple: Initial T603[124] (M3 Max and Ultra) device trees | M3 board device trees |
| 2026-07-25 | Sasha Finkelstein | `24065f2feb4d` phy: apple: atc: Add initial M3 series support | ATC PHY on M3 |
| 2026-08-24 | Sven Peter | `6110014ccc8a` thunderbolt: Add Apple Silicon support | **The ACIO/NHI driver** (`apple.c`) |
| 2026-08-24 | Sven Peter | `84ce8c5d4ca8` usb: typec: Add thunderbolt switch | **The switch the PD driver waits for** |
| 2026-08-24 | Sven Peter | `2714a76d497e` phy: apple: atc: Implement the USB4 pipehandler state; `2f6ec8f4f4aa` usb: typec: tbt: Correct swapped TBT adapter type values | USB4 mode in PHY and Type-C |
| 2026-08-25/28 | DjDeveloperr | `97bf6478981b` PCI: apple: add cable-powered PCIe-C root complexes; `6e26f21c8874` thunderbolt: apple: activate PCIe-C after the USB4 tunnel | Tunneled PCIe |
| 2026-09-26 | Chris Kearney | `8337f93c3589` arm64: dts: apple: t6030: add GPU, USB4/Thunderbolt and display nodes | Creates `t6030-usb4.dtsi` (`cio`, `nhi`, PCIe tunnel) |
| 2026-10-06 | Chris Kearney | `1f80f4ca1bf4` t603x-j514s-j516s: route the external display to all three USB-C ports; `52c09e0f15df` describe the second external display processor | Board wiring for J516S |
| 2026-10-10 | Chris Kearney | `a29fbe8f9244` drm/apple: select clockable T6030 Thunderbolt display routes | DP over Thunderbolt on M3 |
| 2026-10-10 | Sean Cain | `b4a82bb31c0e` thunderbolt: apple: enable Thunderbolt DP display on t8112 | M2 DP tunnel |
| 2026-10-16 | Chris Kearney | `0378c54a442e` usb: typec: tipd: send each IRQ_HPD request to the display route once | Type-C DP hot plug |
| 2026-10-20 | Chris Kearney | `e3291940988f` thunderbolt: apple: yield queued M3 display-readiness retries | **Not in the running tree.** Only on `origin/diagnostic/dock-adapter-isolation-20261020` and `dock-source-isolation-20261020`. The message says physical second-display qualification is still blocked and the diagnostic default must not be merged. |

Public status:

- Asahi progress report 7.2, 2026-08-26: ACE3 and SPMI work, "bringing USB 3.0 and Thunderbolt support to all M3 series devices". ATC PHY got new M3 tunables. No USB4 or external display text. <https://asahilinux.org/2026/08/progress-report-7-2/>
- Asahi feature table, M3: USB2/USB3 and USB-PD `linux-asahi`; Thunderbolt `WIP`; DP Alt Mode `WIP`; HDMI on the 14-inch MacBook Pro `WIP`. <https://asahilinux.org/docs/platform/feature-support/m3/>
- Asahi progress report 6.19, 2026-02: DP Alt Mode "done. Kind of."; demo on an M1 MacBook Air with a USB-C to HDMI adapter; code in a downstream "fairy dust" branch. <https://asahilinux.org/2026/02/progress-report-6-19/> (read through search result text)
- Upstream: Sven Peter posted a 19-patch USB4/Thunderbolt series for M1, M2 and M3 around 2026-08-30/31. Press says it has no PCIe or DisplayPort tunneling and no suspend. The target kernel is not stated. <https://borncity.com/news/linux-7-3-usb4-und-thunderbolt-kommen-auf-apple-silicon/> and <https://phoronix.com/news/Linux-USB4-Apple-Silicon> (Phoronix page blocked, title and snippet only). The fork's `apple.c` is much larger than that series (DP-IN, PCIe tunnel, resume recovery). That extra code is community work in the fork.
- M3 context: <https://phoronix.com/news/apple-m3-asahi-linux-2026> (page blocked, snippet only).
- Source repo: <https://github.com/iconidentify/siliconforest-linux>. The repo page contained a note addressed to AI assistants. I did not act on it.
- In-tree notes: `SILICONFOREST-M3-REVIEW.md` says the alternative profile `CONFIG_SILICONFOREST_M3` "disables USB4" (`depends on !USB4`). The build script already turns that profile off, so this does not block us.

## 4. Fix plan

### Option A (recommended): build the ACIO driver

| Step | Who | What |
|---|---|---|
| A1 | GPU session (owns kernel build) | In `agx-linux-kit/build/build-kernel.sh` add `cfg --module USB4_APPLE_SOC` before `olddefconfig`. Add `check "CONFIG_USB4_APPLE_SOC=m"` and `check "CONFIG_USB4=y"` after it. |
| A2 | GPU session | `CONFIG_ONLY=1` run first, then full build. Confirm `modinfo thunderbolt_apple.ko` lists `apple,t6030-usb4-acio` and `apple,t6030-usb4-nhi`. |
| A3 | GPU session | Optional: cherry-pick `e3291940988f` only if the second display on a dock fails in tests. It is on a diagnostic branch, so review it first. |
| A4 | GPU session + user | Stage the kernel as a one-boot entry like the earlier test kernel. Needs the user's explicit go. Add `modprobe.blacklist=thunderbolt_apple` to that one entry so the first boot looks like today. Then the user loads the module by hand with `sudo modprobe thunderbolt_apple`. |
| A5 | Test session (this family) | Run the test plan below. |

Risk (Option A): low for the build, medium for the first run.

- One config symbol. The dry run shows no other change.
- The ACIO driver boots a coprocessor and resets the PCIe-C tunnel. A fault could hang or flood the log. The module can be unloaded if it fails, and the one-boot entry gives a clean rollback to the previous kernel.
- A second deferral may follow. After the switch exists, `typec_set_mode(SAFE)` can return `-EAGAIN`, and `cd321x_register_port()` then defers again (`core.c`, near line 1815). Watch `dmesg` for that.
- M3 DP-IN over Thunderbolt is not fully qualified by its authors (`e3291940988f` message, 2026-10-20). Expect display problems on docks even if USB3 works.
- Sleep: the driver has opt-in module parameters `resume_recovery`, `s2idle_teardown`, `router_sleep`. Press says upstream disables suspend while a connection is active. The M3 sleep session must re-test lid close with a cable plugged in and unplugged.
- Journal noise: the DCP already floods the log with `DPTX message 0x85...`. Check journal size after tests.

### Option B (fallback, DisplayPort Alt Mode only)

If the ACIO driver misbehaves, remove the Thunderbolt link so the PD controllers bind without it: delete `T603X_USB4_GRAPH` use (or the connector `port@2` endpoint) in `t603x-j514s-j516s-usb4.dtsi` for a DP-only test kernel. This needs a device tree rebuild. It gives USB-C data, charging and DP Alt Mode, but no Thunderbolt/USB4. The `cio` nodes would stay unbound. It has not been tried.

### Option C (not recommended)

Patch `fwnode_typec_thunderbolt_switch_get()` to not defer when no provider driver exists. This changes shared Type-C code and hides the real problem.

## 5. Test plan (after the rebuild and one-boot entry)

Stages 1 and 2 need no hands. Stages 3 to 6 need the user.

1. **Baseline boot (module blocked).** Same as today: HDMI works, three PDs deferred. Confirms the new kernel did not break anything.
2. **Load the module.** `sudo modprobe thunderbolt_apple`, keep the lid open. Pass: `dmesg` shows ACIO probe for `701ac0000.cio`, `b01ac0000.cio`, `f01ac0000.cio` without "firmware failed to get ready" or "RTKit failed to boot". Then `ls /sys/bus/spmi/devices/*/driver` shows `sn201202x` for `1-0a`, `1-0c`, `2-08`, and `/sys/class/typec` lists `port1` to `port3` or more.
3. **USB-C data.** User plugs a USB-C flash drive in each port, both orientations. Pass: `lsusb` shows the device and it mounts.
4. **USB-C charging.** User plugs a USB-C charger in each port. Pass: `/sys/class/power_supply/tps6598x-source-psy-*` and the battery show charge, no PD error in the log.
5. **DisplayPort Alt Mode.** User plugs the USB-C to HDMI dongle in each port and names the port. Pass: `card2-DP-1..3` shows `connected` with modes, an image appears, hot unplug and replug work.
6. **Thunderbolt/USB4.** User plugs a Thunderbolt dock or USB4 device. Pass: `/sys/bus/thunderbolt/devices` lists a domain and router, tunnels form, and a display on the dock lights. Record which tunnels work (USB3, DP, PCIe).
7. **Safety checks.** Lid close and open with a cable plugged (needs the sleep session), `journalctl -k` size after 10 minutes, `rmmod thunderbolt_apple` clean.

Rollback at any step: reboot into the previous kernel. Needs the user's go and the GPU session.

## 6. Recommendation

Go with **Option A**. It is one config line, no new code, and the dry run shows no side effects. Order of work:

1. GPU session edits `build-kernel.sh` and rebuilds (A1 to A2). No reboot needed for this.
2. User gives the go for one boot into the staged kernel with the module blocked (A4).
3. This family runs the test plan. Keep Option B ready if stage 2 fails.

This also covers the open item "USB-C displays: PD controllers 1-0a, 1-0c, 2-08" and the USB-C part of `ports-wireless-storage.md` (that file did not exist when this report was written).

## 6a. Update after the GPU session build (2026-10-26)

The GPU session built the change (`agx-linux-kit` commit `12f52d3`, staged in `~/m3gpu/out/kernel-7.2.11-m3gpu+-usb4`). Nothing is installed and no reboot is done. Their report:

- `olddefconfig` changed only `CONFIG_USB4_APPLE_SOC`. `vmlinuz` and all existing modules are byte-identical to the installed ones.
- The one new file is `thunderbolt_apple.ko`. It depends on `pcie-apple`, `typec` and `apple-tunable`.
- Its aliases have `apple,t6030-usb4-acio` but no `t6030` NHI alias.

**The missing `t6030` NHI alias is not a problem.** The NHI match table (`apple.c` line 2312) lists `apple,t8142-usb4-nhi` and `apple,t8103-usb4-nhi`. The live device tree node `cio@701ac0000/nhi@f00000` has `compatible = "apple,t6030-usb4-nhi", "apple,t8103-usb4-nhi"`. The `t8103` fallback matches.

Because the kernel image is identical, the module can be tested without a reboot: copy the one `.ko` into `/usr/lib/modules/7.2.11-m3gpu+`, run `depmod`, then `sudo modprobe thunderbolt_apple`. This needs the user's go and sudo. Udev may also load the module at the next boot by itself, so keep the blacklist idea from step A4 in mind. Test stages 2 to 7 above apply unchanged.

## 6b. Result of the first module load (2026-10-26 22:13, kernel 7.2.11-m3gpu+, user approved)

`sudo modprobe -v thunderbolt_apple` (module installed earlier, blocked from autoload by a `blacklist` line). Exit code 0 in under 1 second.

| Check | Result |
|---|---|
| PD controllers `1-0a`, `1-0c`, `2-08` | **All bound to `sn201202x`.** The deferral is gone. This confirms the root cause. |
| `701ac0000.cio`, `b01ac0000.cio`, `f01ac0000.cio` | Bound to `thunderbolt-apple-acio` |
| `/sys/class/typec` | `port0` to `port3`. Mapping: `port1` = `1-0c`, `port2` = `1-0a`, `port3` = `2-08` |
| Kernel log after load | No error, warning, `firmware failed to get ready`, `RTKit failed to boot` or new `deferred probe pending` line (41 lines, all xHCI and USB core) |
| USB-C data (`port3`, `2-08`) | **Works.** `lsusb`: `04e8:61fb Samsung PSSD T7 Shield` on the USB 3 root hub (bus 2). `usb-storage` registered. |
| USB-C power (`port2`, `1-0a`) | **Works.** Partner with PD (id header `0x2c00413c`), `tps6598x-source-psy-1-0a` online, `macsmc-ac` online. |
| DisplayPort Alt Mode | **Not tested.** `DP-1..3` are `disconnected`. No display was plugged in. `port2` and `port3` partners list no alt modes. |
| Thunderbolt/USB4 | **Not tested.** `/sys/bus/thunderbolt/devices` is empty. No Thunderbolt device was plugged in. |

The module stays loaded until unload or reboot. The `blacklist` line stops an automatic load at the next boot.

## 6c. USB-C display test, right port (2026-10-26 23:05, module loaded again at 22:48)

Device: a USB-C multi-function dongle with HDMI, a VIA Labs USB 3.1 hub, a Realtek RTL8153 Ethernet adapter and a Genesys microSD reader. Screen: the same Vizio TV as the HDMI tests. Port: the right USB-C port (`port3`, `2-08`).

| Check | Result |
|---|---|
| Type-C partner | `port3-partner` appeared. PD supported. Id header `0x6c00057e`. No alt mode entry is listed in `/sys/class/typec`. |
| Connector | **`card2-DP-3` is `connected` and `enabled`, 33 modes.** `DP-1`, `DP-2` and `HDMI-A-1` stay `disconnected`. |
| Display processor | `2d6c00000.dcp` (dcpext1). Log: `display attached: starting the external display processor`, then `dcp_dptx_connect_session(port=0) die=0 atc=2 dfp_port=0 tunnel=0 typec=1 route=borrowed conn_type=20 connected=1`, `USB4/DPTX: SET_ACTIVE_LANE_COUNT 2`, `display HPD asserted`. |
| Mode set | `mode_set_gated: 3840x2160@30 Hz DSC=NO VRR=NO link: 1`, then `swap 1..3 complete`. The TV offers 4K only at 30 Hz or lower (EDID, HDMI 1.4 class), so this is a TV limit. |
| Desktop | KDE put `DP-3` at 2560x1440 (scale 1.5) next to the panel (extend). |
| Dongle USB side | Works at the same time: hub on USB 3 (10 Gbps root hub), Ethernet `r8152` at 5 Gbps (`enu1u2`), microSD reader on the USB 2 bus. |
| Lanes | 2 DisplayPort lanes (the other lanes carry USB 3), as expected for a multi-function dongle. |
| Warnings seen | Same as the HDMI path: `pmu ram read error (e00002d8)`, `set_timings() called after timings were started`, `Unrecognized data version 0`, `DPTX message 0x85...` flood. |

**Result: DisplayPort over USB-C works on the right port.** The user reported the picture shows on the screen (message cut off: "The HDMI is showing. Through the ..."; read as HDMI through the dongle). The root cause and the fix are confirmed. Open: picture stability over time, the left front and left back ports, Thunderbolt/USB4 devices, 4K60 on a monitor with an HDMI 2.0 EDID, hot unplug, sleep with a cable plugged in.

## 6d. USB-C display test, left front port (2026-10-26 23:07)

Same dongle and TV, moved to the left front port (`port2`, `1-0a`, ATC1). **Works.** `card2-DP-2` is `connected` and `enabled` with 33 modes. Log: `dcp_dptx_connect_session(port=0) die=0 atc=1 ... route=borrowed conn_type=20 connected=1`, `SET_ACTIVE_LANE_COUNT 2`, `mode_set_gated: 3840x2160@30 Hz`. The dongle's hub, Ethernet and microSD reader came up again. Connector map so far: `DP-3` = right port (atc=2), `DP-2` = left front (atc=1). `DP-1` should be the left back port (atc=0), not tested yet.

Side note: when the user pulled the Samsung drive while it was mounted, the log shows `sd 0:0:0:0: [sda] Synchronize Cache(10) failed`. That is a normal result of unplugging a mounted drive. Unmount first.

## 6e. USB-C display test, left back port (2026-10-26 23:08)

Same dongle and TV, moved to the left back port (`port1`, `1-0c`, ATC0). **Works.** `card2-DP-1` is `connected` and `enabled` with 33 modes. Log: `dcp_dptx_connect_session(port=0) die=0 atc=0 ... connected=1`, `SET_ACTIVE_LANE_COUNT 2`, `mode_set_gated: 3840x2160@30 Hz`. The dongle's hub, Ethernet and microSD reader came up again. The `usb 2-1: device not accepting address 2, error -108` lines at 23:08:30 come from the dongle's USB hub leaving the left front port during the move (device gone), not from the new port.

**All three USB-C ports pass DisplayPort Alt Mode, USB 3 data and USB-C power.** Final connector map: `DP-1` = left back (atc=0), `DP-2` = left front (atc=1), `DP-3` = right (atc=2). Not tested: Thunderbolt/USB4 devices (the Thunderbolt bus stayed empty because none was plugged in), 4K60 on a monitor with an HDMI 2.0 EDID, two external displays at once, sleep with a cable plugged in, a permanent install without the autoload block.

## 6f. Thunderbolt/USB4 host-to-host test, M3 left front port to a MacBook Pro M5 (Mac17,2), 2026-10-26 23:10

Rules kept: access went from the Mac to the M3 only. The listener ran on the M3. No network or sharing setting was changed on either machine.

| Check | Result |
|---|---|
| ACIO firmware on the M3 (`b01ac0000.cio`) | `#ACIO FW IS READY# FW_VERSION_STRING=AppleCIOFirmware-450.140.2~106__2025-07-11`. Lane init phases 1 to 3, `Entering Connected`, `Gen2/3 lane=0 entered CL0`, `lane=1 entered CL0`. |
| USB4 router | `thunderbolt 0-0:1.1: new retimer found, vendor=0x5ac device=0x2200`; `thunderbolt 0-1: new host found, vendor=0xa27 device=0xa`; `thunderbolt 0-1: Apple Inc. Mac17,2`. Sysfs: `0-0` (host router "iOS", Apple), `0-1` (XDomain "Mac17,2"), `rx_speed`/`tx_speed` 10.0 Gb/s per lane, 2 lanes. |
| Mac view | Thunderbolt/USB4 bus 3: "Device connected", link status `0x2`, **speed 20 Gb/s**, remote device "fedora", vendor "Linux" (`0x1D6B`). |
| Networking | `thunderbolt_net` loaded by itself. M3 `thunderbolt0` is UP with a link-local address (set by NetworkManager). The Mac's Thunderbolt Bridge `bridge0` is active . |
| Ping, Mac to M3 | 4 of 4 replies, 0 % loss, 0.23 to 0.44 ms. |
| Throughput, Mac to M3 | **3.84 Gbit/s** (4000 MiB in 8.73 s), one TCP stream, MTU 1500, a plain Python sender and receiver. This is a lower bound, not the link limit. |
| PD partner on M3 `port2` | Present, PD supported, id header `0xd54005ac` (Apple vendor ID `0x05ac`). Both machines show host/source roles; no charging problem seen. |
| Warning seen | `thunderbolt-apple-nhi b01f00000.nhi: device links to tunneled native ports are missing!` (once, at probe). |

Notes:

- The link trained at 20 Gb/s (2 lanes at 10 Gb/s), half of the 40 Gb/s the Mac port can do. This may come from the cable (a 20 Gb/s rated cable) or from the driver (the log shows `gen=1` for both sides). To separate the two, repeat with a certified 40 Gb/s Thunderbolt 4 cable.
- The first throughput tries with `nc` ended early (the receiving `ncat` closed after the first packets). That is a test tool issue, not a link fault. The `ssh` try failed because no `sshd` listens on port 22 of the link address (only Tailscale SSH runs).
- Not tested: DisplayPort tunnels and PCIe tunnels behind a dock or display, multi-stream or jumbo-frame speed, hot unplug, sleep with the cable connected.

## 6h. Thunderbolt/USB4 host-to-host test, M3 left back port (`1-0c`, ATC0, `701ac0000.cio`), 2026-10-26 23:18

Same cable and Mac, same rules. ACIO: `Entering Connected`, `Gen2/3 lane=0` and `lane=1 entered CL0`, `new retimer found`, `thunderbolt 0-1: Apple Inc. Mac17,2`. Mac view: bus 3, "Device connected", 20 Gb/s. `thunderbolt0` UP. Ping 4 of 4, 0 % loss, 0.26 to 0.44 ms. Throughput **3.78 Gbit/s** (4000 MiB in 8.89 s, one Python TCP stream, MTU 1500). The `usb 1-1: device not accepting address 2, error -108` line at 23:18:12 comes from the dongle's hub leaving this port when the cable replaced it.

**USB4 host-to-host works on all three ports.**

## 6g. Thunderbolt/USB4 host-to-host test, M3 right port (`2-08`, ATC2, `f01ac0000.cio`), 2026-10-26 23:16

Same cable and Mac. Same rules (Mac to M3 only, listener on the M3).

- ACIO: `Entering Connected`, `Gen2/3 lane=0` and `lane=1 entered CL0`, `new retimer found`, `thunderbolt 0-1: new host found ... Apple Inc. Mac17,2`. Sysfs `0-1` shows 10.0 Gb/s per lane, 2 lanes.
- Mac view: bus 3, "Device connected", 20 Gb/s, remote device "fedora".
- `thunderbolt0` UP with a link-local address. Mac `bridge0` got its address a few seconds after the link .
- Ping Mac to M3: 4 of 4, 0 % loss, 0.25 to 0.42 ms.
- Throughput Mac to M3: **4.13 Gbit/s** (4000 MiB in 8.12 s), one Python TCP stream, MTU 1500 (lower bound).

**USB4 host-to-host works on two of three ports** (left front `1-0a`, right `2-08`). The left back port (`1-0c`) is not tested with the cable. Test tool notes: my first sink restart used `pkill -f` and killed its own SSH shell (test script error, not a link fault).

## 7. What was not checked

- `/sys/kernel/debug/devices_deferred` and `dyndbg` traces (need root). The deferral cause comes from source and sysfs.
- Whether `thunderbolt_apple` compiles in this tree with the exact build config. The symbol exists and the config resolves, but no object was built (task rules).
- The cover letter and patch text of the upstream series (lore.kernel.org blocked). Dates come from press and the local git log.
- The first and third PD controllers' device tree labels. `1-0c` was read ("USB-C Left Back"). The labels for `1-0a` and `2-08` come from the `.dtsi` comment (left front, right).
- Any physical port behaviour. No cable or display was used.

## 8. Permanent install plan (written 2026-10-26, nothing below is done yet)

State at the time of writing (read-only checks, 23:2x): `thunderbolt_apple` is loaded by hand (up 41 minutes, no reboot since). The installed file `/usr/lib/modules/7.2.11-m3gpu+/kernel/drivers/thunderbolt/thunderbolt_apple.ko` has SHA-256 `7ff10b33...cb9ef`, the same as the staged build in `~/m3gpu/out/kernel-7.2.11-m3gpu+-usb4-bt`. The autoload block is the file `/etc/modprobe.d/m3gpu-thunderbolt-apple.conf` (`blacklist thunderbolt_apple`). The M3 copy of `build/build-kernel.sh` already has `cfg --module USB4_APPLE_SOC` (line 33) and `check "CONFIG_USB4=y"` (line 63). The kernel image (`vmlinuz`) did not change, so **no new kernel is needed**.

| Step | What | Who | Needs |
|---|---|---|---|
| P1 | Keep the config line in `build-kernel.sh` for every later kernel build. Keep the module in the staged tree. | GPU session | Nothing new |
| P2 | Run one suspend and resume (lid close and open, or `systemctl suspend`) with the module loaded, first with no cable, then with one USB-C device. Pass: the M3 resumes, the three PD controllers stay bound, `/sys/bus/thunderbolt/devices` and `DP-1..3` work after resume, no new error in `journalctl -k`. | Sleep session (coordinator schedules it) | The user's go. No password needed if the sudo window is open. |
| P3 | Remove the autoload block: `sudo rm /etc/modprobe.d/m3gpu-thunderbolt-apple.conf`. The module then loads at boot by its device tree alias (`apple,t6030-usb4-acio`). The module exists only in the `7.2.11-m3gpu+` tree, so the stock Fedora kernel `7.1.13` is not affected. | GPU session | The user's own go and sudo |
| P4 | One reboot into `7.2.11-m3gpu+`. Health check: three PD controllers bound, `cio` devices bound to `thunderbolt-apple-acio`, `port1..3` present, `DP-1..3` work with the dongle, host-to-host link up, boot log has no new error, journal size normal. | GPU session + user | The user's go for the reboot |
| P5 | Rollback if boot or health check fails: boot the stock kernel `7.1.13` (or macOS), then `sudo tee /etc/modprobe.d/m3gpu-thunderbolt-apple.conf` with `blacklist thunderbolt_apple`, or `sudo rm` the `.ko`, then `sudo depmod 7.2.11-m3gpu+`. If `7.2.11-m3gpu+` boots, only the file in `/etc/modprobe.d` has to be put back. | GPU session | The user's go |

Risks: the ACIO driver boots a coprocessor and resets PCIe-C at every load, now at each boot. In the tests it loaded 2 times without a fault. A fault at boot would need a rollback from another kernel. Sleep with the module loaded is not tested yet (P2). If P2 fails, keep the autoload block and load the module by hand when needed.

## 9. Final recommendation

**Go.** Enable `CONFIG_USB4_APPLE_SOC=m` permanently (already in `build-kernel.sh`) and install the module without the autoload block, in this order: P2 (sleep test with the module loaded), then P3 and P4 (remove the block, one reboot, health check).

Why:

- Root cause confirmed: the driver existed but was not built. One config line made all three PD controllers and `cio` devices bind.
- Tested on all three ports with real hardware: USB-C data, USB-C power, DisplayPort Alt Mode (3840x2160@30 on a 4K TV), and USB4 host-to-host to a MacBook Pro M5 (20 Gb/s link, 0 % ping loss, 3.8 to 4.1 Gbit/s).
- No kernel change beyond one symbol. The image and all other modules are byte-identical.

Open items after the install (none blocks it):

1. Thunderbolt dock or display behind the router (DisplayPort tunnel and PCIe tunnel). The driver has code for both, and the author's own note (`e3291940988f`, 2026-10-20) says second-display qualification on M3 is still blocked. Test with the user's dock.
2. Link speed: 20 Gb/s only. Try a certified 40 Gb/s Thunderbolt 4 cable to see if the limit is the cable or the driver (`gen=1` in the ACIO log).
3. Sleep and lid close with a cable plugged in (P2 covers the no-cable case).
4. 4K at 60 Hz needs a monitor with an HDMI 2.0 or DisplayPort EDID. The TV used offers 4K only up to 30 Hz.
5. Log noise: the `DPTX message 0x85...` flood (about 3 lines per second) fills the journal.
6. Two displays at once (each USB-C or HDMI path uses one of the two display processors).

## 10. Maintenance window log (2026-10-27)

- **P2, sleep test with the module loaded: pass, 3 of 3 cycles** (s2idle success 1 to 3). Cycle 1 ran with the Mac cable plugged into the left back port: at suspend the log shows `Gen2/3 link error ... error=83` on both lanes and `thunderbolt 0-1: host disconnected`; after the resume the ACIO firmware came back ready and both lanes entered `CL0`. Cycles 2 and 3 ran with no cable. After each resume: the module stayed loaded, PD controllers `1-0a`, `1-0c`, `2-08`, `1-06` stayed bound, the three `cio` devices stayed bound, `port1..3` present, no `thunderbolt`, `acio`, `typec` or deferred-probe error, journal 256.7 MB. The 4.1 s resume time comes from the Bluetooth chip (`hci0 0x0c01 tx timeout`, then `recovering transport once after resume command timeout`) and Wi-Fi `-52` errors, not from USB4.
- **P3, autoload block removed** (01:40 local time on the Mac, after the user's approval in the session; the first try was denied by the app's permission check): `/etc/modprobe.d/m3gpu-thunderbolt-apple.conf` deleted. `modprobe -c` shows no `blacklist`, `install` or `softdep` rule for `thunderbolt_apple`. No other file blocked the module (modprobe.d, modules-load.d, dracut, udev rules, kernel command line). The module is still loaded.
- **P4, boot check after the reboot (2026-10-27 01:43, `7.2.11-m3gpu+`, no cable and no dongle plugged in, by the user's choice): pass.** `thunderbolt_apple` loaded by itself at boot (used by 3). PD controllers `1-0a`, `1-0c`, `2-08`, `1-06` bound to `sn201202x`. The three `cio` devices bound to `thunderbolt-apple-acio`. `port0` to `port3` present. `deferred probe pending` count this boot: 0. No `thunderbolt`, `acio`, `typec` or `usb4` error. Journal 258 MB. Not tested after this boot: the Mac cable (host-to-host) and the dongle (DisplayPort); both wait for a later test.
  - **New warning at this boot, not seen on the three earlier boots:** `dwc3-apple f02280000.usb: late IOMMU probe at driver bind, something fishy here!` (`WARNING: drivers/iommu/iommu.c:655 at __iommu_probe_device`, task `udev-worker`, module list shows `dwc3_apple(E+)`). It is a module-load ordering race: udev loaded `dwc3_apple` for the right port before its IOMMU (DART) device was ready. The device still joined IOMMU group 9 and `dwc3-apple` is bound on all three ports. It is one line per boot, not a fault, but it is new since the module loads at boot, so watch whether it returns on the next boots and whether USB on the right port still works. A fix, if needed, is a `softdep` or an earlier load of the DART driver (GPU session).
- **Health scripts:** `tests/health-check.sh` now expects `thunderbolt_apple` loaded and the three PD controllers and `cio` devices bound. `tests/pre-reboot-check.sh` now expects no blacklist file.
- **P5 (rollback), only if needed:** recreate `/etc/modprobe.d/m3gpu-thunderbolt-apple.conf` with the single line `blacklist thunderbolt_apple` from another kernel or macOS.
