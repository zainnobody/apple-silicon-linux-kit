# AVE on M3 Pro (t6030): Stage 0 working notes

Started 2026-10-27. Offline only. The M3 was not touched.
Collected into agx-linux-kit on 2026-10-27 from the local work folder. The DPE table output stays private (not in any repo).
Upstream clone: ../upstream (aquarat/apple-m-series-ave-driver, 9ab14e4). Hardware addresses here come from the macOS ADT of this machine.

## Done
- tools/dpe_build.py: builds AVEDPE01 files for macOS 26 kernelcache sets (control: Atlas_8112 = 1/124/123 entries, as upstream docs/90). Output: private-dumps/ave-m3-tables/ (not in any repo).
- tools/devcap_probe.py: dumps raw DevCap entries.
- drafts/: overlay and SoC row skeletons.

## Findings
1. Janus_6030 DPE set: 2 CAT, 124 CAC default, 123 CAC 8-bit entries. Same counts as Castor and Atlas for CAC, but only 41 to 42 of 124 entries equal. Offsets reach 0x468 (M1/M2 sets stop at 0x1ec). New offsets from 0x324. The upstream tool refused it (limit 0x400): the CAC window layout changed on M3. Janus_6031 and 6030 share 71 of 124.
2. DevCap CEntry_6030 has the same word layout as 6000, 8103 and 8112 (header words, same table shape). No new top-level field. The (dev_id, dev_type, chip_type) triple is not read yet (needs AVE_DevCap_Find disassembly, upstream tools/disas.py).
3. Power gates map by pmgr id2 (record offset 0x1a, name at 0x20 in 0x30-byte records): see the overlay draft. Names match the t6001 overlay labels (sys, pipe4, pipe5, me0, me1, dma) plus four VENC performance-vote domains.
4. The M1 Pro ADT ave0 also has 5 interrupts, 5 reg banks and 11 power gates (upstream data/derived/adt-ave-nodes.txt). The M3 node (5, 5, 10) has the same shape, and the DPE, ASC and AXI2AF banks have equal sizes (0x45c000, 0x800000, 0x1000000). The M3 block is structurally close to the M1 Pro.
5. DART: dart,t8110, streams 0, 12, 15 (bypass-12, bypass-15). Upstream M1 overlays use streams 0 and 1; M2 uses 0 and 15. Stream 12 is new to this driver.
6. H15S image: layout equals the ADT segment-ranges (TEXT 0x128000 at 0, DATA 0x12c000 at 0x128000). Board map in upstream data/derived/board-to-ave-firmware.txt: j514s and j516s use H15S (IPSW 26.6.2).
7. Host kernelcache (macOS 26.7.1) AppleAVE2 905.41.1 carries t6030 tables; M3's own OS is 15.6.1: version pairing still open.

## Added later on 2026-10-27 (coordinator go, offline)
8. DevInfo for t6030: kext name table (soc-id numbers, index = devID-1) and device table found in the macOS 26.7.1 kernelcache (tools/devinfo_probe.py). Controls match upstream docs/08: 6000 = 11/9/6, 6001 = 12/10/7. 6030 = 21/19/12, 6031 = 22/20/12 in 26.7.1.
9. The H15S firmware has its own device table (31 entries at DATA+0x2a0, stride 0x38, indexed by DevID; AVE_DevCap_Find indexes by DevID only; +4 devType, +8 chipType). Entry 21 = DevType 19, ChipType 11. DevID and DevType agree with the kext for t6030 and 8112; ChipType is one lower (t6001: 6 vs 7). Working value for the macOS 15.6.1 pair: 21/19/11. Which DevID is t6030 in 15.6.1 is inferred from the same ordering. Confidence: medium.
10. STKG at DATA+0x2a28. Same fill tags as M1/M2 (STKG, SOC_, SOCR, CpAd, WrAd, IOBA) and a tunables table at DATA+0x4038, 0x5b0 bytes, capacity 36 (M1 had 21 to 23). Same iBoot fill mechanism.
11. TEXT windows: offsets 0, 0x80000, 0x124000 (16 KiB each); digests in drafts/text_win_h15s.inc.

## Stage 0b result (live tree dump from the coordinator, 2026-10-27, read only)
12. No ave, apr or venc node except the six power domains: venc_sys@3d0, venc_dma@8000, venc_pipe4@8008, venc_pipe5@8010, venc_me0@8018, venc_me1@8020 (all exist; sys, dma and me0 carry phandles 0x60, 0x61, 0x62; pipe4, pipe5 and me1 have none). Parents: pipes and me0 under dma, dma under sys, me1 under me0.
13. AIC is apple,t6030-aic3 with #interrupt-cells = 3 (M1 overlays use 4). ADT interrupt numbers map straight into the tree (avd 0x314, 0x315 and its DART 0x31b match). AVE: 810, 804, 803, 806, 805; DART 807.
14. All 29 DARTs are "apple,t6030-dart", "apple,t8110-dart". No dart-ave node.
15. pmp-report has entries 7, 8, 9, 10 only (disp, dispext0/1, ans). No VENC entry, so the speed vote cannot be used without adding one.
16. Not answerable from the Linux tree: whether the boot ADT still has pre-loaded and segment-ranges for ave (Linux drops them). Needs the m1n1 console or a proxy read at boot.

## Open, in order
1. (done) DevInfo, STKG, TEXT windows.
2. Confirm the 15.6.1 ABI numbers: needs the M3's own macOS 15.6.1 kext, or a live handshake result.
3. Check driver code for hard-coded DPE register offsets that moved (grep ave_hw.h, ave_session.c for 0xDC4xx accesses) now that finding 1 shows a different CAC window.
4. Stage 0b (needs the user's go): read-only look at the live Linux tree on the M3: labels of the venc power domains, AIC cell format, whether the boot ADT still has pre-loaded and segment-ranges for ave.
