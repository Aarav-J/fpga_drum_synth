#!/usr/bin/env python3
# Converts a flat binary firmware image into a $readmemh-compatible hex
# file: one 32-bit word per line, 8 hex digits, matching cpu_ram.v's
# 32-bit-wide memory array.
#
# RISC-V is little-endian, so 4 consecutive bytes in the binary represent
# a word with byte[0] as the LSB. $readmemh expects each line to spell out
# the word's numeric value in hex (most-significant digits first), so the
# byte order must be reversed when printing — this is the exact algorithm
# used by picorv32/firmware/makehex.py (public domain).
#
# Usage: python3 tools/makehex.py firmware.bin 1024 > firmware.hex

import sys

binfile = sys.argv[1]
nwords = int(sys.argv[2])

with open(binfile, "rb") as f:
    bindata = f.read()

assert len(bindata) <= 4 * nwords, (
    f"firmware ({len(bindata)} bytes) exceeds RAM capacity "
    f"({4 * nwords} bytes) — shrink the program or grow cpu_ram.v's WORDS"
)
assert len(bindata) % 4 == 0, "firmware binary is not word-aligned"

for i in range(nwords):
    if i < len(bindata) // 4:
        w = bindata[4 * i : 4 * i + 4]
        print("%02x%02x%02x%02x" % (w[3], w[2], w[1], w[0]))
    else:
        print("00000000")
