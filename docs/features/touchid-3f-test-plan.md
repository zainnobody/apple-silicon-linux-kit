# Touch ID 3f test plan: late-touch capture (written 2026-10-27, nothing here has been run)

Run this with the user present. The user touches the sensor on request. Everything else is typed by the person running the test.

## 1. What is known

- Enrol, persistence across reboots and the enclave decision all work. A finger that is on the sensor before a capture starts gets a frame (state 0, 17, 19, 7) and the enclave answers MATCH or NO MATCH correctly.
- A finger that arrives after the capture started gets no frame. The data-ready interrupt works (it fires), but the sensor state stays "armed" (17).
- Each start gives a finger-detect window of about 250 ms. The raw status then changes to a "scan finished, nothing seen" value and the state stays 17.
- A start command while armed does nothing. Idle followed at once by a start did not detect a held finger in 28 windows.
- The driver itself pauses 1800 ms after idle before the next start (between enrol captures and before each verify). The first re-arm tests skipped that pause. Whether the pause is the missing piece is a hypothesis.

## 2. What is prepared (offline, not run on hardware)

| Item | What it is |
|---|---|
| `apple-sep-3f.ko` | The 3d trace, the 3e re-arm, and a settle pause after idle. Parameters under `/sys/module/apple_sep/parameters/` (writable at run time): `sensor_rearm_mode` (0 off, 1 timed idle, settle, start; 2 on status change idle, settle, start; 3 timed start only; 4 on status change full restart with power cycle; default 2), `sensor_rearm_settle_ms` (default 1800), `sensor_rearm_ms` (default 300, modes 1 and 3). |
| `touchid-boot.sh --sensor-irq` | Test DTB with the data-ready interrupt in the sensor node. |
| `touchid-3b.sh` | `load`, `open`, `enrol`, `verify`, `status` and `alarm`, with the alarm check after each step. Select the module with `TOUCHID_3B_MODULE=apple-sep-3f.ko`. |
| `loopverify.sh [CYCLES]` | Fallback: up to 12 full new verifies of 4 s each. See section 6. |

## 3. Steps

1. **Normal boot.** The test boot of an earlier run still has `apple_sep` loaded and it cannot be unloaded. Reboot to a normal boot first (`lsmod | grep apple_sep` prints nothing).
2. **Backup.** `touchid-xart.sh backup`, then `verify`. Copy the backup to the Mac. `touchid-3b.sh pre` refuses to continue unless the newest backup equals the partition.
3. **Install the module.** `sudo install -D -m 0644 ~/window/touchid/apple-sep-3f.ko /lib/modules/7.2.11-m3gpu+/touchid-test/apple-sep-3f.ko`, then `sudo restorecon -F` on that path. Check the sha256 file next to the module.
4. **Arm the test boot.** `touchid-boot.sh --sensor-irq` (optional `--dry` first). Look for `A1 PASS: sensor data-ready interrupt is ... rising edge` and `ARMED`. Undo before the reboot: `touchid-disarm.sh`.
5. **Reboot.** Then check: the restore unit is gone (`systemctl is-enabled m3-touchid-restore.service` prints `not-found`), the boot file is the base again, and `od -An -tx1 /proc/device-tree/soc/spi@289108000/fingerprint@0/interrupts` shows the interrupt cells.
6. **Load and open.** `TOUCHID_3B_MODULE=apple-sep-3f.ko touchid-3b.sh load`, then `open`, then `status`. Expect `LOAD PASS`, `OPEN PASS`, `ALARM CHECK OK`, one identity, and `sensor: interrupt-driven capture`.
7. **Control.** One verify with the enrolled finger on the sensor before the start: MATCH. This proves the setup still works.
8. **Late touch, mode 2, settle 1800.** The user keeps the finger off until the line `place the finger on the sensor` appears, then puts the enrolled finger on and holds it for at least 5 s. Run `touchid-3b.sh verify` and read the trace: `sudo journalctl -k --since "<time>" | grep -E "sensor: capture|re-arm"`.
   - Pass: after a re-arm line, state 17, 19, 7, a frame, then MATCH.
   - Fail: re-arm lines with `ok` and only states 0 and 17, then `no result`.
9. **If step 8 passes, find the shortest settle.** `echo 1000 | sudo tee /sys/module/apple_sep/parameters/sensor_rearm_settle_ms`, then 600, then 300. Repeat step 8 at each value. Write down which values detect.
10. **If step 8 fails, try the other modes** (one late touch each, hold 5 s or more): mode 1 (`echo 1`), then mode 4 (`echo 4`, experimental: it power-cycles the sensor and runs the bring-up inside the capture wait). Mode 4 last.
11. **If every mode fails, run `loopverify.sh`** (section 6) with mode 0 (`echo 0 | sudo tee .../sensor_rearm_mode`).
12. **After a working late touch:** 3 late-touch verifies with the enrolled finger (all MATCH) and 3 with another finger (all NO MATCH). Only then re-enrol with late touches if the earlier template needs it, and follow the trial plan in the stage 3b plan.

## 4. Stop rules

Stop at once, run no further step, and tell the user, on any of these:
- `re-arm ... FAILED`, `the sensor fell to state ...` (state 9 means the sensor lost its patch), more than 40 re-arm lines in one wait, an interrupt storm line (`nobody cared`, `Disabling IRQ`), a CPU stall, a hang in mode 4. Reboot and keep the log.
- Any `xART guard (loaded only): refused` line, any ALARM, `identity-keybag provisioning failed`, zero identities after the reboot.
- A MATCH for a finger that is not the enrolled one.
- Do not repeat a failing step in a loop. One valid failure per setting is enough.
- Do not enrol or delete an identity in this boot until a late touch works.

## 5. What to record

For each late-touch trial: the finger, how long it was held, the mode and settle values, the first lines of the trace (state changes and re-arm lines with times), and the result. Save the journal part of the trial.

## 6. The restart loop (fallback)

`loopverify.sh` runs up to 12 verifies in a row. Each is a complete new capture session: sensor power-up, the 1.8 s pause, arm, the 250 ms finger-detect window. A cycle is cancelled after 4 s (`LOOP_CYCLE_S`, at least 3). The user holds one finger on the sensor for the whole run (about 55 s). The loop stops at the first MATCH or NO MATCH, after two errors in a row, or after the cycles, and then runs the alarm check.

Safety:
- The cancel is the normal Ctrl-C style cancel of the verify client. A cycle that gets no frame writes nothing to the xART store (the earlier late-touch tests show no store operations in the log). Only the final MATCH or NO MATCH writes, as any verify does.
- A cycle shorter than the pause plus the bring-up cancels before the sensor arms. The first version of the script used 1.5 s and would have tested nothing after the first cycle. It also ignored a closed sudo window. Both are fixed.
- The detect window is only about 250 ms in a cycle of about 4.5 s, so the finger must stay down for the whole run. This is a test, not a usable login path.

## 7. After the test

Whatever the result, write it into this file and into the stage 3b plan. Take a fresh backup before the next test boot. Touch ID stays off login, PAM and sudo until the trial plan in the stage 3b plan passes with many more trials.
