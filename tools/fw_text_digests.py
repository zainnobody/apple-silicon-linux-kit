#!/usr/bin/env python3
"""Digests of a dumped GPU firmware TEXT image (T6030, 0x5c000 bytes).

Usage: python3 -I fw_text_digests.py DUMP [--expect HEX] [--save-patchbay FILE]
       python3 -I fw_text_digests.py --self-test

Reads the image-info header at 0x4200, finds the single GKTS marker, and prints:
  full      SHA-256 with only the 8 entropy bytes after the marker zeroed (the kernel's digest)
  masked    SHA-256 with the whole patchbay [off, off+size) zeroed
  premarker SHA-256 of TEXT[0:marker]
  patchbay  SHA-256 of the patchbay bytes (the bytes themselves stay local)
"""
import argparse, hashlib, struct, sys

TEXT_SIZE = 0x5C000
HDR_OFF = 0x4200
MARKER = b"GKTS\x08\x00\x00\x00"


def sha(b):
    return hashlib.sha256(b).hexdigest()


def analyse(text):
    if len(text) != TEXT_SIZE:
        raise SystemExit(f"bad size {len(text):#x}, need {TEXT_SIZE:#x}")
    w = struct.unpack_from("<14I", text, HDR_OFF)
    if w[0] != 0x14000011 or w[1] != 0x64697575 or w[2] != 5:
        raise SystemExit("image-info header not found at 0x4200")
    uuid = text[HDR_OFF + 0x14:HDR_OFF + 0x24]
    pb_off, pb_size, tsize = w[11], w[12], w[13]
    if tsize != len(text):
        raise SystemExit("header text size differs from dump size")
    hits = [o for o in range(0, len(text) - 15, 8) if text[o:o + 8] == MARKER]
    if len(hits) != 1:
        raise SystemExit(f"need exactly one GKTS marker, found {len(hits)}")
    at = hits[0]
    full = bytearray(text); full[at + 8:at + 16] = bytes(8)
    masked = bytearray(text); masked[pb_off:pb_off + pb_size] = bytes(pb_size)
    return {
        "uuid": "%s-%s-%s-%s-%s" % tuple(uuid.hex()[i:j] for i, j in
                                         ((0, 8), (8, 12), (12, 16), (16, 20), (20, 32))),
        "patchbay": (pb_off, pb_size),
        "marker": at,
        "marker_in_patchbay": pb_off <= at and at + 16 <= pb_off + pb_size,
        "full": sha(bytes(full)),
        "masked": sha(bytes(masked)),
        "premarker": sha(text[:at]),
        "patchbay_sha": sha(text[pb_off:pb_off + pb_size]),
        "patchbay_bytes": text[pb_off:pb_off + pb_size],
    }


def synthetic(patch=None, outside=None):
    t = bytearray(TEXT_SIZE)
    struct.pack_into("<14I", t, HDR_OFF, 0x14000011, 0x64697575, 5, 0, 0, 0, 0, 0, 0, 0, 0,
                     0x58E88, 0x1E8, TEXT_SIZE)
    t[HDR_OFF + 0x14:HDR_OFF + 0x24] = bytes(range(16))
    t[0x58E88:0x58E90] = MARKER
    for i in range(0x58E98, 0x59070):
        t[i] = (i * 7) & 0xFF
    if patch is not None:
        t[patch] ^= 1
    if outside is not None:
        t[outside] ^= 1
    return bytes(t)


def self_test():
    base = analyse(synthetic())
    assert base["marker_in_patchbay"]
    ent = bytearray(synthetic()); ent[0x58E91] ^= 0xFF  # entropy bytes are 0x58E88+8..+16
    r = analyse(bytes(ent))
    assert r["full"] == base["full"] and r["masked"] == base["masked"]
    p = analyse(synthetic(patch=0x59000))          # inside patchbay, outside entropy
    assert p["full"] != base["full"] and p["masked"] == base["masked"]
    o = analyse(synthetic(outside=0x1000))         # code byte
    assert o["full"] != base["full"] and o["masked"] != base["masked"]
    o2 = analyse(synthetic(outside=0x5B000))       # after the patchbay
    assert o2["masked"] != base["masked"]
    print("self-test ok")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump", nargs="?")
    ap.add_argument("--expect")
    ap.add_argument("--save-patchbay")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    if not a.dump:
        ap.error("DUMP required")
    r = analyse(open(a.dump, "rb").read())
    print("uuid      ", r["uuid"])
    print("patchbay   %#x+%#x  marker %#x (inside: %s)" % (*r["patchbay"], r["marker"],
                                                          r["marker_in_patchbay"]))
    for k in ("full", "masked", "premarker", "patchbay_sha"):
        print("%-10s %s" % (k, r[k]))
    if a.save_patchbay:
        open(a.save_patchbay, "wb").write(r["patchbay_bytes"])
    if a.expect:
        ok = r["full"].startswith(a.expect.lower())
        print("check full digest vs expected:", "MATCH" if ok else "MISMATCH, dump is not valid")
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
