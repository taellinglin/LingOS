#!/usr/bin/env python3
"""Build the 512-byte on-disk kernel header stage2.asm reads from LBA 17:
magic, file_size_sectors, entry_phys, bss_extra_bytes (all u32 LE), then
zero-padded to a full sector. See stage2.asm's header_buf layout.

Usage: pack_header.py <file_size_sectors> <entry_phys> <bss_extra> <out_path>
(numbers may be decimal or 0x-prefixed hex)
"""
import struct
import sys

MAGIC = 0x474E4B4C


def parse_int(s: str) -> int:
    return int(s, 0)


def main() -> int:
    file_size_sectors = parse_int(sys.argv[1])
    entry_phys = parse_int(sys.argv[2])
    bss_extra = parse_int(sys.argv[3])
    out_path = sys.argv[4]

    header = struct.pack("<IIII", MAGIC, file_size_sectors, entry_phys, bss_extra)
    header += b"\x00" * (512 - len(header))
    with open(out_path, "wb") as f:
        f.write(header)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
