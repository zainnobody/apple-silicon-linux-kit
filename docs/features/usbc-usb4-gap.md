# USB-C display, USB-C data and Thunderbolt/USB4 on the M3 Pro 16-inch (J516S): root cause and fix plan

Researched 2026-10-26. Read-only work on the M3 (`user@<m3-tailscale-ip>`). No kernel, boot entry, m1n1 or firmware change. No reboot. No sudo.
Kernel under test: `7.2.11-m3gpu+` (build `#6`, 2026-10-26 20:18 PDT). Source tree: `~/m3gpu/src/linux`, tag `v2026.10.19-pr363-native.1`, origin `iconidentify/siliconforest-linux`.

## Short answer

**The driver exists. The kernel config does not build it.** `CONFIG_USB4_APPLE_SOC` is `not set` in the running kernel. The source tree has the full ACIO/NHI driver (`drivers/thunderbolt/apple.c`, 3277 lines) and it already matches `apple,t6030-usb4-acio`. The device tree nodes exist. m1n1 already filled the tunables. No firmware file is needed.

Without that driver, nothing registers the "thunderbolt switch" that the PD controller driver waits for. The three PD controllers return `-EPROBE_DEFER` forever. That is the "deferred probe pending: (reason unknown)" line. The same missing driver blocks USB-C data, USB-C charging control, DisplayPort Alt Mode and Thunderbolt on all three ports.

**Fix: one config line (`CONFIG_USB4_APPLE_SOC=m`) in `agx-linux-kit/build/build-kernel.sh`, then one rebuild.** A dry run on a scratch copy of the config changes that one symbol and nothing else.

The earlier note in `display-hdmi.md` ("add the T6030 compatible to the ACIO driver") is not needed. The compatible is already in the driver table.

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

## 7. What was not checked

- `/sys/kernel/debug/devices_deferred` and `dyndbg` traces (need root). The deferral cause comes from source and sysfs.
- Whether `thunderbolt_apple` compiles in this tree with the exact build config. The symbol exists and the config resolves, but no object was built (task rules).
- The cover letter and patch text of the upstream series (lore.kernel.org blocked). Dates come from press and the local git log.
- The first and third PD controllers' device tree labels. `1-0c` was read ("USB-C Left Back"). The labels for `1-0a` and `2-08` come from the `.dtsi` comment (left front, right).
- Any physical port behaviour. No cable or display was used.
