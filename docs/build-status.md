# M3 GPU build status

Date: 2026-10-26. All three parts are built on the M3 (Fedora, `user@<m3-tailscale-ip>`). Nothing is installed. No boot files are changed.

| Part | Source commit | Output on the M3 | Check |
|---|---|---|---|
| Kernel 7.2.11-m3gpu+ | siliconforest-linux `0e1f4666` | `~/m3gpu/out/kernel-7.2.11-m3gpu+/` (`boot/`, `lib/modules/`, `dtb/`) | 16K-page ARM64 Image, 5,644 modules, `apple/t6030-j516s.dtb`, 0 errors in log |
| m1n1 stage 2 | siliconforest-m1n1 `aca1258c` | `~/m3gpu/out/m1n1/m1n1-aca1258c...bin` | sha256 `3118c16f20ee32dba8c8eee14e00fd37c31ab6ab200d12c7cad6c1e60500a710`, 5 MiB |
| Mesa 26.3.0-devel | siliconforest-mesa `7515336b` | `~/m3gpu/out/mesa-stage/opt/mesa-m3/` (69 MB) | `asahi_dri.so`, `libvulkan_asahi.so` (contains G15S), ICD points to `/opt/mesa-m3/lib64/libvulkan_asahi.so`, 0 errors |

## Kernel config (final, verified in the staged config)

- `CONFIG_SILICONFOREST_NATIVE_GPU=y`, `CONFIG_DRM_ASAHI=y`, `CONFIG_DRM_ASAHI_G15=y`, `CONFIG_APPLE_PMP=y`
- Off: `APPLE_SEP`, `ARM64_USER4K_EXPERIMENTAL`, `KUNIT`, `LIVEPATCH`; `SILICONFOREST_M3` absent
- Base: Fedora `config-7.1.13-402.asahi.fc44.aarch64+16k`, built with GCC 16.2.1 like Fedora

## Fixes needed during the build

1. m1n1: GCC link failed on `__popcountdi2`; built with clang (`USE_CLANG=1 ARCH=aarch64-linux-gnu`), as in the fork's CI.
2. Kernel: `LIVEPATCH` failed a `KSYM_NAME_LEN` build check; turned off.
3. Kernel: the Rust `gpuvm` binding needs `DRM_GPUVM=y`, so `DRM_ASAHI=y` (built in), which needs `APPLE_PMP=y`. This matches the SiliconForest config.
4. KDE idle suspend stopped the first kernel build (about 10:28). Fix: `~/.config/powerdevilrc` now has `AutoSuspendAction=0` for AC and battery, and `LidAction=0` for AC. Builds now run as `systemd-run --user` services.

## Open points for the install step

- The GPU driver uses firmware structures named `G15V14_8_3` (macOS 14.8.3). Our stub is 14.7. m1n1 arms the GPU only for two listed 14.8.3 image UUIDs. A first boot with the GPU off will show whether our firmware matches.
- Fedora's m1n1 `boot.bin` carries the device trees for all kernels. Putting the new j516s DTB in it also affects the Fedora fallback kernel. Recovery for a bad `boot.bin` is from macOS. Plan this before installing.
- Mesa must be copied to `/opt/mesa-m3` with sudo, then used per program with environment variables only.
