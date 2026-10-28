# Performance and stability

Measurements on the MacBook Pro 16-inch M3 Pro (Mac15,7, 12-core CPU, 18-core GPU, chip revision B1), unless a row says otherwise.

## GPU shader throughput: same math on each system

`tests/gles-stress.c` (Linux, GLES fragment shader) and `tests/metal-stress.swift` (macOS, Metal compute kernel) run the same integer work: each pixel of a 1024x1024 target runs 400 xorshift steps with a new seed per frame. Every 10th frame is read back and compared with the same math on the CPU, so a wrong result shows at once. The unit is billion pixel-iterations per second (G pixel-iter/s).

| Date | GPU | System, driver | Run | Frames/s | G pixel-iter/s | Wrong values |
|---|---|---|---|---|---|---|
| 2026-10-26 | M3 Pro, 18 cores | Fedora, kernel 7.2.11-m3gpu+, SiliconForest Mesa 26.3.0-devel | 600 s | 543.7 | 228.0 | 0 of 32,621 checks |
| 2026-10-26 | M5, 10 cores (host Mac) | macOS 26, Metal | 20 s | 242.3 | 101.6 | 0 of 485 checks |
| 2026-10-27 | M3 Pro, 18 cores | macOS 15.6.1 on the same M3, Metal compute kernel | 0 to 450 s of a 600 s run | about 317 | about 133 | 0 of 14,831 checks |

Notes:
- Per GPU core: M3 Pro on Linux about 12.7, M5 on macOS about 10.2 G pixel-iter/s.
- Estimate of the hardware limit (not measured): 18 cores x 128 ALUs x 1.38 GHz (top GPU state in the kernel log) is about 3.2 trillion integer operations per second. One step is about 7 operations, so about 450 G steps per second. Linux reaches about 50% of that, and the CPU checks stop the GPU every 10 frames. The 128 ALUs per core is the commonly reported figure, not an Apple specification.
- Fragment shader (Linux) and compute kernel (macOS) are not identical paths. Both rows on the M3 Pro do the same math on the same chip, but through different shader stages, so the ratio is not a pure driver comparison.
- macOS on the M3 (2026-10-27): the steady rate is about 9,510 frames per 30 s from 0 to 450 s. After 450 s the SSH link dropped and macOS most likely went to sleep: only 5,710 frames ran from 450 s to 740 s. The printed average of 84.02 G pixel-iter/s includes that gap, so it is not used here. Binary sha256 2a97d90b...
- On this test, the Linux fragment shader (228 G) runs about 1.7 times faster than the macOS compute kernel (about 133 G). A Linux compute version of the test would make a fairer comparison.

## Desktop benchmark (partial)

`glmark2-es2-wayland -s 1280x800` on the KDE desktop, test kernel, 2026-10-26 13:41. The run stopped early for a reboot.

| Scene | FPS |
|---|---|
| texture, nearest | 3562 |
| texture, linear | 3562 |
| texture, mipmap | 3486 |
| shading, gouraud | 3270 |
| shading, blinn-phong-inf | 3266 |

No GPU errors during the run. The full run (`tests/stress.sh`) needs a desktop login.

## Stability

| Date | Test | Result |
|---|---|---|
| 2026-10-26 13:06 | Readback test, 3 runs | 3 of 3 pass, 0 of 4096 pixels wrong |
| 2026-10-26 13:47 | Shader stress, 600 s (`tests/soak.sh`) | Pass, 0 wrong values |
| 2026-10-26 13:57 | Readback test, 20 runs | 20 of 20 pass |
| 2026-10-26 13:57 | Idle soak, 60 min, login screen on the GPU | Pass: readback 3/3 after the soak, 0 kernel GPU or display problems |
| 2026-10-26 | Load soak, 60 min (`tests/load-soak.sh`) | Pass: 228.17 G pixel-iterations/s for the full hour (no drop), 0 wrong values in 195,843 checks, 0 kernel GPU or display problems. End temperatures 26.7 / 45.3 / 53.3 C (thermal zones 0-2) |
| 2026-10-26 23:21 | Vulkan compute stress, 600 s (`tests/vk-stress.c`), desktop in use | Pass: 0 wrong values in 6,587 checks. One GPU fault in a desktop render job during the run (see below) |

### KWin crash on a GPU fault in another process (2026-10-27 08:52:39)

An invalid llama.cpp test tile made a llama-bench compute job write to unmapped GPU addresses. The kernel recovered, but `kwin_wayland`, a different process, crashed with SIGSEGV in the same second, and the desktop had to be restarted. So a GPU fault in one process can take down the compositor. Details and open questions: `docs/gpu-fault-2026-10-26.md`, "KWin crash on a fault in another process".

### GPU fault and plasmashell crash (2026-10-26 23:22)

During the `vk-stress` run, the desktop was in use (plasmashell, Firefox and other GPU clients). This is the only GPU fault in 8 boots with the GPU stack.

1. 23:22:53: a render job of plasmashell (context 18, TA and FS stages) read an unmapped GPU address (fault status `0x8492a48011`, unit `0x40`). The compute test was not the faulting job.
2. The kernel recovered the GPU correctly (halt, resume, new render allocators). It marked plasmashell's GPU context as lost (`EIO`).
3. 23:23:06: plasmashell drew its next frame and crashed (SIGSEGV) in Mesa: `st_Clear`, `agx_clear`, `agx_get_batch`, `agx_batch_init`. The gallium driver does not handle a lost context.

Two open bugs: the render-path fault itself (kernel or Mesa G15 render state; the trigger is probably heavy compute work at the same time as desktop rendering, not proven), and the Mesa crash after a context loss (it should report a reset). The kwin_wayland crash at 18:21 is a different case: the login-screen compositor, with no GPU fault in the kernel log.

## Vulkan compute and local LLMs (2026-10-26)

| Test | Result |
|---|---|
| `tests/vk-compute.c`, 50 dispatches over 16,777,216 values | Pass, 0 wrong values (native Mesa) |
| llama.cpp, Llama 3.2 3B Q4_K_M, GPU | pp512 303 tokens/s, tg128 13.5 tokens/s |
| llama.cpp, Llama 3.1 8B Q4_K_M, GPU | pp512 125 tokens/s, tg128 5.8 tokens/s |
| llama.cpp, Llama 3.1 8B Q4_K_M, CPU (6 threads) | pp512 67 tokens/s, tg128 6.6 tokens/s |
| GPU and CPU text for the same prompt | Same |
| After the memory floor fix (2026-10-26 20:43): 3B GPU / CPU | pp512 356 / 169, tg128 48.1 / 55.7 tokens/s |
| After the memory floor fix: 8B GPU / CPU | pp512 150 / 71, tg128 22.7 / 25.1 tokens/s |

Flash attention: the native compiler refused one instruction in the `flash_attn_f32_f16_aligned` shader, an f32 multiply with a half result (`fmul` f32 x f32 -> f16). Its short encodings hold only 8 of the 64 wait masks, and the shader needed a wider one. `patches/mesa-agx3-fmul-narrow-wait.patch` first runs the wait as its own instruction, as the compiler already does for the other short forms. With the patch, llama.cpp `test-backend-ops -o FLASH_ATTN_EXT` passes 5368 of 5368 tests on the GPU (11 cases are not supported by llama.cpp's Vulkan backend). With `-fa 1`, the speed is the same as with `-fa 0` (8B: 150 / 22.8 tokens/s), and the text is the same as the CPU text. Details and the full table: `ane-linux/docs/llm-baseline.md`.

Installed in `/opt/mesa-m3` (stage M, 2026-10-27 01:36). Rerun 2026-10-27 07:40, new boot, on the charger at 12 % battery, `llama-bench -p 512 -n 128 -r 3 -ngl 99`, tokens/s:

| Model | `-fa 0` pp512 / tg128 | `-fa 1` pp512 / tg128 |
|---|---|---|
| Llama 3.1 8B Q4_K_M | 149.98 / 22.79 | 150.13 / 22.69 |
| Llama 3.2 3B Q4_K_M | 357.11 / 47.97 | 357.65 / 47.60 |

0 GPU faults. Text check (40 tokens, greedy, 2 models x 2 prompts): the installed Mesa and the old Mesa build give the same text in 4 of 4 cases, and the GPU gives the same text as the CPU in 3 of 4. In the 4th case (8B, "The capital of France is") the GPU picks a different first word than the CPU with the old Mesa too, so it is GPU and CPU rounding, not the patch. Results on the M3: `~/llm-work/results/fa-20261027-0734`.

**G2 (2026-10-27).** Llama 3.1 8B Q4_0 (requantized): pp512 169.8, tg128 26.65 tokens/s; Q4_K_M: 150.2 / 22.75. Token generation reads 124 GB/s of weights (macOS on Llama 2 7B: 109 GB/s), so it is at parity per byte. Prompt processing is about 59 % of macOS: the matrix multiplies run at about 2.2 TFLOPS without cooperative matrix (macOS uses `simdgroup_matrix`, about 4.6 TFLOPS). Batch size, flash attention and tile choice change it by less than 2 %. Details and the work estimate: `ane-linux/docs/llm-baseline.md`, section G2.

**Select the native Vulkan driver outside the desktop.** The desktop session gets the native Mesa variables from the user environment generator. An SSH shell does not, so the Vulkan loader picks the distribution's Mesa. That driver writes an older compute format, and the kernel refuses every job (`G15: rejecting CDM record ... 00001212`, `submit failed ... EINVAL`). Benchmarks then report impossible speeds. Set this first:

```bash
export VK_DRIVER_FILES=/opt/mesa-agx/share/vulkan/icd.d/asahi_icd.aarch64.json
```


## Memory bandwidth (2026-10-26)

LLM token generation reads all weights once per token, so it depends on memory read speed. The GPU profile of Llama 3.1 8B (`GGML_VK_PERF_LOGGER=1`) shows 188 ms of GPU time per token, almost all in matrix-vector shaders at about 29 GB/s. Dispatch overhead is small (about 25 to 60 us per small operation, under 10% of the token time). The llama.cpp options `GGML_VK_FORCE_MMVQ`, `GGML_VK_DISABLE_FUSION`, `GGML_VK_MAX_NODES_PER_SUBMIT=1000` and `GGML_VK_PREFER_HOST_MEMORY` change nothing (6.3 to 6.4 tokens/s).

| Test | Result |
|---|---|
| GPU read, `tests/vk-bandwidth.c`, 512 MiB, 1 / 4 / 16 / 64 reads per thread | 25.4 / 29.7 / 30.8 / 31.1 GB/s |
| GPU read, cached or uncached memory type | 30.8 GB/s for both |
| CPU read, `tests/cpu-bw.c`, 1 / 6 / 12 threads | 29.3 / 32.6 / 32.4 GB/s |
| Published M3 Pro memory bandwidth | 150 GB/s |

Shared-limit test (`tests/mem-shared.sh`, 2026-10-26 18:22, no root, no register access). Mean values; when two readers run at the same time, the mean covers the overlap.

| Readers | Result |
|---|---|
| P cores alone (6 threads, up to 4.06 GHz) | 32.4 GB/s |
| E cores alone (6 threads, up to 2.75 GHz) | 29.8 GB/s |
| GPU alone | 31.1 GB/s |
| P cores and GPU at the same time | 19.0 + 17.8 = 36.8 GB/s in total |
| P cores and E cores at the same time | 21.2 + 16.2 = 37.4 GB/s in total |

Every reader alone reaches about 30 to 32 GB/s, and two readers together share about 37 GB/s. The slower E cores almost reach the same value as the P cores. So the limit is shared below the CPU clusters and the GPU (memory controller or fabric), and it does not depend on the CPU clock. This supports the low memory performance state cause. It does not prove it.

The CPU and the GPU both stop near 32 GB/s, so the limit is in the memory system, not in the GPU driver or the shaders. Probable cause: under Linux the memory controller or fabric stays in a low performance state. On this kernel the CPU clock driver binds the M3 clusters as `apple,t8112-cluster-cpufreq`, which sends no memory vote (`has_ps2 = false`). This is not proven yet.

Same machine in macOS 15.6.1 (offline, 2026-10-26 18:40, `tests/cpu-bw.c` built with pthreads, same binary hash for every run):

| CPU threads | macOS best / mean | Linux best / mean |
|---|---|---|
| 1 | 60.6 / 48.8 GB/s | 29.3 GB/s (best) |
| 6 | 89.3 / 80.9 GB/s | 32.6 / 32.4 GB/s |
| 12 | 115.3 / 110.4 GB/s | 32.5 / 32.2 GB/s |
| 6, background QoS (E cores) | 38.9 / 31.3 GB/s | 29.8 GB/s (E cores, mean) |

macOS reads 3.4 times faster with all cores, and 2 times faster with one thread. So the hardware is not the limit: Linux leaves the memory system in a slow state. In macOS one thread alone goes beyond the whole Linux limit. Device tree findings: `docs/memory-pmp-findings.md` (the PMP coprocessor sets memory and fabric speed; no Linux driver starts it). Research notes: `docs/memory-bandwidth-research.md` (no Linux driver casts a memory or fabric performance vote on T6030; the fork has one only for T8140).

### Fix: the PMP memory floor (2026-10-26, tested on the M3)

Cause, now proven: no Linux driver on this kernel requested a memory floor from the PMP. The SiliconForest fork has the request in `drivers/soc/apple/m3/pmp-display.c` (CPU-client PTD entries 288 and 289, DCS4 and FAB2). That file is only built with `CONFIG_SILICONFOREST_M3`, which this build turns off. `patches/t6030-pmp-memory-floor.patch` moves the same request into the maintained PMP report driver. The boot option `pmp_report.memory_floor=0` turns it off.

Kernel log on the test boot: `memory floor try 1: DVFS state 0x30200/0x30200 -> 0x32204/0x32204`. The PMP accepted the request on the first try.

`tests/mem-shared.sh` after the fix (2026-10-26 20:42 boot, mean values):

| Readers | Before | After |
|---|---|---|
| P cores alone (6 threads) | 32.4 GB/s | 123.5 GB/s (best 127.1) |
| E cores alone (6 threads) | 29.8 GB/s | 65.1 GB/s |
| All 12 cores | 32.2 GB/s | 109.7 GB/s |
| GPU alone | 31.1 GB/s | 130.1 GB/s (best 133.6) |
| P cores and GPU at the same time | 19.0 + 17.8 GB/s | 123.2 + 131.2 GB/s |
| P cores and E cores at the same time | 21.2 + 16.2 GB/s | 64.3 + 56.3 GB/s |

Rerun on 2026-10-27 with the four-chain `cpu-bw.c` (OpenMP build, sha256 3908a5b1...): P cores 126.0 / 125.1, E cores 64.9 / 64.6, all cores 113.2 / 110.8, GPU 133.7 / 129.9 GB/s (best / mean). Together: P cores 125.4 / 94.4 with GPU 133.4 / 127.0; P cores 65.0 / 61.9 with E cores 64.9 / 55.9. These match the first run, so the table above stays valid. With many threads, OpenMP gives each thread its own add chain, so the one-chain problem (see below) did not affect it.

The P cores now read more than macOS with 6 threads (89.3 GB/s best). The GPU reads 4.2 times faster than before. Llama 3.1 8B token generation goes from 5.8 to 22.7 tokens/s on the GPU, and from 6.6 to 25.1 on the CPU. GPU and CPU text still match. The kernel log has no GPU fault, firmware halt or refused submit.

Limits: the floor is fixed, not load-based, so idle power is higher than in macOS. The test measured one boot only.

### Linux after the fix and macOS, same CPU test (`tests/cpu-bw.c`)

| CPU threads | macOS 15.6.1, 2026-10-27 (5 runs, best / mean) | Linux with the memory floor, 2026-10-26 (best / mean) |
|---|---|---|
| 1 | 83.1 / 60.7 GB/s | 60.2 / 52.0 GB/s (P core, four-chain build; see below) |
| 6 | 125.1 / 121.0 GB/s | 127.1 / 126.4 GB/s (P cores, `taskset`) |
| 12 | 116.9 / 115.9 GB/s | 109.7 GB/s (mean) |
| GPU read, `vk-bandwidth` | no Metal version | 134.7 / 131.7 GB/s |

macOS binary sha256 e51a4d49... (pthreads build for macOS 14 and later). The 6-thread macOS value is higher than in the first macOS run (89.3 GB/s best on 2026-10-26). macOS places threads freely, so it can use E cores. With 6 threads on the P cores, Linux now matches macOS.

**One-thread result (2026-10-27).** A first Linux run gave 20 GB/s with one thread, 3 times slower than macOS. Most of that gap came from the test build, not from the memory system. The old sum loop had one add chain. gcc kept it as one dependent chain, so add latency limited it to about 20 GB/s. Apple clang (macOS build) splits the loop into several chains. The same source built with clang on Linux reads 43 to 56 GB/s. `tests/cpu-bw.c` now uses four chains, so both compilers measure memory.

| Linux build, one thread on a P core (cpu 7) | best / mean |
|---|---|
| gcc, old one-chain loop | 20.3 / 18.4 GB/s |
| clang, old loop | 43.3 / 34.8 GB/s |
| gcc, four chains (pthreads) | 60.2 / 52.0 GB/s |
| gcc, four chains (OpenMP) | 54.5 / 52.5 GB/s |
| gcc, four chains, one E core | 31.4 / 30.2 GB/s |

The remaining gap to macOS (60.7 GB/s mean) is about 15 %. A possible cause: with one memory-bound thread, the P core clock sometimes drops (samples from 0.7 to 4.06 GHz), but a compute loop holds 4.06 GHz. The `schedutil` governor and the Apple cpufreq driver choose that clock. Also, this kernel drives M3 clusters with the t8112 table, which does not set the PS2 field of the DVFS command. The driver sets PS2 only on M1 (t8103). What PS2 does on M3 is not known; no value is guessed. Governor test (2026-10-27, `tests/governor-bw-test.sh`, P core 7). The first run had a script error: it did not set `OMP_NUM_THREADS=1`, so 12 threads shared the one core. The result still shows that the clock does not limit memory reads on one core:

| Governor | 12 threads on P core 7, best / mean | Clock samples |
|---|---|---|
| schedutil | 83.8 / 82.5 GB/s | 17 of 40 at 1.36 GHz, 17 at 4.06 GHz |
| performance | 83.7 / 82.8 GB/s | 40 of 40 at 4.06 GHz |
| schedutil again | 83.4 / 82.5 GB/s | 18 of 40 at 4.06 GHz |

One P core reaches 83 GB/s, the same as the macOS one-thread best (83.1 GB/s). The memory system and the clock are not the limit. The one-thread gap comes from how one thread issues its reads, and the four-chain build already closes most of it (59.0 GB/s mean in the distro-pack run, 97 % of macOS). The script now sets `OMP_NUM_THREADS=1`; a true one-thread run under `performance` was not done.

### GPU compute against macOS: same shader type (`tests/vk-stress.c`)

`vk-stress` is the `metal-stress` kernel as a Vulkan compute shader (same math, 16x16 groups, wait on every 10th frame).

| Run | Frames/s | G pixel-iter/s | Wrong values |
|---|---|---|---|
| Linux, 10 s, desktop idle | 250.0 | 104.9 | 0 of 251 checks |
| Linux, 600 s, desktop in use | 109.8 (first 30 s: 201) | 46.0 | 0 of 6,587 checks |
| Linux, 600 s, desktop idle, no other GPU client (2026-10-27 00:35) | 113.2 (first 30 s: 233, then about 105) | 47.5 | 0 of 6,790 checks |
| macOS 15.6.1, Metal, steady 0 to 450 s | about 317 | about 133 | 0 of 14,831 checks |

The clean 600 s rerun shows the same drop after 30 s with no other GPU client, so the drop does not come from the desktop. A failed suspend try (suspend key at 00:38:59) during the rerun did not change the rate. Log on the M3: `~/vktest/vk-stress-600-clean.log` (30 s lines: 6990, 10160, 13320, 16530, 19690, 22850, 26250, 29420, 32710, 36330, 39520, 42680, 45840, 49000, 52160, 55320, 58490, 61650, 64810 frames; CPU check 27.96 ms per check).

**What limits this test (2026-10-27, `tests/gpu-perf-suite.sh`).** The GPU is not slower than in macOS. The test pattern is the limit:

| Run (Linux, `vk-stress`) | G pixel-iter/s | CPU check per 10 frames |
|---|---|---|
| No wait (`VK_STRESS_CHECK_EVERY=0`), 60 s | **255.5** | none |
| Wait and check every 100th frame, 60 s | 192.9 | 56.8 ms |
| Wait and check every 10th frame (as `metal-stress`), 30 to 60 s runs | 62 to 115 | 17 to 27 ms |
| `gles-stress` (fragment shader, same math), 60 s | 226.1 | about 1 ms per check |

- On each 10th frame the test empties the GPU queue and checks 21,904 values on the CPU. The GPU has no work during the check (17 to 27 ms), about half of the time.
- The GPU clock state (read each 0.2 s from the debugfs `asahi-g15/pstate` file) shows the effect. With no wait, the GPU stays at state 8 (1380 MHz) for the full run. With the wait on every 10th frame, the firmware DVFS often runs the GPU at states 1 to 3 (338 to 796 MHz). Then 10 GPU frames take about 33 ms instead of 16 ms.
- The driver gives the firmware the full Apple DVFS controller set from the device tree (`perf-tgt-utilization`, gains, filters, boost: `g15/board/record.rs`), the same values that macOS gets. No firmware word was changed.
- The CPU side changes the result too. On an E core the check takes 27 ms (62 G). The energy-aware scheduler can put the test there, because the process mostly waits for the GPU. On a P core: 20 ms (113 G). gcc and clang builds check equally fast (25.4 ms both). `performance` governor, `uclampset -m 1024` and `sched_energy_aware=0` gave 86, 84 and 91 G: a faster check, but lower GPU states. All settings were set back after the test.
- The same setup varies from 85 to 115 G between 30 s runs, because the DVFS state changes.

**Idle test boot (stage M, 2026-10-27 01:43).** Hypothesis: the GPU powers off 2.5 ms after its last job, so the DVFS starts low after each CPU check. One boot with `asahi.g15_idle_standby_us=100000` (GPU stays powered 100 ms) disproved it:

| Test (60 s) | Default (00:12) | Standby 100 ms (01:44) |
|---|---|---|
| Wait every 10th frame | 64.8 G | 64.9 G (P core, 30 s: 84.2 G) |
| Wait every 100th frame | 192.9 G | 189.2 G |
| No wait | 255.5 G | 263.4 G |
| `gles-stress` | 226.1 G | 247.0 G |
| GPU read | 133.6 GB/s | 133.8 GB/s |

The GPU still ran at state 1 (338 MHz) for most of the wait test. So the firmware DVFS chooses the low clock from the low utilization (the GPU is busy about half the time), not from power-off. The argument was removed again (no gain, more idle power). The higher no-wait and fragment values came with the new Mesa build (flash attention patch) on a fresh boot; one run each, not proven.

So the macOS figure of 133 G is a mixed CPU and GPU DVFS result, not a GPU limit. Linux reaches 255 G when the GPU is kept busy, which is 1.9 times the macOS figure for the check pattern. A fair GPU comparison needs the no-wait run in macOS too (`metal-stress` with no checks). That needs a macOS boot.

**G1: closing the stop-and-go gap (2026-10-27).**

a) CPU side (`tests/g1-cpu-side.sh 60`, 3 runs of 60 s each, macOS pattern, on the charger):

| CPU setting | G pixel-iter/s | CPU check per 10 frames |
|---|---|---|
| Default | 63.2 / 63.2 / 64.0 | 27.0 to 28.9 ms |
| `taskset -c 7` (P core) | 62.9 / 63.0 / 63.3 | 28.8 to 29.0 ms |
| `uclampset -m 1024 taskset -c 7` | **81.0 / 81.1 / 81.3** | **14.4 to 14.6 ms** |

Pinning alone does not help: `schedutil` keeps the P core slow because the thread mostly waits. `uclamp.min` 1024 halves the check time (+28 %). The GPU is then still busy only about 53 % of the time. The pstate sampler was not run (it needs root after 07:35).

b) Driver side. The DVFS controller words come from the G15S HardwareData template of the firmware build (the macOS configuration), not from this Mac's ADT (its `sgx` node has no `perf-*` controller properties). Decoded at HardwareDataA (+0x4580) with the G15C record offsets, confirmed by the fixed neighbours:

| Word | Value |
|---|---|
| `perf_tgt_utilization`, `_2` | 80 % |
| `perf_boost_min_util`, `perf_boost_ce_step` | 90, 50 |
| filter a / a2 | 0.2 / 0.005 |
| integral / proportional gain | 1.755 / 5.85 |
| base / max pstate (scaled) | 100 (state 1) / 800 (state 8) |

So the firmware aims for 80 % busy. At about 50 % busy it lowers the clock until the GPU is busy 80 % of the time, near state 1. The driver has no module parameter or debugfs knob for this and no minimum-pstate request. `patches/g15-perf-tgt-util.patch` adds `asahi.g15_perf_tgt_util` (30 to 95, 0 = unchanged); built (image sha256 3f032b51...), install script `install/stage-n-tgt-util.sh`, not tested yet (needs root and one boot).

c) macOS evidence: only the pattern number (133 G at about 317 frames/s, 31.5 ms per 10 frames). If the M3 GPU at the top clock needs 16.4 ms for 10 frames (Linux no-wait value), macOS spends about 15 ms per check and keeps the GPU near the top clock at about 52 % busy. With the same firmware words that would not happen, so macOS likely sends a performance hint with its work or uses other controller words. Not proven: a macOS run with `METAL_STRESS_CHECK_EVERY=0` and `powermetrics` GPU frequency would show it.

d) Test boot with `asahi.g15_perf_tgt_util=50` (2026-10-27 12:14, one-time boot, `install/window/gpu-boot.sh` and `gpu-check.sh`, output `~/gpu-perf/gpu-check-20261027-121452`): **GPU_CHECK_FAIL, no gain.** The driver logged `DVFS target utilization 50 % from the module parameter (template 80 %)`, so the firmware got the new words.

| Run | G pixel-iter/s | CPU check per 10 frames | GPU time per 10 frames | Against the top clock (16.3 ms) | GPU busy |
|---|---|---|---|---|---|
| Default, stage O (G1 a) | 63.2-64.0 | 27-29 ms | 38.3 ms | 2.35 x | 58 % |
| Default, target 50 | 64.00 | 26.97 ms | 38.6 ms | 2.36 x | 59 % |
| uclamp P core, stage O (G1 a) | 81.0-81.3 | 14.5 ms | 37.2 ms | 2.28 x | 72 % |
| uclamp P core, target 50 | 52.93 | 14.55 ms | 64.7 ms | 3.97 x | 82 % |
| No wait, target 50 | 257.20 (stage O 263.6) | none | 16.3 ms | 1.00 x | 100 % |

GPU time per 10 frames = 10 / frames per second minus the CPU check time; the top-clock value comes from the no-wait run. One run each.

- In every stop-and-go run the GPU is busy 58-82 % of the time, above both the 80 % template target (for the uclamp run) and the 50 % test target. A controller that aims at that busy share would raise the clock. It did not: the default run is the same to within 1 %, and the uclamp run became slower (3.97 times the top-clock time against 2.28).
- So the words at HardwareDataA +0x788/+0x7ec do not control this case, or the firmware measures busy time in a way that a 15-27 ms idle gap resets (for example a power-down between bursts, with a restart at a low state). The decode in b) is not wrong for the record layout, but this test shows the target is not the limit.
- The uclamp drop is one run on a fresh boot. It needs a repeat before it counts.
- The parameter stays in the kernel with default 0 (no change). Do not set it.

Next: measure, do not guess. Run the pstate sampler (root) during `VK_STRESS_CHECK_EVERY=10` on the normal boot, to see the clock state per burst and whether the GPU powers down in the CPU gaps. Only then choose the next controller word (the boost words at util 90/step 50, the filter a 0.2/0.005, or the idle power-down delay).

e) Clock probe (2026-10-27 12:50, normal boot, `tests/gpu-clock-probe.sh`, 2 ms `pstate` sampling from debugfs):

| Run | G pixel-iter/s | Fast bursts (state 8, about 17 ms) | Then |
|---|---|---|---|
| check 10, 60 s | 67.22 | first 19.97 s | every burst at state 1 (338 MHz, about 66 ms), power-off (state 0) between |
| check 10, uclamp P core, 60 s | 78.79 | first 19.99 s | same |
| no wait, 20 s | 263.60 | whole run | |
| check 10, 30 s, after idle gaps of about 3, 2, 10 and 30 s | 87.08, 88.71, 86.68, 87.31 | first 19.96-19.99 s each time | same |

- The firmware keeps the top clock for exactly 20 s of a new GPU client's work. Then its controller target steps 4, 3, 2 to 1 within about 300 ms, and every later burst runs at state 1, 4 times slower. A 2 s gap is enough to get a new 20 s window, so the window probably starts with a new client (context), not after a long idle.
- So the stop-and-go result depends on the run length: 30 s gives 87 G, 60 s gives 64-67 G. The macOS 133 G figure needs the same check: is macOS also fast only for 20 s, or does it stay fast?
- The template has no DVFS word that clearly encodes 20 s (value 20 only at 0xb20, 0xb54 and HardwareDataA +0xf7c, units not known). The 50 % target test did not change the state-1 phase.
- Next: find what starts the window (a new context, a new queue or a firmware message), and whether the driver can send it again. The firmware words to try in a test boot are the boost words (HardwareDataA +0x790 = 90 % minimum busy, +0x794 = step 50), or the base state (+0x7d8/+0x7e0 = 100, state 1).

f) What starts the 20 s window (2026-10-27 22:30, on battery, no root; `tests/vk-stress.c` with the new `VK_STRESS_REPORT_S` and `VK_STRESS_PAUSE`, check every 10 frames):

| Run | Frame rate per 2 s step |
|---|---|
| 50 s, 3 s pause at 28 s in the same process | 245-278 fps to 20 s, then 100-112 fps; after the pause 248-250 fps again to the end (20 s) |
| 28 s, 1 s pause at 22 s | slow before the pause, 248-250 fps after it |
| 28 s, 0.3 s pause at 22 s (started right after the run above) | slow already at 16 s; 100-122 fps after the pause |
| 28 s, 0.1 s pause at 22 s (started right after) | 100-118 fps the whole run |

- **The window is an idle reset, not a new client.** After the GPU has been idle for about 1 s, the firmware gives 20 s at the top clock, also inside the same process and GPU context. Gaps of 0.3 s or less do not reset it, and runs started back to back carry the slow state over (the earlier 4-run test had about 3 s between runs, so each got a new window).
- So the firmware restarts its performance controller after a deep idle (probably the GPU power-down), starts it at the top state and holds it for 20 s. After that, the controller follows its utilization target and goes down to state 1 at the busy share of this pattern. The 20 s does not show as one word in the template; it can be a count of controller samples.
- Effect: a load with a pause of 1 s or more at least every 20 s runs at full speed. A steady stop-and-go load (a CPU step between GPU steps, no long pauses) runs at state 1 after 20 s. The macOS 133 G figure must be checked against this: a macOS run of 60 s or more with `powermetrics` GPU frequency.
- **tgt_util=50: closed.** The 50 % target changed neither the 20 s window nor the state-1 phase (d above). The parameter stays in the kernel with default 0, and nobody should set it. To change the state-1 phase, the next firmware words to try are the boost words (A+0x790 minimum busy 90 %, A+0x794 step 50) or the base state (A+0x7d8, A+0x7e0, A+0x81c: 100, state 1). Each needs a module parameter like `g15_perf_tgt_util`, a kernel build, an install and a test boot.

**Q3_K models on the GPU (2026-10-27 22:50).** The installed Mesa could not build llama.cpp's `mul_mat_vec_q3_k_f32_f32` pipeline (`VK_ERROR_UNKNOWN`). Cause: the AGX3 packer refused `not x, x` (an in-place ALU op) that waits on two scoreboard slots (0x30 and 0x3), because its wait prelude only handled one slot. The AGX3B identity carrier has one wait field per slot, so `patches/mesa-agx3-inplace-multislot-wait.patch` retires the whole mask with one carrier. Built into `~/m3gpu/out/mesa-q3k-prefix` (not `/opt`): `test-backend-ops -o MUL_MAT` q3_K 48/48 (before: abort), q4_0 94/94, q4_K 96/96, q6_K 55/55, q2_K 55/55, 0 GPU faults. Installed into `/opt/mesa-m3` on 2026-10-28 00:29 (rebuilt in the stage M build folder with prefix `/opt/mesa-m3`, because the test prefix build holds its own path in every library; the folder belongs to the desktop user, so no root was needed; backup `~/m3gpu/backup/20261028-002921-pre-mesa-q3k`). Check against `/opt`: q3_K 48/48, q2_K 55/55, q4_0 94/94, q4_K 96/96, q6_K 55/55, 0 GPU faults. A full `-o MUL_MAT` run stops at `iq2_s` (`vk::CommandBuffer::end: ErrorFeatureNotPresent`). The old Mesa stops at the same point, so this is a separate, older problem (fixed in llama.cpp, see the next paragraph).

**iq2_s mat-vec on the GPU (2026-10-28 01:40).** A full `test-backend-ops -o MUL_MAT` stopped at iq2_s with `vk::CommandBuffer::end: ErrorFeatureNotPresent` and a core dump. Cause: the `mul_mat_vec_iq2_s` shader for 3 to 8 columns uses all 192 register halves and needs a spill frame of 8204 bytes. Honeykrisp admits 8192 bytes for compute (`hk_g17p_compute_shader_supported`), so `hk_dispatch_g17p_native` refuses the dispatch and `vkEndCommandBuffer` returns the error. 1 and 2 columns pass, and 9 or more columns use the matrix path. Fix (llama.cpp, not Mesa): `ane-linux/llm/llama-vk-honeykrisp-iq2s-matvec-cols.patch` limits the iq2_s mat-vec path to 2 columns on Honeykrisp; wider batches use the matrix path. The Mesa limit stays: the backing of the thread-private spill memory on G15 is not known, so a higher cap would be a guess. Result with `/opt/mesa-m3`, one type per run: all 23 types pass (iq2_s 49/49, every other iq type 49 to 64, f32 260, f16 334, bf16 215, q-types 48 to 96), 0 failures, no core dumps. The full run skipped no type after the fix.

### GPU suite (2026-10-27 00:12, `tests/gpu-perf-suite.sh 60`, desktop idle)

| Test | Result |
|---|---|
| Compute, no wait | 255.5 G pixel-iter/s |
| Fragment shader (`gles-stress`) | 226.1 G pixel-iter/s, 0 wrong |
| GPU memory read (`vk-bandwidth 512 20 16`) | best 133.6, mean 126.6 GB/s (specification 150 GB/s) |
| `glmark2-wayland`, 1920x1080 window | score 3192 |
| Kernel GPU faults | 0 |

### 7-Zip benchmark (`7z b`, 7-Zip 26.04, 2026-10-26 23:32)

| Threads | Compress (MIPS) | Decompress (MIPS) | Total rating (MIPS) |
|---|---|---|---|
| All (12) | 90,284 | 51,495 | 70,889 |
| 1 | 9,321 | 6,463 | 7,892 |

No macOS value on this Mac.

## Heat and fans under sustained load (2026-10-27)

`tests/heat-soak.sh` (with `tests/heat-sample.sh` and the safety stop `tests/heat-guard.sh`), stage O kernel, charger in, Plasma desktop up.

**Fans off (10:13, the baseline).** Before the fan fix, the fans never ran. Output `~/gpu-perf/heat-soak-20261027-101316` on the M3.

| Phase | Length | Throughput over the run | PMP CPU hotspot | SoC die max | Others max | Fans |
|---|---|---|---|---|---|---|
| GPU only: vk-stress, no wait | 600 s | 628-629 fps in every 30 s step (263.6 Gpix-iter/s): flat | 64 C at start, 80.8 C max, about 80 C steady, still rising slowly | 68.6 C | charger 48.9 C, Wi-Fi 54.0 C, battery 25.5 C | 0 / 0 rpm |
| CPU + GPU: 7-Zip benchmark, 12 threads, in a loop, plus vk-stress | 336 s (stopped by the guard) | 7-Zip 67.6k-73.3k per pass: flat; P cores 4034 MHz mean in the first quarter, 4038 MHz in the last | 95-100 C at the start of each 7-Zip pass (about every 8 s), about 77 C between; 61 of 164 samples at 90 C or more; 100.0 C at 10:31:52 | 66.1 C | charger 43.5 C, Wi-Fi 51.5 C | 0 / 0 rpm |

**Fans on (11:25).** The coordinator found the cause: the M3 SMC rejects the fan mode write until the key `Ftst` is set to 1. `patches/macsmc-hwmon-ftst-unlock.patch` (in the Documents copy of this repo) sets `Ftst`, and `m3-fancurve.service` (installed and enabled at 11:23) runs a fan curve. Same script, phases of 240 s. Full data: `docs/features/fans-heat.md` in the Documents copy (commit 75a6054).

| Phase | Length | Throughput | PMP CPU hotspot max | SoC die max | Fans max |
|---|---|---|---|---|---|
| GPU only | 240 s | vk-stress 263.60 G (628.5 fps; fans off: 263.6 G) | 72.8 C (fans off: 80.8 C) | 61.6 C | 1616 rpm |
| CPU + GPU | 240 s | vk-stress 263.26 G; 7-Zip 69,563 mean; P cores 4,030 MHz mean | 93.8 C, never 95 C (fans off: 100 C, guard stop) | 61.4 C | 4028 rpm |

- **No throttling seen**, with or without fans. Fans off: the GPU rate did not drop in 10 min, the P cores stayed at 4056 MHz even at the 100 C sample, and the kernel logged no thermal lines. A 35 s check run gave 627 fps for the GPU with the CPU load, the same as without it.
- **The guard did not stop the fans-on run.** With the fans, an all-core CPU load plus the GPU stays below 95 C in 240 s. Without them, it reached 100 C in under 6 min.
- **Fan keys:** the device tree names the SMC keys `F0Ac`/`F1Ac` (actual), `F0Tg`/`F1Tg` (target), `F0Mn`/`F0Mx` (min/max) and `F0Md` (mode). Fan 1 reads min 1350 and max 5349 rpm, Fan 2 min 1458 and max 5777 rpm. In SMC automatic mode the SMC kept its own target at 0 with a 100 C hotspot.
- **macOS reference:** Notebookcheck measured up to 2,400 rpm and 31.1 dB(A) after 30 min of Cinebench R23.
- **Keep the fans working:** every M3 kernel build must carry `macsmc-hwmon-ftst-unlock.patch`. The patched module is in `/lib/modules/7.2.11-m3gpu+/updates/`, so a new kernel version does not get it. Keep `tests/heat-guard.sh` on for long loads.

## Planned: how far each part of the chip goes

The goal is the limit of each block on Linux, and the same numbers on macOS on the same Mac.

| Block | Linux test | macOS test | What it shows |
|---|---|---|---|
| GPU integer and float ALU | `gles-stress`, a float variant | `metal-stress.swift`, a float variant | Shader throughput against the estimate above |
| GPU memory bandwidth | a copy shader on a large buffer | the same in Metal | Bandwidth against the M3 Pro's 150 GB/s specification |
| GPU sustained clock and heat | `load-soak.sh` with thermal readings | `powermetrics` during the Metal run | Throttling under long load |
| GPU 3D | `glmark2`, `vkmark` | GFXBench or a Metal scene | Real-scene frame rates |
| CPU (6 P-cores + 6 E-cores) | `stress-ng`, `7z b`, kernel build time | the same tools from Homebrew | Per-core and all-core speed, P and E cores |
| Memory | `mbw`, STREAM | STREAM | Bandwidth and latency |
| Storage | `fio` | `fio` | SSD read and write |

Rules for a fair comparison: same tool and settings on both systems, machine on power, lid open, fans free, three runs, report the median.
