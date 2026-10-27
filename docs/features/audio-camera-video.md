# Audio, camera and video codecs on the M3 Pro (J516S)

Tested 2026-10-26 over SSH on Fedora Asahi Remix 44.
**Kernel tested: `7.2.11-m3gpu+`** (the one-boot test kernel, not the stock 7.1.13).
No kernel, boot entry, firmware or m1n1 change was made. No recording or image was kept.
Asahi status column: from `docs/asahi-m3-pro-status.md`.

## Results

| Feature | Test run | Result | Evidence | Asahi status |
|---|---|---|---|---|
| Sound cards | `/proc/asound/cards`, `aplay -l`, `arecord -l` | Works, but only for the logged-in desktop user | Cards `AppleJ516` (macaudio) and `AppleJ516HPAI` (aop_audio). From a pure SSH session (greeter on seat0) `aplay -l` shows no cards and PipeWire lists no devices, because device ACLs go to the active seat user. After the user logged in at the KDE desktop, all devices appeared | n/a |
| Speakers | `wpctl status`, 440 Hz 3 s and 880 Hz 5 s tones at volume 0.25 and 0.40 (default 0.70, restored) | **Partly confirmed. Not a full pass.** | Sink "MacBook Pro J516 Speakers" (convolver filter) exists and is the default. 6 `tas2764` amps probed, `speakersafetyd` active, "Speaker volumes unlocked" in the kernel log. User heard "something for a second" from the 3 s tone. Host mic saw a short +10 dB bump. The 5 s tone gave no clear mic result (room noise) and no answer from the user yet | linux-asahi (docs). Not confirmed in press |
| Microphones | `ffmpeg -f pulse -i effect_output.j516-mic`, 9 s, level only, file deleted. A 1 kHz tone played from the host Mac | **Works** | Tone at about -61 dB for 4 s against a floor of about -88 dB. Sources found: `effect_output.j516-mic` (array) and Headset Microphone (jack) | Working (Phoronix, 6 Sep 2026) |
| Headphone jack | `amixer -c 1 cget` jack controls | **Not tested.** No headphones available | "Headphone Jack" and "Headset Mic Jack" read `off`. Input device "MacBook Pro J516 Headphone Jack" and a headphone sink exist | linux-asahi (docs) |
| Webcam | `wpctl inspect`, ffmpeg v4l2 captures: stats runs, then one 1280 px frame sent to the user (copies deleted) | **Works for capture. Picture quality is poor. LED lit on a 15 s run (user report), dark on the shorter 1 to 10 s runs.** The frame shows a real, sharp, correctly exposed scene | `/dev/video0` is "FaceTime HD Camera", driver `apple-isp`. NV12 up to 1920x1080. 10 s run gave 301 frames (about 30 fps). The image was viewed by Claude and by the user. The camera LED is not exposed under `/sys/class/leds`, so software cannot test or force it. LED: dark on the earlier short runs, lit on a 15 s run. The `isp@2c8000000` node has no LED property, so the LED is probably driven by firmware or hardware. Quality (1080p frame, dim room, mixed light): heavy grain, strong purple and yellow colour cast, face underexposed against a bright lamp. The driver exposes only 2 V4L2 controls (camera class, dynamic framerate): no exposure, gain or white balance. `libcamera` 0.7.2 is installed, but no Apple ISP pipeline was used, so auto exposure, white balance and denoise are whatever the ISP firmware does | Working. Some issues in Feb 2026 |
| Video decode hardware | Kernel log, `/lib/firmware/apple`, `ffmpeg -hwaccels` | **Fails on this boot** | `avd 30b080000.avd: Direct firmware load for apple/avd-fw-v4-t0.bin failed with error -2`, then `probe ... failed with error -2`. `/lib/firmware/apple` does not exist. `apple_avd` module is loaded but binds to nothing. No `/dev/video` node for it | Working (Phoronix, 6 Sep 2026). **Not reproduced here** |
| H.264, HEVC, AV1 hardware decode with CPU comparison | Not run | **Blocked** by the missing AVD firmware. Also `vainfo` is not installed and Fedora `ffmpeg-free` has no HEVC decoder and only OpenH264 for H.264 | See above | |
| Software decode baseline | 1080p 30 fps 10 s AV1 test clip (SVT-AV1), `libdav1d` | Works | Wall 2.18 s, user 4.43 s, sys 0.22 s, CPU 212% of 1200% (12 cores) | n/a |
| Video encode | `ffmpeg -encoders` | **No hardware encoder** | Only `*_vaapi` and `*_v4l2m2m` wrappers are listed. No VA driver exists, and the only v4l2 video node is the camera | TBA |
| ProRes | `ffmpeg -encoders` | Software only | `prores`, `prores_aw`, `prores_ks` run on the CPU. No hardware ProRes block is exposed | TBA |

## Notes

- An earlier note in the shared folder said the speaker sink was missing. After the desktop login the sink exists. The earlier reading came from a session without seat access.
- The host Mac's AirPlay sink also shows up in `wpctl`. Test tones went to the speaker node by name, not to it.
- ProRes encode and decode in hardware are not part of the hardware decode driver in this kernel.

- One SSH timeout at 21:15 was probably the user closing the lid (suspend). The M3 had no reboot (up 33 min, same kernel). Keep the lid open for tests.

## Camera quality: same-light comparison (2026-10-26 22:50)

- Same room, same two lights, same seat. macOS Photo Booth (1440x960) against Linux ffmpeg capture (1920x1080, `apple-isp`, kernel 7.2.11-m3gpu+).
- Mean luma at 1280 px width: macOS 150, Linux 128. Saturation equal (14.6 and 14.5).
- Linux in this light: natural warm colour, no purple cast, face visible, fine grain visible in the flat wall. macOS: cleaner, brighter, less grain, face lit more evenly.
- The earlier poor frame came mostly from the dark room (one weak lamp), not from a broken camera. Linux is usable in decent light and still behind macOS in noise and brightness. Photo Booth may add its own processing.
- Calibration files are installed: `/lib/firmware/vendor/apple/isp_{1820,1822,1921,1922,8720,8723}_*.dat` (6 files, dated install time). The driver has a table of about 40 names. A start of the camera printed no "setfile not loaded, streaming without calibration" warning, so a setfile was probably loaded. Which file matched was not logged. The hypothesis that calibration is missing is not supported. The remaining gap may be missing exposure and tone control in Linux (the driver exposes no exposure or gain control), or ISP behaviour that macOS tunes further.
- Next test: bright daylight, and 5 min of video to see whether auto exposure settles.

## Next steps

1. Get the AVD firmware `apple/avd-fw-v4-t0.bin` into `/lib/firmware`. Ask the firmware session where it comes from (extract from macOS, or the Asahi firmware tool). This needs root on the M3 and a change to the system, so it needs the user's go. Then rerun the decode tests.
2. Install `libva-utils`, `v4l-utils` and a full ffmpeg (RPM Fusion) so H.264 and HEVC clips can be tested. Needs root and the user's go.
3. Repeat the speaker test with the user listening, with a 5 s tone, and ask about left and right.
4. Test the headphone jack when headphones are available: jack state, quiet tone, headset mic.
5. Camera LED: lit on a 15 s run, dark on short runs. Repeat with 30 s and 5 s runs and note the timing. Treat the camera as active whenever an app uses it until this is understood.
6. Camera quality: compare the same scene in macOS (same light). If macOS is much better, the gap is ISP tuning and processing that Linux lacks. Check whether the Asahi `libcamera` pipeline for `apple-isp` is in Fedora 44.
7. Retest on the stock 7.1.13 kernel to see whether the result differs (needs a reboot, so it needs the user's go and a message to the GPU session first).

## What needs the user's hands

- Listen to the speaker tone and say what was heard (length, left or right, distortion).
- Plug in headphones for the jack test.
- Type sudo passwords in their own Terminal tab for any firmware or package step.
- Log in to the KDE desktop after each boot, or audio and camera stay hidden from SSH.
