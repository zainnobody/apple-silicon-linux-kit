#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Print raw AVE_DevCap entries (u32 words) from a macOS 26 kernelcache. Read only.
  python3 -I devcap_probe.py UPSTREAM_DIR KERNELCACHE SUFFIX...   e.g. 6030 6000 8112
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dpe_probe_lib as P  # noqa: E402

up, kcpath, sufs = sys.argv[1], sys.argv[2], sys.argv[3:]
f = P.load_fwgen(up)
f.lzfse_decode = P.lzfse_native
kc = f.Kernelcache(f.kernelcache_macho(open(kcpath, "rb").read()))
syms = kc.symbols(kc.kext(f.KEXT))
names = sorted(n for n in syms if "AVE_DevCap" in n)
print(len(names), "DevCap symbols:", [n.split("gsc_sAVE_DevCap_")[-1] for n in names])
for s in sufs:
    for n in names:
        if n.endswith("_" + s):
            o = kc.off(syms[n], 0x100)
            w = struct.unpack_from("<64I", kc.d, o)
            print(n, "\n ", " ".join(f"{x:x}" for x in w[:48]))
