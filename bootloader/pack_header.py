#!/usr/bin/env python3
"""Build the 512-byte on-disk kernel header stage2.asm reads from LBA 17:
magic, file_size_sectors, entry_phys, bss_extra_bytes (all u32 LE), then a
display-mode preference byte at offset 16, then zero-padded to a sector.
See stage2.asm's header_buf layout.

The display byte is 0 (auto) at install time; the running system rewrites
just that byte via `ling_kernel_display_set` (Settings > Display) so the
choice survives reboots without disturbing the rest of the header. A
reinstall resets it to auto, which is correct.

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

    header = struct.pack("<IIIIB", MAGIC, file_size_sectors, entry_phys, bss_extra, 0)
    header += b"\x00" * (512 - len(header))
    with open(out_path, "wb") as f:
        f.write(header)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
