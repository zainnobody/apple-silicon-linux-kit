# Asahi Linux on MacBook Pro M3 Pro (Mac15,7): Status Report

Research date: 2026-10-26. Research only. No files on the Mac were changed and the M3 Mac was not contacted.

## Summary

- Asahi Linux officially supports M3, M3 Pro and M3 Max Macs since 6 September 2026. The Mac Studio M3 Ultra is excluded.
- Installation is still gated behind the installer's Expert mode (`EXPERT=1`), per The Register, 7 September 2026.
- The main gaps are the GPU (no performant 3D), sleep (no suspend), and HDMI (disabled on MacBooks). All three trace to missing display coprocessor (DCP) support, except the GPU.
- No older Asahi release, kernel branch or M2 path gives better M3 Pro support. No separate community patch set was found.

## Feature table

Status words follow the Asahi docs: "linux-asahi" means mostly stable and usable. "WIP" means active work, not ready for broad use. "TBA" means no active work.

| Feature | Status (M3 Pro) | Source | Date |
|---|---|---|---|
| GPU 3D (OpenGL/Vulkan) | Not performant or power efficient. Docs say TBA for M3 Pro. Articles say "2D desktop only" in practice. | [Phoronix](https://www.phoronix.com/news/Asahi-Linux-Official-M3), [The Register](https://www.theregister.com/os-platforms/2026/09/07/asahi-linux-takes-on-apple-m3-minus-a-few-creature-comforts/5294788), [Asahi M3 feature page](https://asahilinux.org/docs/platform/feature-support/m3/) | 6-7 Sep 2026; page undated |
| GPU performance and power | Not usable. Developers say "wait a bit." No timeline given. | [The Register](https://www.theregister.com/os-platforms/2026/09/07/asahi-linux-takes-on-apple-m3-minus-a-few-creature-comforts/5294788), [Asahi progress report 6.19](https://asahilinux.org/2026/02/progress-report-6-19/) | Feb 2026 to Sep 2026 |
| Display (main panel, boot framebuffer) | Boot framebuffer linux-asahi. Full support WIP. | [Asahi M3 feature page](https://asahilinux.org/docs/platform/feature-support/m3/) | Undated |
| DCP (display controller) | WIP. Blocks sleep and HDMI. | [Phoronix](https://www.phoronix.com/news/Asahi-Linux-Official-M3) | 6 Sep 2026 |
| Brightness | WIP. No date. | [Asahi M3 feature page](https://asahilinux.org/docs/platform/feature-support/m3/) | Undated |
| HDMI out | Disabled on MacBooks until DCP work lands. | [Phoronix](https://www.phoronix.com/news/Asahi-Linux-Official-M3), [The Register](https://www.theregister.com/os-platforms/2026/09/07/asahi-linux-takes-on-apple-m3-minus-a-few-creature-comforts/5294788) | 6-7 Sep 2026 |
| External displays (Thunderbolt) | Not confirmed. One outlet says partial support may exist. Docs say WIP. | [Asahi M3 feature page](https://asahilinux.org/docs/platform/feature-support/m3/), [search summary of press](https://www.theregister.com/os-platforms/2026/09/07/asahi-linux-takes-on-apple-m3-minus-a-few-creature-comforts/5294788) | Sep 2026 |
| DisplayPort Alt Mode over USB-C | WIP. "Done when it's done." Experimental code exists. | [Phoronix, Feb 2026 report](https://www.phoronix.com/news/Asahi-Linux-EOY-2025-CCC) | Feb 2026 |
| ProMotion / 120 Hz | Not supported. Developers work to pass the 60 Hz limit. | [Asahi progress report 6.19](https://asahilinux.org/2026/02/progress-report-6-19/) | 18 Feb 2026 |
| Sleep and suspend | Conflict. Docs list SoC suspend as linux-asahi. Press says sleep does not work, due to the firmware framebuffer and missing DCP. Press is the better source for the user. | [Asahi M3 feature page](https://asahilinux.org/docs/platform/feature-support/m3/), [Phoronix](https://www.phoronix.com/news/Asahi-Linux-Official-M3) | 6 Sep 2026 |
| Lid close | One outlet says closing the lid shuts the system down, not suspend. The Register does not mention this. Not verified on the primary source. | [search summary of press](https://www.theregister.com/os-platforms/2026/09/07/asahi-linux-takes-on-apple-m3-minus-a-few-creature-comforts/5294788) | Sep 2026 |
| Battery life and battery info | Battery info linux-asahi. Battery life not stated by any source found. | [Asahi M3 feature page](https://asahilinux.org/docs/platform/feature-support/m3/) | Undated |
| Speakers | linux-asahi (docs). Not separately confirmed in press. | [Asahi M3 feature page](https://asahilinux.org/docs/platform/feature-support/m3/) | Undated |
| Microphones | Working. | [Phoronix](https://www.phoronix.com/news/Asahi-Linux-Official-M3) | 6 Sep 2026 |
| Headphone jack (3.5 mm) | linux-asahi (docs). | [Asahi M3 feature page](https://asahilinux.org/docs/platform/feature-support/m3/) | Undated |
| Wi-Fi | Working. | [Phoronix](https://www.phoronix.com/news/Asahi-Linux-Official-M3) | 6 Sep 2026 |
| Bluetooth | Working. | [Phoronix](https://www.phoronix.com/news/Asahi-Linux-Official-M3) | 6 Sep 2026 |
| Thunderbolt USB-C ports | USB 2 and USB 3 linux-asahi. Thunderbolt WIP. | [Asahi M3 feature page](https://asahilinux.org/docs/platform/feature-support/m3/) | Undated |
| USB 3 (10 Gb/s) | Working up to hardware limit. | [Phoronix](https://www.phoronix.com/news/Asahi-Linux-Official-M3) | 6 Sep 2026 |
| Keyboard | linux-asahi (kernel 7.3 per docs). | [Asahi M3 feature page](https://asahilinux.org/docs/platform/feature-support/m3/) | Undated |
| Keyboard backlight | linux-asahi (7.3). | [Asahi M3 feature page](https://asahilinux.org/docs/platform/feature-support/m3/) | Undated |
| Trackpad | linux-asahi. | [Asahi M3 feature page](https://asahilinux.org/docs/platform/feature-support/m3/) | Undated |
| Webcam | Working. Some lingering issues in Feb 2026. | [Phoronix](https://www.phoronix.com/news/Asahi-Linux-Official-M3), [Asahi progress report 6.19](https://asahilinux.org/2026/02/progress-report-6-19/) | Sep 2026 |
| SD card slot | linux-asahi. | [Asahi M3 feature page](https://asahilinux.org/docs/platform/feature-support/m3/) | Undated |
| Video decode (incl. AV1) | Working. | [Phoronix](https://www.phoronix.com/news/Asahi-Linux-Official-M3) | 6 Sep 2026 |
| Video encode, ProRes, Neural Engine | TBA. | [Asahi M3 feature page](https://asahilinux.org/docs/platform/feature-support/m3/) | Undated |
| Touch ID | TBA. | [Asahi M3 feature page](https://asahilinux.org/docs/platform/feature-support/m3/) | Undated |
| Installer | Expert mode only. | [The Register](https://www.theregister.com/os-platforms/2026/09/07/asahi-linux-takes-on-apple-m3-minus-a-few-creature-comforts/5294788) | 7 Sep 2026 |
| Upstream kernel | Incomplete. Patches target Linux 7.4 or later. | [Phoronix](https://www.phoronix.com/news/Asahi-Linux-Official-M3) | 6 Sep 2026 |

## Backward support question

- No older Asahi release supports M3 Pro better. M3 is the newest generation supported. Older M1 and M2 releases do not have M3 drivers.
- No M2 path exists for M3 hardware. The M3 GPU, DCP and firmware differ from M2. The Asahi GPU work covers a new GPU microarchitecture (per a German report summarised by search, not verified on the primary source).
- Update 2026-10-26: omacom/linux-aurora and iconidentify/siliconforest claim working M3 Pro (J516S) GPU acceleration with OS firmware 14.7. Not verified. See apple-rea-plan.md section 0b.
- Community patches: one experimental repo exists for Mac15,6 (gallantcrusader/asahi-m3pro-fullstack). It has no GPU or display support and is behind official Asahi. See m3-pro-help-feasibility.md. Otherwise, only Asahi's own downstream code exists. Asahi keeps experimental work in a "fairydust" branch. It is not officially supported. Its patches may be used, but they carry no support.

## Recommendation

- Install now with known gaps only if these limits are acceptable:
  - No sleep. Closing the lid shuts the system down.
  - No HDMI on the MacBook.
  - No 3D acceleration. The desktop is 2D only.
  - Installer requires Expert mode.
- Wait if the user needs sleep, HDMI, or 3D graphics. No timeline exists. Developers said "wait a bit" and gave no date.
- Re-check the [Asahi blog](https://asahilinux.org/blog/) before installing. Sources here date from 18 Feb 2026 to late Sep 2026. The official announcement page was not directly read.

## Caveats

- The feature table comes from the Asahi M3 docs page, read through a summarising fetch. Verify its rows against the page directly.
- The docs page shows no last-updated date.
- The sleep row conflicts between the docs and press. Press is used for the user-facing answer.
- The Asahi installer GitHub release page showed no releases when read. The installer change date could not be confirmed.
