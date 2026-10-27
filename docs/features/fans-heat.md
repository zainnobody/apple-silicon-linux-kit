# Fans and heat on the M3 Pro (2026-10-27)

## Problem

Under Linux both fans stay off, even at a 100 C PMP hotspot.
The SMC keeps fan target 0 in auto mode. macOS has `thermalmonitord`, which asks the SMC for cooling. Linux has no such service.
The GPU session heat soak (CPU plus GPU, 2026-10-27) reached a 100 C hotspot after 5.6 minutes with the fans at 0 rpm.

## Fan keys and the M3 firmware

| Key | Use |
|---|---|
| `F0Ac`, `F1Ac` | actual speed (rpm) |
| `F0Tg`, `F1Tg` | target speed (rpm) |
| `F0Mn`, `F0Mx` | minimum and maximum (fan 1: 1350 to 5349 rpm, fan 2: 1458 to 5777 rpm) |
| `F0Md`, `F1Md` | mode: 0 = system (auto), 1 = manual |
| `Ftst` | unlock flag: the M3 firmware rejects a mode write until it is 1 |

The stock `macsmc_hwmon` with `fan_control=1` makes `fanX_target` writable. On the M3 the write fails with EIO, because the mode write fails.
`patches/macsmc-hwmon-ftst-unlock.patch` sets `Ftst` to 1 and retries the mode write every 500 ms for up to 10 s.
The M3 accepts it after about 8 s. When no fan is in manual mode, the patch sets `Ftst` back to 0.

## Manual test (2026-10-27)

Target 2000 rpm on both fans for 30 s, then target 0:

| Time | Fan 1 rpm | Fan 2 rpm |
|---|---|---|
| unlock | write OK after 8 s | write OK after 8 s |
| +5 s to +30 s | 1994 to 2008 | 1988 to 2017 |
| back to auto | 0 | 0 |

## Fan curve service

`tools/m3-fancurve.sh` reads the SoC die zone (`macsmc_soc_die`) and the PMP hotspot every 2 s.
It uses the hotter of the die value and (hotspot minus 10 C). A rise counts at once; a fall is smoothed.
A step down needs the value to fall 3 C below the step.

| Temperature | Fan target |
|---|---|
| below 62 C | 0 (SMC auto) |
| 62 C | 1500 rpm |
| 70 C | 2200 rpm |
| 78 C | 3000 rpm |
| 86 C | 4000 rpm |
| 92 C | 5000 rpm (fan 1 max 5349) |

A step up is at once. A step down waits for 15 lower readings (30 s), because the hotspot is spiky.

Fail-safe: these events set both fans back to target 0 (SMC auto):

- the script exits or gets TERM or INT (trap)
- the SoC die sensor is unreadable
- the service stops for any reason, `kill -9` included (`ExecStopPost`)

After a restart, the script writes the fan state on its first reading. If a fan write fails, the script keeps the old step and tries again 2 s later.

Install and undo (root, on the M3):

```bash
sudo tools/m3-fancurve-install.sh /path/to/patched/macsmc-hwmon.ko
sudo tools/m3-fancurve-install.sh --undo
```

The installer puts the module in `/lib/modules/<kernel>/updates/` and enables `m3-fancurve.service`.
The initramfs holds the stock module, so the service reloads the module with `fan_control=1` at start.
The initramfs and `/etc/modprobe.d` stay unchanged. A new kernel needs the patch in its build.

## Load test with the fan curve

Same load as the GPU session heat soak (`heat-soak.sh`): vk-stress, then 7-Zip on 12 cores plus vk-stress. Charger in, heat guard on.
Without fans: the 10-minute run at 10:13 (phases of 600 s). With fans: the 7-minute run at 11:06 (phases of 420 s), fan curve in the foreground without the 30 s hold.

| Value | Fans off (SMC only) | Fan curve |
|---|---|---|
| GPU only: PMP CPU hotspot max | 80.8 C | 72.8 C |
| GPU only: SoC die max | 68.6 C | 61.2 C |
| GPU only: fans max | 0 rpm | 1630 / 1602 rpm |
| CPU + GPU: PMP CPU hotspot max | 99.2 C (heat guard stop at 100 C in the earlier run) | 95.2 C |
| CPU + GPU: SoC die max | not in the 10:13 run | 61.6 C |
| CPU + GPU: fans max | 0 rpm | 3036 / 3033 rpm |
| CPU + GPU: vk-stress | 263.56 G/s (GPU phase) | 263.30 G/s |
| CPU + GPU: 7-Zip average rating | 70,979 | 69,556 (minus 2 %) |
| CPU + GPU: P-core clock average | 4,036 MHz | 4,019 MHz |
| Heat guard | stopped the load in the earlier run | no stop |

Without fans the CPU hotspot passed 95 C 27 s after 7-Zip started. With fans it first reached 95 C after 3.5 minutes, for one 2 s sample.
The CPU hotspot follows short 7-Zip peaks, so the fans cut its maximum by about 4 C only.
The SoC die and the GPU-only hotspot drop by about 7 C.
Without the hold, the fans changed between 2200 and 3000 rpm every 2 to 8 s. The 30 s hold stops this.

### Fail-safe tests (2026-10-27, service installed)

| Test | Result |
|---|---|
| Boot path: stock module with `fan_control=N`, then service start | module reloaded from `updates/`, `fan_control=Y`, service active |
| Fans at 1500 rpm by hand, `kill -9` of the script | `ExecStopPost` set both targets to 0 within 2 s; restart after 5 s wrote 0 again |
| `systemctl kill -s KILL` (kills the whole unit, `ExecStopPost` included) | first script version left the fans at 1500 rpm; fixed: the restarted script writes the fans on its first reading |
| Manual write right after a clear of `Ftst` | one EIO (unlock took more than 10 s); fixed: the script keeps its step and tries again |

### Load test with the installed service (11:25, phases of 240 s, 30 s hold on)

| Value | Result |
|---|---|
| GPU only: PMP CPU hotspot max | 72.8 C |
| GPU only: SoC die max | 61.6 C |
| GPU only: fans max | 1616 / 1609 rpm |
| CPU + GPU: PMP CPU hotspot max | 93.8 C (never 95 C) |
| CPU + GPU: SoC die max | 61.4 C |
| CPU + GPU: fans max | 4028 / 4017 rpm |
| CPU + GPU: vk-stress | 263.26 G/s |
| CPU + GPU: 7-Zip average rating | 69,563 |
| CPU + GPU: P-core clock average | 4,030 MHz |
| Fan speed changes | 7 in 4.5 minutes (about 70 without the hold) |
| Heat guard | no stop; desktop (KWin, plasmashell) stayed up |
