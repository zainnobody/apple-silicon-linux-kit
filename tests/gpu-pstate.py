#!/usr/bin/env python3
# GPU clock state sampler (root): reads /sys/kernel/debug/asahi-g15/pstate every INTERVAL ms
# for SECONDS seconds and writes one CSV line per change (time, pstate, freq, firmware
# power-state count, hwdata actual/target/current). At the end it prints the time share of each
# state and the number of changes. Usage: gpu-pstate.py <csv> [seconds] [interval ms]
import re, sys, time
out = sys.argv[1]
secs = float(sys.argv[2]) if len(sys.argv) > 2 else 60
step = (float(sys.argv[3]) if len(sys.argv) > 3 else 2) / 1000
F = "/sys/kernel/debug/asahi-g15/pstate"
rx = re.compile(r"pstate (\d+) freq_khz (\d+).*?power_states (\d+).*?actual (\d+) target (\d+) current (\d+)", re.S)
share, last, changes, reads, t0 = {}, None, 0, 0, time.monotonic()
prev_t = t0
with open(out, "w") as o:
    o.write("t_ms,pstate,freq_mhz,power_states,actual,target,current\n")
    while True:
        now = time.monotonic()
        if now - t0 >= secs:
            break
        with open(F) as f:
            m = rx.search(f.read())
        reads += 1
        if m:
            v = tuple(int(x) for x in m.groups())
            if last is not None:
                share[last[0]] = share.get(last[0], 0) + (now - prev_t)
            prev_t = now
            key = (v[0], v[3], v[4], v[5])
            if last is None or key != (last[0], last[3], last[4], last[5]):
                if last is not None and v[0] != last[0]:
                    changes += 1
                o.write(f"{(now - t0) * 1000:.1f},{v[0]},{v[1] // 1000},{v[2]},{v[3]},{v[4]},{v[5]}\n")
            last = v
        time.sleep(step)
total = sum(share.values()) or 1
print(f"pstate: {reads} reads in {secs:.0f} s ({reads / secs:.0f}/s), {changes} state changes")
print("pstate share: " + " ".join(f"s{k}={100 * v / total:.1f}%" for k, v in sorted(share.items())))
mean = sum(k * v for k, v in share.items()) / total
print(f"pstate mean {mean:.2f}")
