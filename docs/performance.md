# Performance and stability

Measurements on the MacBook Pro 16-inch M3 Pro (Mac15,7, 12-core CPU, 18-core GPU, chip revision B1), unless a row says otherwise.

## GPU shader throughput: same math on each system

`tests/gles-stress.c` (Linux, GLES fragment shader) and `tests/metal-stress.swift` (macOS, Metal compute kernel) run the same integer work: each pixel of a 1024x1024 target runs 400 xorshift steps with a new seed per frame. Every 10th frame is read back and compared with the same math on the CPU, so a wrong result shows at once. The unit is billion pixel-iterations per second (G pixel-iter/s).

| Date | GPU | System, driver | Run | Frames/s | G pixel-iter/s | Wrong values |
|---|---|---|---|---|---|---|
| 2026-10-26 | M3 Pro, 18 cores | Fedora, kernel 7.2.11-m3gpu+, SiliconForest Mesa 26.3.0-devel | 600 s | 543.7 | 228.0 | 0 of 32,621 checks |
| 2026-10-26 | M5, 10 cores (host Mac) | macOS 26, Metal | 20 s | 242.3 | 101.6 | 0 of 485 checks |
| planned | M3 Pro, 18 cores | macOS 15.6.1 on the same M3, Metal | 600 s | | | |

Notes:
- Per GPU core: M3 Pro on Linux about 12.7, M5 on macOS about 10.2 G pixel-iter/s.
- Estimate of the hardware limit (not measured): 18 cores x 128 ALUs x 1.38 GHz (top GPU state in the kernel log) is about 3.2 trillion integer operations per second. One step is about 7 operations, so about 450 G steps per second. Linux reaches about 50% of that, and the CPU checks stop the GPU every 10 frames. The 128 ALUs per core is the commonly reported figure, not an Apple specification.
- Fragment shader (Linux) and compute kernel (macOS) are not identical paths. The macOS run on the M3 gives the fair comparison.

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

Flash attention must be off (`-fa 0`): the native compiler refuses one instruction in that shader. Details and the full table: `ane-linux/docs/llm-baseline.md`.

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

The P cores now read more than macOS with 6 threads (89.3 GB/s best). The GPU reads 4.2 times faster than before. Llama 3.1 8B token generation goes from 5.8 to 22.7 tokens/s on the GPU, and from 6.6 to 25.1 on the CPU. GPU and CPU text still match. The kernel log has no GPU fault, firmware halt or refused submit.

Limits: the floor is fixed, not load-based, so idle power is higher than in macOS. The test measured one boot only.

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
