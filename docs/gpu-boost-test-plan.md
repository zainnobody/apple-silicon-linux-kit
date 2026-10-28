# GPU clock test 2: boost words and base state (plan, 2026-10-28)

Goal: change the state-1 phase that follows the 20 s top-clock window (docs/performance.md, G1 e and f).
In the stop-and-go pattern (vk-stress, CPU check every 10th frame) the GPU is busy 58-82 % of the time.
After 20 s every burst runs at state 1 (338 MHz) and throughput falls from about 87 G to 64-67 G.
The target word (tgt_util=50) did not change this. This test tries the next controller words.

## The patch

`patches/g15-perf-boost-base.patch` adds three module parameters. All default to 0, and 0 keeps the
template value, so a boot without the arguments is the same as stage O.

| Parameter | Words (HardwareDataA) | Template | Range |
|---|---|---|---|
| `asahi.g15_perf_boost_min` | +0x790, boost minimum utilization, percent | 90 | 30..100 |
| `asahi.g15_perf_boost_step` | +0x794, boost step (`apple,perf-boost-ce-step`) | 50 | 10..100 |
| `asahi.g15_perf_base_pstate` | +0x7d8, +0x7e0, +0x81c = 100 x base; +0x7d4 = (top - base) / 0.95 as f32 | base 1 (100, 7.368) | 1..7 |

- The record writer (`g15/board/record.rs`) writes these words from the same device-tree values, so
  the offsets and the base-state formula come from the code, not from a guess.
- Each override checks that its words hold the template values first. If not, the driver logs
  "override refused" and the GPU probe fails. The boot still reaches a console, and the next boot is normal.
- The driver logs one line per override: "DVFS boost minimum utilization ..." or "DVFS base pstate ...".
- The parameters are read once, when the firmware starts. Each value needs a boot (the driver is built in).
- The meaning of the boost words is from their names only. The unit of the boost step is not known.

Build: `m3-legacy/scripts/build-boost.sh`, output `~/m3gpu/out/kernel-7.2.11-m3gpu+-boost`
(image sha256 e576affa234a19d3f930bc288206e28ddb51fc7f9b69058bc4ebc3a480df5ed0). It contains the recovery and tgt_util patches of stage O.

## Steps (each needs the user's go; installs and boots need sudo)

1. **Install as stage P** with `install/stage-p-boost.sh` (snapper snapshot, backup, image and modules, no
   boot argument change, no reboot). Reboot once into the normal entry.
2. **Default check (no arguments).** `journalctl -k -b | grep DVFS` shows no override line.
   `sudo cat /sys/kernel/debug/asahi-g15/pstate` shows the words unchanged (90, 50, 100).
   Run `tests/gpu-clock-probe.sh 60 10`. Expect the stage O result: 63-67 G, state 1 after 20 s.
   Run the fault gate once (`tests/fault-gate.sh 2 1`) because the kernel changed.
3. **Test boot P1: `asahi.g15_perf_boost_min=50`** (one time, through `install/window/gpu-boot.sh`
   with `ARG` and `WANT` set for stage P). Reason: the pattern's busy share (58-82 %) never reaches
   90 %, so the boost may never start. At 50 % it should.
4. **Test boot P2: `asahi.g15_perf_base_pstate=4`.** Reason: the controller falls to the base state.
   With base 4 the floor should be state 4, if the word is a floor.
5. **Optional P3: `asahi.g15_perf_boost_min=50 asahi.g15_perf_boost_step=100`**, only when P1 shows
   some boost but less than state 4 in most bursts.

## What to measure in each test boot

- The boot line and the driver's override line (`journalctl -k -b | grep DVFS`).
- The words in `/sys/kernel/debug/asahi-g15/pstate` (root): the overridden values must show.
- `tests/gpu-clock-probe.sh 60 10`, two runs with 30 s idle between them: throughput, and the time
  share of each clock state after 20 s (2 ms sampler).
- `tests/gpu-clock-probe.sh 20 0` (no wait): the top-clock value, 255-264 G at stage O.
- Idle: 2 minutes with no GPU load, state share from the sampler (state 0 should be above 95 %).
- Heat: `heat-sample.sh` maximums, from the probe output.
- `~/gpu-fault-watch.log` and `journalctl -k -b | grep -E "GPU fault|recovery|fail-stop"`.

## Pass

- The override line is in the kernel log, and the debugfs words show the new values.
- Check-10 run of 60 s: 100 G or more (stage O 64-67 G), and most bursts after 20 s above state 1.
- No-wait run: within 3 % of 263.6 G.
- Idle: state 0 at least 95 % of the time (no higher idle power).
- 0 GPU faults, 0 recovery lines, 0 fail-stop, desktop alive.

## Stop rules

- Stop at once and boot the normal entry if any of these occur: a GPU fault, a firmware halt or
  "recovery" line, "override refused", a hung desktop, or a hotspot of 95 C or more.
- On battery: no test boot. Run the boots on the charger only.
- One argument set per boot. Do not set two experiments in one boot except P3.
- If P1 and P2 both fail the pass rules, stop. Leave the parameters at 0 and write the result in
  docs/performance.md. The next step is then the 20 s window itself, not these words.

## Rollback

- A test boot is one time only (grub2-reboot): the next boot is the normal entry. `install/window/gpu-rollback.sh`
  removes the extra entry.
- Stage P itself: the parameters default to 0, so the normal entry behaves as stage O. A full undo
  copies the backup from `/root/m3gpu-backup/<time>-pre-boost` back, or rolls back the snapper snapshot.
