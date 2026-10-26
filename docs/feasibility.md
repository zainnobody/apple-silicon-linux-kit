# Can We Help Finish M3 Pro Support? (REA and AI tools)

Research date: 2026-10-26. Question: can REA or other AI tools help code the missing M3 Pro features in Asahi Linux?

## Short answer

- **Upstream with AI: no.** Asahi forbids generative AI for material contributions. Asahi would reject or ban AI-derived work.
- **REA for the GPU: no.** REA's core feature is decompilation with Hopper, Ghidra or IDA. Asahi forbids decompiling Apple's userspace graphics driver binaries.
- **By hand, without AI: possible, but hard.** It needs an M3 Pro, kernel and Mesa skills, and months of work. The best route is to join the Asahi team and follow their rules.
- **Easiest real help now:** test on your Mac15,7, report results, and donate.

## 1. What REA is

| Fact | Detail | Source | Date |
|---|---|---|---|
| Purpose | An MCP server and CLI that connects coding agents to reverse engineering tools. | [morluto/rea README](https://github.com/morluto/rea) | Read 2026-10-26 |
| Engines | Hopper, Ghidra or IDA for native binaries. objdump and Rizin also work. | [morluto/rea README](https://github.com/morluto/rea) | Read 2026-10-26 |
| GPU targets | CUDA and HIP code objects only. No Apple GPU (AGX) target is listed. | [morluto/rea README](https://github.com/morluto/rea) | Read 2026-10-26 |
| Hosts | macOS 12 and later is listed. Apple Silicon (arm64) is not stated. | [capitalandcompute.net](https://capitalandcompute.net/blog/what-is-rea-reverse-engineer-anything/) | 10 Oct 2026 |
| Safety warning | A fake trojan copy exists. Install only from the official repo or npm package (`rea-agents`). | [pasqualepillitteri.it fact check](https://pasqualepillitteri.it/en/news/23845/rea-reverse-engineer-anything-github-true-false) | Oct 2026 |

## 2. Asahi rules that block AI and decompilation

| Rule | Exact wording | Source |
|---|---|---|
| AI ban | "we broadly forbid the use of generative AI tooling for material contributions to Asahi Linux." | [Generative AI policy](https://asahilinux.org/llm-policy/) |
| Agentic tools | LLM legal risk "is amplified with 'agentic' approaches." | [Generative AI policy](https://asahilinux.org/llm-policy/) |
| Penalty | Using an LLM to interpret an m1n1 trace gets "a first and final warning." Concealed extensive use leads to an immediate ban. | [Generative AI policy](https://asahilinux.org/llm-policy/) |
| GPU binaries | Contributors "must not disassemble or decompile userspace graphics driver binaries." | [Copyright and Reverse Engineering policy](https://asahilinux.org/copyright/) |
| Clean room | "we do not currently allow contributions of code developed concurrently with binary reverse engineering." | [Copyright and Reverse Engineering policy](https://asahilinux.org/copyright/) |
| GPU contributors | "We require that all GPU contributors be known to the Board by real name." | [Copyright and Reverse Engineering policy](https://asahilinux.org/copyright/) |
| Leaks | Asahi "absolutely forbids" any non-public copyrighted material. | [Copyright and Reverse Engineering policy](https://asahilinux.org/copyright/) |

Neither policy page shows a date. Both pages were read on 2026-10-26.

## 3. What the missing parts need, technically

### GPU (largest gap)

- The M3 GPU (G15) has a new instruction set. Instructions have variable length and use a complex compression scheme.
- Registers are allocated dynamically. The memory address space grows from 39 to 43 bits.
- Status at XDC 2026 (29 Sep 2026): compute shaders run on M3. The shader compiler is WIP. The userspace graphics driver is "TODO." The kernel driver is WIP and shows GPU timeouts.
- Timeline: "coming soon™." No date.
- Team: Anna Maniscalco (Valve), Alyssa Milburn, Evan Tang (CodeWeavers).
- The team uses its own tools: a shim between userspace and kernel, Metal binary archive inspection, and m1n1 tracing.
- Sources: [XDC 2026 talk page](https://indico.freedesktop.org/event/12/contributions/532/), [talk slides](https://indico.freedesktop.org/event/12/contributions/532/attachments/389/557/slides.html).

### Display (DCP), which also blocks sleep and HDMI

- M3 cannot run macOS 13.5. The current Linux display driver targets that firmware interface.
- Apple changed the DCP firmware API in macOS 14. The communication protocol stayed the same.
- Asahi says it can trace the new API "with minimal changes" to its existing tools.
- The driver is being rewritten in Rust to handle firmware versions better.
- Source: [Progress report 6.19](https://asahilinux.org/2026/02/progress-report-6-19/), 18 Feb 2026.
- This looks like the most approachable M3 gap for a new human contributor. It still needs the m1n1 setup and kernel skills.

### Other release blockers named by Asahi

- M3 support in `speakersafetyd` (speaker protection) was release-blocking in Feb 2026.
- Source: [Progress report 6.19](https://asahilinux.org/2026/02/progress-report-6-19/), 18 Feb 2026.

## 4. Community work outside Asahi

- One community repo exists: [gallantcrusader/asahi-m3pro-fullstack](https://github.com/gallantcrusader/asahi-m3pro-fullstack), a fork of Moriz82/asahi-m3pro-fullstack.
- It targets Mac15,6 (14-inch M3 Pro). It does not target Mac15,7.
- It calls itself "experimental bring-up, not daily-driver support." It shows no GPU acceleration and no working display.
- Its native test install was retired on 2026-09-26. It has 0 stars.
- It is behind official Asahi M3 support. It is not a better path.
- This corrects the first report, which said no community patches were found.

## 5. Can you do it yourself?

| Path | Possible? | Why |
|---|---|---|
| Use REA or an AI agent and send code to Asahi | No | AI ban and penalties. GPU decompilation is forbidden. |
| Use REA privately in your own fork | Technically yes, but not useful | The work cannot be upstreamed. It carries legal risk (this is not legal advice). REA has no Apple GPU target. |
| Write code by hand and join Asahi | Yes, slowly | Needs an M3 Pro, kernel, Rust or Mesa skills, and the m1n1 tools. GPU work also needs a real name known to the Board. |
| Test, report bugs and donate | Yes, now | Needs no special skills. The project lacks M3 testers and funds. |

## 6. Private build for personal use (no upstream)

The Asahi AI rules apply only to work sent to Asahi. A private repo for personal use does not have to follow them.

### Legal (not legal advice)

- Apple's licenses forbid decompiling and reverse engineering. They make an exception where the law does not allow that restriction. ([Apple SLA example](https://www.apple.com/legal/sla/docs/macOSServer57.pdf))
- Some countries allow decompiling for interoperability. I did not check the law in your country.
- Watching hardware behaviour (tracing) is lower risk than decompiling Apple code.
- Keep the repo private. A public repo with code derived from Apple binaries is distribution and carries copyright risk.

### Feasibility per gap (solo, with AI help)

| Gap | Solo feasibility | Why |
|---|---|---|
| Display (DCP): sleep, HDMI, brightness | Best target. Months of work. | The protocol is unchanged. Only the macOS 14 API changed. Asahi tracing tools exist. Asahi is also doing this work, so it may land first. |
| External display (DP Alt Mode) | Use existing code | Asahi's public "fairydust" branch has experimental DP Alt Mode. You can build it privately. |
| ProMotion (120 Hz, VRR) | After DCP | Depends on the DCP work. |
| Speakers | Do not touch | Wrong speaker settings can damage the speakers. An Asahi developer damaged an M2 MacBook Air speaker while testing. Use Asahi's speakersafetyd only. ([Phoronix](https://www.phoronix.com/news/Apple-Mac-Speaker-Headset-Linux)) |
| GPU 3D | Very unlikely solo | A team with Valve and CodeWeavers members has run compute since March 2026. Graphics is still "TODO." REA lists no Apple GPU target. |
| Touch ID, ProRes, Neural Engine | Not realistic | No public work exists. Large unknowns. |

### What a solo setup needs

- A second computer (Mac or Linux) as the host. ([m1n1 user guide](https://asahilinux.org/docs/sw/m1n1-user-guide/))
- A USB-C to USB-A cable, with the USB-C end on the M3 Pro.
- The m1n1 hypervisor to run macOS and trace hardware access.
- Kernel build skills (C and Rust).
- macOS kept in the dual boot as a fallback.

## 7. An "REA for Apple" and priorities

### What an Apple version of REA needs

- REA does no disassembly itself. It drives Hopper, Ghidra, IDA, objdump or Rizin. ([REA README](https://github.com/morluto/rea))
- No public tool decodes the M3 GPU instruction set (G15). A disassembler for it is the core missing piece.
- Writing that disassembler is the GPU reverse engineering work itself. The REA wrapper is the easy part.
- No Ghidra processor module for Apple GPUs was found. Ghidra modules are written in SLEIGH.
- REA's README shows no plugin system. Its CONTRIBUTING.md and architecture map were not read.

### Starting points that exist

| Area | Project | Covers | License | Source |
|---|---|---|---|---|
| GPU ISA | dougallj/applegpu: docs, disassembler, assembler, emulator | G13 (M1) only | BSD-3-Clause | [repo](https://github.com/dougallj/applegpu) |
| GPU, M3 | Asahi team tools: `compiler_explorer.py`, `hwtestbed.py`, `wrap.c` shim | M3 compute shaders | Not checked | [XDC 2026 slides](https://indico.freedesktop.org/event/12/contributions/532/attachments/389/557/slides.html) |
| Neural Engine | eiln/ane: kernel module, libane, Python bindings | Chips not stated | MIT | [repo](https://github.com/eiln/ane) |

### Priority ranking (value against effort)

| Rank | Item | Daily value | Solo effort | Note |
|---|---|---|---|---|
| 1 | Display (DCP): sleep, HDMI, brightness, 120 Hz | High | Medium | Sleep gives battery life. The protocol is unchanged. |
| 2 | GPU 3D | High | Very high | Needs a G15 disassembler, a Mesa compiler, and a kernel driver. Follow the Asahi team's code. |
| 3 | Neural Engine | Low for most users | Medium to high | Only ML workloads use it. A base driver exists, but M3 support is not stated. Linux apps do not use the ANE by default. |
| 4 | Touch ID, ProRes | Low | Very high | No public base exists. |

## 8. Recommended next steps

1. Install Asahi on the Mac15,7 (the install session already does this).
2. Test each feature in the gap list. Record results with the kernel version.
3. Join `#asahi-dev` (named on the [Help Wanted page](https://asahilinux.org/docs/project/help-wanted/)). Ask where M3 test results help most.
4. Donate on [OpenCollective](https://opencollective.com/asahilinux) if you want to fund the work.
5. To learn kernel work, start with a Help Wanted task. Those tasks are small and not M3-specific.
6. Do not use REA or AI tools on Asahi work.
