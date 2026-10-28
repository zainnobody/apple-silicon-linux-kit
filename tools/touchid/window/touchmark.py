#!/usr/bin/env python3
"""Touch-time logger for the Touch ID late-touch tests. Run it on the M3 in its own terminal tab (ssh -t), next to the loop.

  python3 -I ~/window/touchmark.py

The USER presses Enter at the moment the finger LANDS on the sensor, and Enter again at the moment it LIFTS. The first
Enter of a pair is a DOWN, the second an UP. Each Enter is stamped with the M3 clock (epoch seconds, microseconds) and
appended to ~/window/touch.marks, so a touch time never depends on a chat message. Keys: r + Enter = start a new pair
(the next Enter is a DOWN), q + Enter (or Ctrl-D) = quit. Use one hand on the sensor and the other on Enter.
"""
import os
import sys
import time

path = os.path.expanduser(os.environ.get("TOUCH_MARKS", "~/window/touch.marks"))
print("touch marks -> %s" % path)
print("Enter = finger lands (DOWN), Enter = finger lifts (UP). r = next Enter is a DOWN again, q = quit.")
n = 0
down = True
with open(path, "a", buffering=1) as out:
    out.write("# session start %.6f\n" % time.time())
    while True:
        line = sys.stdin.readline()
        t = time.time()
        if line == "":
            break
        cmd = line.strip().lower()
        if cmd == "q":
            break
        if cmd == "r":
            down = True
            print("reset: the next Enter is a DOWN")
            continue
        n += 1
        kind = "D" if down else "U"
        down = not down
        out.write("%.6f %s\n" % (t, kind))
        print("%3d %s %s.%03d" % (n, "DOWN" if kind == "D" else "UP  ", time.strftime("%H:%M:%S", time.localtime(t)), int((t % 1) * 1000)))
    out.write("# session end %.6f\n" % time.time())
print("done, %d marks" % n)
