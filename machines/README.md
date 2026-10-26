# Machine profiles

Each file sets the values that differ between Macs. Select one with `AGX_PROFILE` (in `config.local.sh` or the environment). The default is `j516s`.

| Profile | Machine | SoC / GPU | Status |
|---|---|---|---|
| `j516s` | MacBook Pro 16-inch M3 Pro (Mac15,7) | T6030 / G15S | Tested 2026-10-26 (chip revision B1, OS firmware 14.7) |

## Add a machine

1. Copy `j516s.sh` to `<board>.sh`.
2. Set the values from the running machine:
   - `AGX_MACHINE`: the board line of `tr '\0' '\n' < /proc/device-tree/compatible`, for example `apple,j514s`.
   - `AGX_DTB_NAME`: the board DTB in `/boot/dtb/apple/`, for example `t6030-j514s.dtb`.
   - `AGX_GPU_NODE`: `ls /sys/bus/platform/devices | grep gpu`.
   - `AGX_M1N1_OPTIONS`: the m1n1 GPU and display options for the SoC. The T6030 names are `t6030-gpu`, `t6030-dcp`, `t6030-dcpext`. Check the m1n1 source (`src/kboot_gpu.c`) for other SoCs.
3. Run the stages. If the GPU driver refuses the firmware, it prints the TEXT hash. Read `docs/gpu-firmware-investigation.md` before you add a pin.
4. Add a row to the table above with the date and what you tested.
