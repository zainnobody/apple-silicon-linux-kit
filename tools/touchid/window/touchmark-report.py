#!/usr/bin/env python3
"""Correlate touch marks with the sensor capture trace.

  python3 -I touchmark-report.py JOURNAL MARKS [CYCLE_S]

JOURNAL is the kernel log of a loop run with the 3d, 3e or 3f module and sensor_trace=1, saved with
`journalctl -k -o short-unix` (loopverify.sh does this; the short-precise format also works, in local time).
MARKS is the file written by touchmark.py. For every finger touch (a DOWN and its UP) the report says when the finger landed
relative to the start of the capture it fell into, how long it stayed, and whether and when the sensor saw it
(state 19 = finger seen, 7 = frame ready). The summary groups the touches by landing time.
"""
import re
import sys
import time

jpath, mpath = sys.argv[1], sys.argv[2]
cycle_s = float(sys.argv[3]) if len(sys.argv) > 3 else 7.0

marks = []
for line in open(mpath):
    p = line.split()
    if len(p) == 2 and p[1] in ("D", "U"):
        marks.append((float(p[0]), p[1]))
if not marks:
    sys.exit("no marks in %s" % mpath)
year = time.localtime(marks[0][0]).tm_year


def stamp(line):
    m = re.match(r"(\d{9,11}\.\d+) ", line)
    if m:
        return float(m.group(1))
    m = re.match(r"([A-Z][a-z]{2}) +(\d+) (\d+):(\d+):(\d+)\.(\d+) ", line)
    if not m:
        return None
    mon = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"].index(m.group(1)) + 1
    t = time.mktime((year, mon, int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5)), 0, 0, -1))
    return t + float("0." + m.group(6))


caps = []  # each: dict(t0, events=[(offset_ms, state)], timeout_ms)
for line in open(jpath, errors="replace"):
    t = stamp(line)
    if t is None:
        continue
    if "capture wait starts" in line:
        caps.append({"t0": t, "ev": [], "timeout": None})
        continue
    if not caps:
        continue
    m = re.search(r"capture poll (\d+) ms: state (\d+)", line)
    if m:
        caps[-1]["ev"].append((int(m.group(1)), int(m.group(2))))
    m = re.search(r"capture wait timed out after (\d+) ms", line)
    if m:
        caps[-1]["timeout"] = int(m.group(1))
if not caps:
    sys.exit("no 'capture wait starts' lines in %s (sensor_trace=1 and the 3d/3e/3f module are needed)" % jpath)

for i, c in enumerate(caps):
    nxt = caps[i + 1]["t0"] - 0.4 if i + 1 < len(caps) else c["t0"] + cycle_s
    c["end"] = min(nxt, c["t0"] + 65.0)
    seen = [off for off, st in c["ev"] if st in (19, 7)]
    c["seen"] = min(seen) / 1000.0 if seen else None

# pair the marks: a DOWN followed by the next UP
touches = []
pending = None
for t, k in marks:
    if k == "D":
        pending = t
    elif pending is not None:
        touches.append((pending, t))
        pending = None

print("captures %d, touches %d, cycle %.1f s\n" % (len(caps), len(touches), cycle_s))
rows = []
for n, (td, tu) in enumerate(touches, 1):
    hold = tu - td
    # first capture that the finger overlaps
    hit = None
    for i, c in enumerate(caps):
        if tu >= c["t0"] and td <= c["end"]:
            hit = i
            break
    if hit is None:
        print("touch %2d: down %s hold %.2f s: no capture was running (dead time or before the loop)" % (n, time.strftime("%H:%M:%S", time.localtime(td)), hold))
        continue
    c = caps[hit]
    arrive = td - c["t0"]
    if c["seen"] is not None:
        t_seen = c["t0"] + c["seen"]
        ok = td - 0.1 <= t_seen <= tu + 0.5
    else:
        t_seen, ok = None, False
    if arrive < 0:
        where = "on before the capture start (%.2f s before)" % -arrive
        bin_ = "on at start"
    else:
        where = "landed %.2f s after the capture start" % arrive
        bin_ = ("0.0-0.3 s" if arrive < 0.3 else "0.3-1.0 s" if arrive < 1.0 else "1.0-1.9 s" if arrive < 1.9 else
                "1.9-2.3 s" if arrive < 2.3 else "2.3-4.0 s" if arrive < 4.0 else "4.0 s or later")
    if ok and arrive < 0:
        verdict = "SEEN at +%.3f s of the capture" % c["seen"]
    elif ok:
        verdict = "SEEN at +%.3f s (latency %.0f ms after landing)" % (c["seen"], (t_seen - td) * 1000)
    elif c["seen"] is not None:
        verdict = "not matched to this touch (capture saw a finger at +%.3f s)" % c["seen"]
    else:
        verdict = "NOT seen (state stayed armed)"
    until = min(tu, c["end"]) - c["t0"]
    print("touch %2d: capture %d, %s, finger down for %.2f s (until +%.2f s of the capture): %s" % (n, hit + 1, where, hold, until, verdict))
    rows.append((bin_, ok))

print("\nsummary by landing time (touches that overlapped a capture):")
order = ["on at start", "0.0-0.3 s", "0.3-1.0 s", "1.0-1.9 s", "1.9-2.3 s", "2.3-4.0 s", "4.0 s or later"]
for b in order:
    sel = [ok for bb, ok in rows if bb == b]
    if sel:
        print("  %-15s %d touches, %d seen" % (b, len(sel), sum(sel)))
