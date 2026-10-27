# M3 Pro memory speed: what the Apple device tree shows (2026-10-26)

Source: read-only dump of the Apple device tree (ADT) in macOS 15.6.1 on the MacBook Pro 16-inch M3 Pro (Mac15,7, T6030), with `tools/adt-power-dump.sh`. The full dump stays private (it holds machine identifiers) and is not in this repository.

## Problem

Under Linux, the CPU and the GPU read memory at about 32 GB/s. In macOS, the same machine reads 115 GB/s (see `performance.md`, "Memory bandwidth").

## Findings

1. **The PMP controls memory and fabric speed.** The thresholds for memory speed changes are properties of `iop-pmp-nub`, under `pmp@40C00000`. This is the PMP, a power-management coprocessor (`compatible = "iop-nub,rtbuddy-v2"`, firmware `t6030pmp`, `pre-loaded = 1`: the boot firmware loads it, the operating system starts it).
2. **Speed areas.** The PMP property `dvfs-domain` lists five areas:

   | Index | Name | Levels |
   |---|---|---|
   | 1 | DCS (memory controller) | 5 |
   | 2 | SOC | 3 |
   | 3 | DISP_INT | 3 |
   | 4 | FAB (fabric) | 3 |
   | 5 | DISP_EXT | 4 |

   DCS has 5 levels (0 to 4), the same count as on T8140, where the fork's PMC driver uses `dcs_max = 4`.
3. **Bandwidth-driven.** The PMP has bandwidth thresholds per source: `dcs-bw-threshold`, `dcs-rd-bwr-threshold`, `dcs-wr-bwr-threshold`, `agx-dcs-bw-threshold` (GPU), `ane-fast-dcs-bw-threshold` and `ane-slow-dcs-bw-threshold` (Neural Engine), `soc0/1-rd/wr-bwr-threshold`, `ioa0..3-afnc-bw-threshold`, and `agx-af-*` for the fabric. So macOS gives the PMP these values, and the PMP raises DCS and fabric levels when it sees traffic.
4. **No PMC node.** The ADT has no node named `pmc`. `clpc` (`compatible = "clpc,t6030"`) is a PMGR nub with `soc-devices = <3 4 6>` and interrupts, but no register ranges of its own.
5. **Memory facts.** LPDDR5, Hynix, `dcs-count-per-amcc = 6`.

## What this means for Linux

On this kernel the PMP is only a power gate (`ps_pmp` in `t6030-pmgr.dtsi`). No Linux driver starts the PMP firmware and sends it its configuration. So no agent raises DCS or fabric speed, and memory stays at the level the boot firmware left. This fits one shared limit of about 32 to 37 GB/s for all CPU clusters and the GPU.

This is a strong explanation, but not proven. The proof is a measurement after DCS goes up.

## Possible fixes, from simplest to most complete

| Option | Work | Risk |
|---|---|---|
| A. A fixed DCS vote from the AP through the PMC (as the fork does on T8140) | Find the T6030 PMC register layout by m1n1 hypervisor tracing of macOS; add `apple,t6030-pmc` to `pmc.c` and a DT node | Medium: needs traced, not guessed, offsets |
| B. Start the PMP (RTKit) and send it the ADT thresholds (as macOS does) | Trace the macOS PMP driver's RTKit messages with the m1n1 hypervisor; write a PMP driver | Medium to high, weeks |
| C. Set a DCS level once in m1n1 before Linux starts | Same tracing as A; a small m1n1 change | Medium; no load-based scaling |

All three need m1n1 hypervisor tracing first: run macOS under m1n1 from the host Mac over USB-C and log writes to the PMGR, PMP and PMC areas during boot and under memory load. No register value is written from a guess.
