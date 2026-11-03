# Asahi Linux on M3 Pro (Mac15,7, serial [serial removed, see private-dumps]): status

Status (2026-10-26): Fedora Asahi Remix 44 KDE is installed and boots. macOS 15.6.1 shares the disk.
Fedora updates (639 packages) were started; a final macOS boot check and cleanup are still open.

## What changed on the M3, in order

1. macOS 14.6.1 install: admin group fixed (Apple's GUID added to GroupMembers), Preboot refreshed,
   container shrunk to 497 GB. Then the Asahi installer stopped: M3 needs system firmware from
   macOS 14.8.3 or newer (SFR >= 23.10.220), and 14.6.1 has 23.7.93.
2. No 14.7/14.8 full restore image exists. The user chose a DFU restore to macOS 15.6.1 (24G90)
   from the host with Apple Configurator (cfgutil restore -I). This ERASED the whole disk.
   Image SHA-256 3d87686b691ac765eb6a6b3082b2334e2af9710096a00432dd519af89ff2ea78 (matched ipsw.me).
3. User did macOS setup offline: admin user `Apple`, Remote Login on. SSH key m3_access re-added.
   New firmware: OS Loader 11881.140.96, SFR 24.7.90.0.0,0.
4. Asahi installer v0.9.2 ran offline from local copies (IPSW_BASE / REPO_BASE env vars), KDE only,
   codec extras dropped. Admin GUID fix needed again on the fresh macOS (same GroupMembers bug).
   macOS resized to 497.33 GB, Fedora got 497.33 GB (EFI 500M, Boot 1G, Root btrfs 459 GB).
5. `bless` needed Apple's signing server (BYErrorDomain 102, NetworkRequired). Fixed with a temporary
   proxy on the host plus SSH reverse tunnel and a macOS network service "USB Link" on en4 with
   HTTP/HTTPS proxy 127.0.0.1:3128. gs.apple.com signed the boot entry. Proxy and tunnel stopped.
   "USB Link" service is STILL configured in macOS: remove it with
   `sudo networksetup -removenetworkservice "USB Link"`.
6. Recovery step (step2.sh): kmutil needed the macOS admin name `Apple`, not a Linux name.
7. Fedora: user user, on Wi-Fi, joined tailnet as `fedora` (<m3-tailscale-ip>) with Tailscale SSH.

## Verified on Fedora (over Tailscale SSH)

- Kernel 7.1.6-400.asahi.fc44.aarch64+16k, Fedora Asahi Remix 44.
- lscpu: 12 CPUs online (0-11), two clusters of 6 (max 2748 MHz and 4056 MHz).
- Memory visible: 16 GiB of 18 GB.
- GPU: only simpledrm (simple-framebuffer) on card0. No GPU driver, no render node. Graphics are
  software-rendered. This matches the Asahi M3 announcement (no GPU acceleration yet; sleep and
  HDMI also do not work).

## Full hardware check (kernel 7.1.13-402.asahi, 2026-10-26)

- CPU: 12 workers for 15 s, all 12 cores at 100%. Max 4056 MHz (P) and 2748 MHz (E),
  apple-cpufreq with schedutil. Temperatures stayed at 25-33 C.
- Audio: macaudio J516 card. Headphone jack sink and headset mic present. Internal mic array
  filter (j516-mic) present. NO internal speaker sink, although speakersafetyd runs and 6 tas2764
  amps are detected: speakers look not yet enabled for M3.
- Camera: apple-isp, "FaceTime HD Camera (V4L2)" listed in PipeWire.
- Bluetooth: controller powered (codec-capability errors at boot, normally harmless).
- Wi-Fi: connected (brcmfmac -52 errors at boot, normally harmless).
- Battery and charger: reported (100%, AC online). USB-C PD ports reported.
- Keyboard, trackpad (Apple MTP), lid switch, keyboard backlight LED: present.
- Display backlight: NO /sys/class/backlight entry, so screen brightness control is missing
  (no DCP driver yet).
- Sleep: only s2idle offered; Asahi says sleep does not work on M3. Not tested.
- KVM: /dev/kvm present. Podman installed. Page size 16K. FEX/muvm not installed.

## Proxy log (what reached Apple through the host)

Allowed: gs.apple.com (signing), plus macOS background services before the proxy was narrowed:
courier.push, smoot, configuration, bag.itunes, ls (location), iadsdk, ocsp2.
Refused: gateway.icloud.com, updates.cdn-apple.com, non-Apple hosts. No sign-in happened.

## Finished after install

- Fedora: `dnf upgrade --refresh` done (658 packages, 0 left), restarted into kernel
  7.1.13-402.asahi.fc44; 12 CPUs, no failed units, Tailscale back, GPU still simpledrm only.
- macOS 15.6.1 boots (SIP on, FileVault off). "USB Link" service removed (grep count 0),
  ~/asahi-install deleted. Default startup disk is still the Fedora stub (/dev/disk1s2).
- Installer log kept on the host Mac: m3-logs/installer.log.

## Left

- Host Mac: the downloaded copies (15.6.1 IPSW, Asahi mirror, installer check, catalog, photos) deleted
  on the user's request. Kept: small scripts in tools/ and m3-logs/installer.log.
- Optional: set macOS as default in System Settings > General > Startup Disk.
