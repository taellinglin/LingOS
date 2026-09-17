#!/usr/bin/env python3
"""Hand-rolled 8-bit RGB PNG encoder (no Pillow dependency) -- a small
four-color quadrant image, easy to eyeball-verify in a low-res screendump
once horizon-browser decodes and scales it."""

import struct
import zlib

W, H = 64, 48
QUADRANTS = [
    (0xE8, 0x3E, 0x3E),  # red: top-left
    (0x3E, 0xC8, 0x5A),  # green: top-right
    (0x3E, 0x7A, 0xE8),  # blue: bottom-left
    (0xF0, 0xC8, 0x2A),  # yellow: bottom-right
]


def pixel(x, y):
    q = (0 if x < W // 2 else 1) + (0 if y < H // 2 else 2)
    return QUADRANTS[q]


def chunk(tag, data):
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


raw = bytearray()
for y in range(H):
    raw.append(0)  # filter type: none
    for x in range(W):
        raw.extend(pixel(x, y))

png = bytearray(b"\x89PNG\r\n\x1a\n")
png += chunk(
    b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)
)  # color type 2 = truecolor RGB
png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
png += chunk(b"IEND", b"")

with open("logo.png", "wb") as f:
    f.write(png)
print(f"wrote logo.png ({len(png)} bytes, {W}x{H})")
