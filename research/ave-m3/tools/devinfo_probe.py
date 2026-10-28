#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Find the AVE_DevInfo soc-id name table and device table in a macOS 26 kernelcache. Read only.
The kext maps ADT soc-id ("t6030") through {prefix, number} entries (16 bytes) to a devID, which
indexes a 0x48-byte-stride table whose +4 is devType and +8 chipType (upstream docs/08 section 7).
  python3 -I devinfo_probe.py UPSTREAM_DIR KERNELCACHE
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dpe_probe_lib as P  # noqa: E402

up, kcpath = sys.argv[1], sys.argv[2]
f = P.load_fwgen(up)
f.lzfse_decode = P.lzfse_native
kc = f.Kernelcache(f.kernelcache_macho(open(kcpath, "rb").read()))
d = kc.d
ko = kc.kext(f.KEXT)
segs = {}
for cmd, off, size in f.load_commands(d, ko):
    if cmd == f.LC_SEGMENT_64:
        name = d[off + 8:off + 24].rstrip(b"\0").decode()
        segs[name] = struct.unpack_from("<QQQQ", d, off + 24)
print({k: (hex(v[0]), hex(v[3]), hex(v[2])) for k, v in segs.items()})
lo = min(v[2] for v in segs.values() if v[3])
hi = max(v[2] + v[3] for v in segs.values())
blob = d[lo:hi]
# name table: 16-byte entries, number at +8 (u32); find runs containing 6000
key = struct.pack("<I", 6000)
i = 0
found = []
while True:
    i = blob.find(key, i + 1)
    if i < 0:
        break
    base = i - 8
    if base < 0 or base % 8:
        continue
    run = []
    k = base
    while k + 16 <= len(blob) and len(run) < 64:
        num = struct.unpack_from("<I", blob, k + 8)[0]
        if not (1000 <= num <= 9999):
            break
        run.append(num)
        k += 16
    if len(run) >= 6:
        found.append((lo + base, run))
for a, run in found:
    print("name table at file", hex(a), "numbers:", run)

# --- extend the name table backwards, then find the 0x48-stride device table ---
a0, run0 = found[0]
off = a0 - lo
back = []
k = off - 16
while k >= 0:
    num = struct.unpack_from("<I", blob, k + 8)[0]
    if not (1000 <= num <= 9999):
        break
    back.append(num)
    k -= 16
names = list(reversed(back)) + run0
print("full soc-id name table:", names, "-> index of 6030 =", names.index(6030), ", 6000 =", names.index(6000))
i6000, i6001, i6030 = names.index(6000), names.index(6001), names.index(6030)
u = lambda o: struct.unpack_from("<I", blob, o)[0]
hits = []
for o in range(0, len(blob) - 0x48 * 40, 4):
    if u(o + 4) == 9 and u(o + 8) == 6 and u(o + 0x48 + 4) == 10 and u(o + 0x48 + 8) == 7:
        hits.append(o)
print("device table candidates (file offs):", [hex(lo + h) for h in hits])
for h in hits[:2]:
    t0 = h - 0x48 * i6000
    print("table start", hex(lo + t0))
    for n, idx in (("6000", i6000), ("6001", i6001), ("6030", i6030), ("6031", names.index(6031)), ("8112", names.index(8112))):
        o = t0 + 0x48 * idx
        print(" soc", n, "idx", idx, "words +0..+0x44:", " ".join(f"{u(o + 4 * j):x}" for j in range(18)))
