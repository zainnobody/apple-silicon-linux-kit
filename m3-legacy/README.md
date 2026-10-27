# Exact copies from the tested M3 Pro

These files are copied unchanged from the tested MacBook Pro M3 Pro (J516S), 2026-10-26. They built and installed its current state. They use the first names of the test (`~/m3gpu`, `/opt/mesa-m3`, `m3gpu-boot`). For a new install, use the general versions in `build/` and `install/`. Use these files to see exactly what ran.

| Path | What it is |
|---|---|
| `scripts/build-kernel.sh`, `build-m1n1.sh`, `build-mesa.sh`, `common.sh`, `make-bootbin.sh`, `use-bootbin.sh`, `setup-nopasswd.sh`, `stage-a.sh` to `stage-g.sh` | The M3 copies of the build and install scripts. `deps.sh` and `fetch-sources.sh` are the same as in `build/`. Stages H to L are in `install/`. |
| `scripts/add_floor.py` | Adds the PMP memory floor to `pmp-report.c` (the result is `patches/t6030-pmp-memory-floor.patch`). |
| `scripts/build-memfloor.sh` | Incremental kernel build for stage J. |
| `scripts/build-usb4.sh` | Incremental kernel build with `CONFIG_USB4_APPLE_SOC=m` and the Bluetooth patch, staged in `~/m3gpu/out/kernel-7.2.11-m3gpu+-usb4-bt` (stage L). |
| `kernel/config-7.2.11-m3gpu+-installed` | `/boot/config-7.2.11-m3gpu+` of the installed image (stage J). |
| `kernel/config-7.2.11-m3gpu+-usb4` | The build config of the stage L modules. It differs from the installed config in one line: `CONFIG_USB4_APPLE_SOC=m`. |

The root-owned files installed on the M3 are in `install/m3-installed/`.
