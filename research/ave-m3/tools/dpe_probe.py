#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Helpers: probe AppleAVE2 DPE tunable tables in a macOS 26 kernelcache (read only).

Reuses the upstream parser (ave_fwgen.py) with three changes for macOS 26:
LZFSE through libcompression (no lzfse tool needed), symbol prefix `gsc_s`
instead of `gs_s`, and a raw header dump to check the struct layout first.
Nothing is written. Run: python3 -I dpe_probe.py UPSTREAM_DIR KERNELCACHE SET...
"""
import ctypes
import importlib.util
import struct
import sys


def load_fwgen(upstream):
    spec = importlib.util.spec_from_file_location("ave_fwgen", upstream + "/tools/ave_fwgen.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def lzfse_native(data, size):
    lib = ctypes.CDLL("/usr/lib/libcompression.dylib")
    dst = ctypes.create_string_buffer(size)
    n = lib.compression_decode_buffer(dst, size, data, len(data), None, 0x801)
    if n != size:
        raise SystemExit(f"lzfse: got {n}, want {size}")
    return dst.raw


def main():
    up, kcpath, sets = sys.argv[1], sys.argv[2], sys.argv[3:]
    f = load_fwgen(up)
    f.lzfse_decode = lzfse_native
    kc = f.Kernelcache(f.kernelcache_macho(open(kcpath, "rb").read()))
    syms = kc.symbols(kc.kext(f.KEXT))
    print("kext symbols:", len(syms))
    for s in sets:
        want = "gsc_sAVE_DPE_CfgSet_" + s
        hits = [(n, v) for n, v in syms.items() if n.endswith(want)]
        print(s, "->", hits)
        if len(hits) != 1:
            continue
        o = kc.off(hits[0][1], 0x80)
        raw = struct.unpack_from("<16Q", kc.d, o)
        print("  raw u64[0..3]:", [hex(x) for x in raw[:4]])
        for slot in range(6):
            p, n = raw[4 + 2 * slot], raw[5 + 2 * slot]
            print(f"  slot {slot}: count {n}")


main()
