#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Print the .text_win initialiser (three 16 KiB TEXT windows, sha256) for a firmware Mach-O. Read only.
Windows: TEXT+0, TEXT+0x80000 and the last 16 KiB, as in the upstream rows (TEXT 0xd0000 -> 0xcc000).
  python3 -I text_win.py IMAGE.macho
"""
import hashlib
import struct
import sys

d = open(sys.argv[1], "rb").read()
ncmds = struct.unpack_from("<I", d, 16)[0]
off = 32
for _ in range(ncmds):
    cmd, size = struct.unpack_from("<II", d, off)
    if cmd == 0x19 and d[off + 8:off + 14] == b"__TEXT":
        va, vs, fo, fs = struct.unpack_from("<QQQQ", d, off + 24)
        break
    off += size
W = 0x4000
print("\t.text_win = {")
for o in (0, 0x80000, fs - W):
    dig = hashlib.sha256(d[fo + o:fo + o + W]).digest()
    print(f"\t\t{{ {o:#x}, {{")
    for i in range(0, 32, 8):
        print("\t\t\t" + ", ".join(f"0x{b:02x}" for b in dig[i:i + 8]) + ",")
    print("\t\t} },")
print("\t},")
