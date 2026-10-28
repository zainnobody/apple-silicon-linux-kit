#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Build AVE DPE tunable files for macOS 26 sets from a local kernelcache.

Same table format as upstream ave_fwgen.py (AVEDPE01). Differences: LZFSE via
libcompression and the macOS 26 symbol prefix `gsc_s`. Output goes to a folder
you name (keep it outside the repository: the files hold Apple register data).
  python3 -I dpe_build.py UPSTREAM_DIR KERNELCACHE OUTDIR SET...
Controls: Atlas_8112 must give 1/124/123 entries (docs/90) and Castor_6000
must equal the 13.5 file if one is passed with --compare.
"""
import hashlib
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dpe_probe_lib as P  # noqa: E402


def tables(f, kc, setname):
    syms = kc.symbols(kc.kext(f.KEXT))
    want = "gsc_sAVE_DPE_CfgSet_" + setname
    hits = [va for n, va in syms.items() if n.endswith(want) and n[:-len(want)].lstrip("_ZL0123456789") == ""]
    if len(hits) != 1:
        raise SystemExit(f"{len(hits)} symbols for {want}")
    o = kc.off(hits[0], 0x80)
    hdr = struct.unpack_from("<4Q", kc.d, o)
    if (hdr[0] & 0xFFFFFFFF) != f.DPE_CAT_BASE or (hdr[2] & 0xFFFFFFFF) != f.DPE_CAC_BASE:
        raise SystemExit(f"{want}: unexpected window header")
    out = {}
    for key, slot in f.DPE_SLOTS:
        raw, n = struct.unpack_from("<QQ", kc.d, o + 0x20 + 16 * slot)
        ents = []
        if n:
            to = kc.off(kc.pointer(raw), 16 * n)
            for i in range(n):
                off, width, clear, value = struct.unpack_from("<4I", kc.d, to + 16 * i)
                if width != 4 or off & 3 or off >= 0x1000:
                    raise SystemExit(f"{want}: {key}[{i}] = {off:#x}/{width} not a 32-bit register")
                ents.append((off, clear, value))
        out[key] = ents
    return out


def main():
    up, kcpath, outdir, sets = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
    f = P.load_fwgen(up)
    f.lzfse_decode = P.lzfse_native
    kc = f.Kernelcache(f.kernelcache_macho(open(kcpath, "rb").read()))
    os.makedirs(outdir, exist_ok=True)
    allt = {}
    for s in sets:
        t = tables(f, kc, s)
        allt[s] = t
        blob = f.dpe_encode(t)
        path = os.path.join(outdir, f"ave-26.7-dpe-{s.lower()}.bin")
        open(path, "wb").write(blob)
        print(s, {k: len(v) for k, v in t.items()}, len(blob), "bytes sha256", hashlib.sha256(blob).hexdigest()[:16])
    names = list(allt)
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            a, b = allt[names[i]], allt[names[j]]
            for k in a:
                same = sum(1 for x in a[k] if x in b[k])
                print(f"  {names[i]} vs {names[j]} {k}: {same} of {len(a[k])}/{len(b[k])} entries equal")


main()
