# Reborn / T001 - deterministic test image generator (vision capability probe)
#
# Purpose: produce a small PNG whose content is known exactly, so that the
# visual-analysis tool (E:/claude-vision-skill/vision.js) can be verified with a
# question whose correct answer is already known. This proves the vision path is
# usable for later acceptance evidence (T005/T006 proportions, M01/M02 behaviour).
#
# Usage:
#   python E:\Reborn\Tools\Probes\make_probe_image.py

import struct
import zlib
import os

OUT = r"E:\Reborn\Art\Probes\vision_probe_red_blue.png"
W, H = 64, 32


def chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


# Left half pure red (255,0,0), right half pure blue (0,0,255).
rows = bytearray()
for _y in range(H):
    rows.append(0)  # PNG filter type 0 (None) per scanline
    for x in range(W):
        rows += b"\xff\x00\x00" if x < W // 2 else b"\x00\x00\xff"

png = (
    b"\x89PNG\r\n\x1a\n"
    + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    + chunk(b"IEND", b"")
)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "wb") as fh:
    fh.write(png)

print("WROTE {0} ({1} bytes) {2}x{3} left=red right=blue".format(OUT, len(png), W, H))
