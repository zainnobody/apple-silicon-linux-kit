# Apple REA: Plan

Plan date: 2026-10-26. Status: plan only. No code exists yet.

Goal: a private reverse engineering toolkit for Apple Silicon hardware. AI agents (Claude Code) use it through MCP. First use: M3 Pro GPU, display (DCP) and Neural Engine work for a private Linux build. It must also work on other targets (M1, M2, other Macs).

## 0. Verified M3 Pro state (from the install session, 2026-10-26)

Source: `asahi-m3-findings.md` in the shared session notes folder.

- Machine: MacBook Pro 16-inch, Mac15,7, j516sap, T6030.
- Dual boot: macOS 15.6.1 (24G90) and Fedora Asahi Remix 44 KDE. Kernel 7.1.13-402.asahi.fc44 (16K pages).
- Default boot is Fedora. Hold the power button at boot to pick macOS.
- Fedora access: Tailscale SSH (`user@<m3-tailscale-ip>`). sudo needs the user's password.
- macOS access: `ssh m3` over the USB-C cable link (host en13 to M3 en4). Works only in macOS.
- **User rule: macOS stays offline.** No Wi-Fi and no Ethernet.

Gaps confirmed on the real machine:

| Gap | Observed |
|---|---|
| GPU | Only simpledrm. No AGX driver, no render node. Software rendering. |
| Speakers | No speaker sink in PipeWire. speakersafetyd runs and 6 tas2764 amps are found. Not enabled for j516. |
| Brightness | No `/sys/class/backlight`. No DCP driver. |
| Sleep | Only s2idle offered. Not tested. |
| HDMI | Disabled. |

Works: 12 CPUs, camera, mic array, headset mic, headphone jack, Wi-Fi, Bluetooth, battery, keyboard, trackpad, lid switch, keyboard backlight, KVM.

Effects on this plan:

- Phase 1 runs on the offline macOS. Any Metal compiler or Xcode tools must be copied in from the host. A second option is Metal's runtime compiler, which is built into macOS. Which tools are already on the M3 is not checked.
- Phase 4: the host already has a USB-C link to the M3. The m1n1 proxy uses USB in a different mode, so this link is not proof that the proxy setup works.
- Speakers stay out of scope. The amps exist, and wrong settings can damage them.

## 0b. GPU track: port existing community M3 GPU work first (added 2026-10-26)

### New finding

A community kernel already has M3 and M3 Pro GPU work. We should test it before we write our own driver.

| Project | What it is | State (checked 2026-10-26) |
|---|---|---|
| [omacom/linux-aurora](https://github.com/omacom/linux-aurora) branch `integration/aurora` | Kernel tree with `drm/asahi` G15 (M3) GPU work, T6030 (M3 Pro) GPU fixes, T6030 panel backlight | Very active. Several contributors. GPU commits on 2026-10-24 to 2026-10-26. 29 stars. |
| [iconidentify/siliconforest](https://github.com/iconidentify/siliconforest) | Kernel, Mesa and m1n1 built from linux-aurora, packaged for Omarchy (Arch) | Claims "M3 Pro 16-inch J516S with 14.7" is qualified: hardware OpenGL and Vulkan pixel readback, panel brightness, Quake at 1920x1080, zero GPU faults. Report dated 2026-10-19. 0 stars. Claims not verified by us. |
| [iconidentify/siliconforest-mesa](https://github.com/iconidentify/siliconforest-mesa) | Mesa with M3 GPU changes | Qualified commit `7515336b`. |

Not affiliated with Asahi. The SiliconForest m1n1 notes an "owner-authorized AI policy", so AI tools were likely used.

### Our M3 matches their tested setup

Read over SSH on 2026-10-26 (read only):

| Item | Our M3 | SiliconForest qualified pair |
|---|---|---|
| Board | `apple,j516s`, `apple,t6030` | J516S |
| OS firmware (stub) | 14.7 | 14.7 |
| System firmware | 15.6 | Not stated |
| Kernel | 7.1.13-402.asahi.fc44 (16K pages) | 7.2.11 siliconforest `0e1f4666` |
| GPU device tree node | None | Added by their kernel and m1n1 |
| `asahi.ko` | Present, not bound (no GPU node) | Bound |
| Mesa | Fedora 26.2.5 | siliconforest-mesa `7515336b` |

### Approach

1. **Review the sources.** Diff linux-aurora, siliconforest-m1n1 and siliconforest-mesa against Asahi. This is third-party kernel code with full system access, so read it before it runs.
2. **Build on the M3 itself, in Fedora.** Build the kernel as an extra kernel next to the Fedora kernel. Build Mesa into a separate folder (`/opt/mesa-m3`), so Fedora's Mesa stays in place.
3. **Back up the boot files.** Save `/boot/efi/m1n1/boot.bin` and the device tree files before any change.
4. **Install the m1n1 and kernel.** The Fedora kernel stays in GRUB as a fallback.
5. **Test.** Check that the GPU device appears, then run OpenGL and Vulkan tests with the new Mesa only.
6. **Roll back if needed.** Pick the old kernel in GRUB. If m1n1 fails, boot macOS (hold power), mount the EFI partition and restore `boot.bin`.

Needs from the user: the Fedora sudo password for package installs and the boot changes. We do not use the SiliconForest `curl | bash` installer. It targets Omarchy, not Fedora.

## 1. Key decision: separate tool, modelled on REA

**Decision:** build a separate Python MCP server. Do not fork REA.

Reasons:

- REA is TypeScript with strict checks and a maintainer scope rule for new providers. A fork would slow us down.
- The Apple tools we need are Python: applegpu (GPU ISA) and the m1n1 proxyclient (hardware tracing).
- REA's design is still a good model. Its GPU and model readers show the pattern: one provider per format, structured evidence output.
- Claude Code can use REA and our server at the same time. REA handles normal Mach-O and Arm64 code. Our server handles Apple-only formats.

Working name: `apple-rea`. Change it if you want.

## 2. What exists today (checked 2026-10-26)

| Piece | Where | Notes |
|---|---|---|
| REA GPU readers | `morluto/rea` `src/gpu/` | AMD and CUDA only (`AmdGpuTarget.ts`, `CudaFatbinary.ts`, `PtxKernels.ts`). No Apple GPU reader. MIT. |
| REA model readers | `morluto/rea` `src/model/` | GGUF and safetensors only. No CoreML or ANE reader. |
| m1n1 hypervisor tracers | `AsahiLinux/m1n1` `proxyclient/hv/` | `trace_agx.py`, `trace_dcp.py`, `trace_dptx.py`, `trace_mesa.py`, `trace_prores.py`, `trace_isp.py`, and more. No ANE tracer. GPL-2.0 since m1n1 2.0.0. |
| m1n1 trace decoders | `AsahiLinux/m1n1` `proxyclient/m1n1/trace/` | `agx.py`, `asc.py`, `dart.py`, `isp.py`, and others. |
| G13 (M1) GPU ISA | `dougallj/applegpu` | Docs, disassembler, assembler, emulator. G13 only. BSD-3-Clause. |
| M3 GPU method | XDC 2026 slides (29 Sep 2026) | `wrap.c` shim, Metal binary archive inspection, `compiler_explorer.py`, `hwtestbed.py`. Public release of these tools is not confirmed. |
| Neural Engine driver | `eiln/ane` | Kernel module, libane, Python bindings. Chip support not stated. MIT. |

## 3. Architecture

```
Claude Code
  |-- REA (existing, for normal Arm64 / Mach-O code)
  `-- apple-rea (new MCP server, Python)
        |-- corpus      : build shader and model test sets on macOS
        |-- metallib    : read Metal libraries and binary archives, extract GPU code
        |-- agx         : disassemble GPU code (G13 via applegpu, G15 new)
        |-- isa_lab     : diff tools to find instruction encodings
        |-- hwtest      : run test code on real hardware through m1n1
        |-- traces      : parse and diff m1n1 trace logs (AGX, DCP, others)
        |-- ane         : read compiled Neural Engine models
        `-- evidence    : store every result with inputs, hashes and dates
```

Rules for the design:

- Each module is a provider with one job, like REA.
- Every tool returns structured evidence: input hash, tool version, date, output.
- m1n1 code is GPL. We call it as a separate process. We do not import it, so our code keeps its own license.
- Nothing writes to the M3 Pro disk. Hardware tests run through the m1n1 proxy only.

## 4. Inputs: what we analyse

Low legal risk first:

1. **Shaders we write.** We compile our own Metal shaders on macOS and read the GPU code that Apple's compiler produces. This is the main method for the GPU ISA.
2. **Hardware traces.** m1n1 records what macOS sends to the hardware. We read register and message traffic, not Apple code.
3. **Models we compile.** We compile our own CoreML models and read the Neural Engine output.

Higher risk, use only if needed and keep private:

4. **Apple binaries** (kexts, firmware, Metal driver). REA with Ghidra can read these. Apple's licence forbids this except where law allows it. This is not legal advice.

## 5. Phases

Each phase has a clear "done when" test.

### Phase 0: Setup (1 to 2 days)

- Create a private Git repo with the Python package and the MCP server skeleton.
- Register the server in Claude Code.
- Check the Asahi team's public repos for M3 GPU tools first, so we do not duplicate work.
- **Done when:** Claude Code lists the `apple-rea` tools and a test tool returns evidence.

### Phase 1: Shader corpus builder (macOS)

- Generate many small Metal shaders. Each shader changes one thing (one operation, one register, one constant).
- Compile them with Apple's tools and save source, compiled library and GPU code side by side.
- **Done when:** the corpus holds at least 500 shader pairs for the M3 Pro (G15), with a manifest.

### Phase 2: G13 baseline (tests the toolkit on known ground)

- Wrap applegpu as the G13 disassembler.
- Run the full pipeline on M1 shaders, where the answers are known.
- **Done when:** our pipeline output matches applegpu on every corpus shader. This needs an M1 Mac or M1 shader binaries.

### Phase 3: G15 instruction set lab (the main work)

- Diff tools: compare two compiled shaders and show which bits changed.
- Encoding table: record each guess (field, bit position, meaning) with the shaders that prove it.
- Instruction length finder: M3 instructions have variable length, so first find where each instruction starts and ends.
- AI agents propose guesses. Tests confirm or reject each guess.
- **Done when (milestone A):** the decoder splits 95% of corpus code into instructions with correct lengths.
- **Done when (milestone B):** the decoder names the operation for 80% of corpus instructions.

### Phase 4: Hardware test bench (M3 Pro)

- Use m1n1 on the M3 Pro, controlled from a second computer over USB.
- Assemble test code with our decoder and run it on the GPU. Compare results with the expected values.
- **Done when:** a hand-written compute test runs on the M3 Pro GPU and returns the expected result.

### Phase 5: Trace tools (DCP and AGX)

- Parse m1n1 `trace_dcp.py` and `trace_agx.py` logs into structured events.
- Diff two runs (for example, brightness 50% against 60%) to find the changed messages.
- **Done when:** a brightness change in macOS shows as a clear message diff. This also feeds the display work (sleep, HDMI, brightness).

### Phase 6: Neural Engine reader

- Compile small CoreML models on macOS and read the Neural Engine output.
- Test eiln/ane on M1 or M2 first if available, then check M3.
- **Done when:** the reader lists the layers and sizes of a small compiled model.

## 6. Testing on other targets

The tool must not be M3-only. Test plan:

| Target | What it proves |
|---|---|
| M1 Mac (G13) | Ground truth. applegpu already decodes G13, so our output must match. |
| M2 Mac (G14) | Checks that the diff tools find known small changes between generations. |
| M3 Pro (G15) | The real research target. |
| M4 Mac | The XDC slides say the M4 ISA "seems (largely?) unchanged" from M3. A good second check. |
| Non-Apple CUDA/AMD code | Use REA as is. Not a target for apple-rea. |

## 7. Hardware and software needed

- The M3 Pro (Mac15,7) with macOS kept in the dual boot.
- A second computer (Mac or Linux) to run the m1n1 proxy.
- A USB-C to USB-A cable, USB-C end on the M3 Pro.
- Xcode command line tools on macOS for Metal and CoreML compiling.
- Optional: an M1 or M2 Mac for ground truth tests.

## 8. Risks

| Risk | Control |
|---|---|
| GPU tests hang the M3 Pro | Run tests through m1n1 only. Reboot to macOS if needed. Data on disk is not touched. |
| Speaker damage | Never touch audio in this project. |
| Asahi publishes the same tools | Check their repos at the start of each phase. Reuse their work. |
| Legal risk from Apple binaries | Prefer our own shaders, models and hardware traces. Keep the repo private. |
| Too slow to reach a working GPU driver | The toolkit still has value for the display work and for research. Set milestones, not a driver deadline. |

## 9. Open questions for the user

1. Do you have an M1, M2 or M4 Mac for ground truth tests?
2. Is this host (the Mac with the USB-C link to the M3) the m1n1 host? It looks like the best choice.
3. Where should the private repo live (GitHub private repo, or local only)?
4. May we copy Apple's Metal tools (from Xcode on the host) to the offline macOS on the M3?
