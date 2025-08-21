#!/usr/bin/env python3
# Convert little-endian binary into $readmemh-compatible 32-bit word-per-line hex
import sys, struct
if len(sys.argv) != 3:
    print("usage: bin2hex.py in.bin out.hex"); sys.exit(1)
inp, outp = sys.argv[1], sys.argv[2]
data = open(inp, "rb").read()
# pad to multiple of 4
if len(data)%4 != 0:
    data += b"\x00"*(4 - (len(data)%4))
with open(outp, "w") as f:
    for i in range(0, len(data), 4):
        (word,) = struct.unpack("<I", data[i:i+4])
        f.write(f"{word:08x}\n")
