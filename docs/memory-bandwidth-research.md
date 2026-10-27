# Memory bandwidth on Apple Silicon under Linux: research notes (2026-10-26)
[V] = I read the source. [I] = inferred.
Sources read: AsahiLinux/linux (asahi branch), AsahiLinux/m1n1 (main), iconidentify/siliconforest-linux
(redirects to chriskearney/siliconforest-linux), branch siliconforest/next (head 65cd54ba0d).

## 1. How Asahi raises memory bandwidth on M1, M1 Pro/Max, M2, M2 Pro/Max
- [V] Upstream Asahi has NO memory-controller perf-state driver. The original cpufreq commit 6286bbb405
  (Nov 2022) says: "This driver does not yet implement the memory controller performance state tuning
  that usually accompanies higher CPU p-states. This will be done in a future patch." I found no such patch.
- [V] The PS2 field (bits 15:12 of the cluster DVFS command register) is written only when has_ps2 is true
  (t8103 only). Commit 4a06c250ab "Drop setting the PS2 field on M2+" (Hector Martin, Dec 2024) says:
  "It is not known what this field does", and that M2+ must match macOS. So PS2 is not a proven memory vote.
  The code uses it only as a copy of the P-state.
- [V] m1n1 src/mcc.c (mcc_enable_cache, called from kboot_boot) turns on the system level cache (SLC) in each
  memory cache controller plane. It handles t8103/t8112, t600x/t602x, and M3 (mcc_init_m3: mcc,t6030,
  mcc,t6031, mcc,t8122). This is cache enable plus TrustZone carveout unmapping. It is not a bandwidth or DCS
  frequency control. [I] If the SLC were off, bandwidth would fall, but M3 Pro mcc,t6030 is covered, so check
  the m1n1 log line "MCC: System level cache enabled".
- [V] m1n1 has no DCS or fabric perf-state code. dcs references are only dcs_num_channels (startup.c), MCC
  register offsets, and the T8012 pmgr always-on fix.
- [I] On M1/M2 the DRAM controller and fabric appear to be left at the iBoot state, which is already fast.
  Support: the Asahi GPU blog reports GPU buffer clears at 355 GB/s on M1 Ultra under Linux, near peak
  (the search snippet is secondhand; I did not open the post).
- [V] SiliconForest has the only memory-rail code I found, for T8140 (not M3):
  - drivers/pmdomain/apple/pmc.c, binding power/apple,pmc.yaml, compatible "apple,t8140-pmc". The PMC
    "arbitrates the perf state of shared rails (DRAM controller DCS, SoC fabric) between voter agents (PMP,
    CLPC, GPU, AP)". Each agent has a 4-bit-per-rail floor word. A rail honours an agent only if its enable
    bit is set. T8140 regs: voters at 0x302800000, rails at 0x3028aa000.
  - drivers/soc/apple/clpc.c, compatible "apple,t8140-clpc". Its header says macOS CLPC raises the DCS and
    fabric floor while CPU or GPU are busy, and that "the native mapping ... has not been decoded". Module
    parameters: dcs_map (default 1,2,3,4), soc_map, gpu_dcs, gpu_soc, sample_ms, busy_pct, hold_ms. Debugfs:
    status, force.
  - T8140 pmc.c hw: 4 agents, 4 rails, dcs_rail 0, dcs_max 4, AP agent 3.

## 2. Reported CPU bandwidth, Linux vs macOS
- [I] I found no public STREAM, sysbench or mbw comparison for Asahi M1/M2 in web search. No known large CPU
  shortfall on M1/M2, and no fix commit. The ~half-of-peak CPU limit on Max parts is a macOS-side fact (a
  secondhand Hacker News claim, unverified).
- Phoronix M1 review: Linux lagged macOS mainly because P-core boost states were not reached.

## 3. T6030 / M3 specifics
- [V] t6030.dtsi: cpufreq nodes at 0x210e20000 (E) and 0x211e20000 (P), compatible t6030 then t8112. The
  t8112 info (has_ps2 false) is used. This matches macOS behaviour for M2+.
- [V] SiliconForest T6030 DT has no pmc, clpc, dcs-perf or memory-perf node. pmgr has ps_dcs0..9 power
  domains only (power gates, not perf). Only T8140 has PMC/CLPC support.
- [V] T6030 has a PMP (power management processor): t6030-pmp.dtso, drivers/soc/apple/m3/pmp-core.rs,
  pmp-display.c. It starts only when the display driver first asks for it. grep of pmp*.rs found no DCS,
  bandwidth or floor code. pmc.c says the "PMP's DCS vote follows GPU load".
- [V] drivers/soc/apple/mcc.c is T8140-only (SLC allocation enable); not bound on T6030.
- [I] Best hypothesis: on M3 (like T8140) the DCS and fabric rails are arbitrated by a PMC with voter floors.
  The firmware or macOS CLPC and PMP raise the floor under load. Linux casts no vote, so the DRAM rail sits
  at a low iBoot or PMP-idle state. A flat ~32 GB/s for both CPU and GPU (about 21 % of 150) supports one
  shared rail cap, not a CPU-side limit. Whether T6030 has the same PMC layout is unverified.
- No SiliconForest or linux-aurora issue or commit about M3 bandwidth was found (GitHub code search did not
  index the fork; I used the tree and file reads).

## 4. Low-risk tests
Safe (read only or userspace):
1. Vary CPU frequency (scaling_max_freq 1.0, 2.0, 4.0 GHz) and rerun the 1 GiB sum. If bandwidth stays
   ~32 GB/s, the cap is not CPU clock. [I]
2. Run CPU read and GPU Vulkan read together. If the total stays ~32 GB/s, the cap is shared (DRAM/fabric
   rail). If it adds up, the cap is per master.
3. Check dmesg for "MCC: System level cache enabled" (m1n1 log), PMP start messages, and `ls /sys/class/devfreq`.
4. Read-only: dump the ADT on macOS or via m1n1 (`proxyclient/tools/dump_adt.py`) and look for pmc, pmp,
   clpc, dcs nodes and tunables on T6030. Check "dcs-count-per-amcc" and "plane-count-per-amcc".
5. Compare idle vs sustained CPU load for 1 s: the T8140 CLPC holds a floor for ~32 ms after demand. Bandwidth
   that rises under load hints at a PMP/CLPC vote path.
6. Check DT clock names/regs of T6030 ADT pmgr for a PMC-like window. Reading from the ADT is safe.
High risk (do not do without a recovery path):
- Any MMIO read or write at guessed PMC/DCS/AMCC/PMGR addresses (devmem, m1n1 poke): wrong address gives an
  SError hang, and a write can lock the DRAM rail or crash the machine.
- Porting apple,t8140-pmc and clpc to T6030 with guessed offsets. Writing DVFS PS2 via a has_ps2 = true
  patch on T6030: low harm but unproven, since upstream says the field does not matter on M2+.
- m1n1 hypervisor tracing of macOS (hv trace of PMC/DCS regs) is the safe way to learn real register
  layouts: it only observes macOS writes. This is the path to decode the T6030 voter map.
