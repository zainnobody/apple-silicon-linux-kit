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

Flash attention: the native compiler refused one instruction in the `flash_attn_f32_f16_aligned` shader, an f32 multiply with a half result (`fmul` f32 x f32 -> f16). Its short encodings hold only 8 of the 64 wait masks, and the shader needed a wider one. `patches/mesa-agx3-fmul-narrow-wait.patch` first runs the wait as its own instruction, as the compiler already does for the other short forms. With the patch, llama.cpp `test-backend-ops -o FLASH_ATTN_EXT` passes 5368 of 5368 tests on the GPU (11 cases are not supported by llama.cpp's Vulkan backend). With `-fa 1`, the speed is the same as with `-fa 0` (8B: 150 / 22.8 tokens/s), and the text is the same as the CPU text. The patch is in the Mesa build folder only, not yet in `/opt/mesa-m3`, so use `-fa 0` until it is installed. Details and the full table: `ane-linux/docs/llm-baseline.md`.

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
