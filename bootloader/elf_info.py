#!/usr/bin/env python3
"""Extract exactly the two numbers stage2.asm needs from a linked kernel
ELF that a plain `objcopy -O binary` flatten can't preserve on its own:
the real entry point address, and the total in-memory footprint including
.bss (which the flat file doesn't include at all -- it's a trailing NOBITS
section with no file content, confirmed by testing).

Parses the ELF64 header/section table directly (not readelf's text output)
so this doesn't depend on any particular readelf version's formatting.

Usage: elf_info.py <elf-path>
Prints two lines: "entry=<hex>" and "mem_end=<hex>" (highest vaddr+size
across every SHF_ALLOC section) -- the caller computes bss_extra as
mem_end - link_base - flat_file_size.
"""

import struct
import sys

SHF_ALLOC = 0x2


def main() -> int:
    path = sys.argv[1]
    with open(path, "rb") as f:
        data = f.read()

    if data[:4] != b"\x7fELF":
        print("error: not an ELF file", file=sys.stderr)
        return 1
    ei_class = data[4]
    if ei_class != 2:
        print("error: not a 64-bit ELF", file=sys.stderr)
        return 1

    e_entry = struct.unpack_from("<Q", data, 24)[0]
    e_shoff = struct.unpack_from("<Q", data, 0x28)[0]
    e_shentsize = struct.unpack_from("<H", data, 0x3A)[0]
    e_shnum = struct.unpack_from("<H", data, 0x3C)[0]

    mem_end = 0
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        sh_flags = struct.unpack_from("<Q", data, off + 0x08)[0]
        sh_addr = struct.unpack_from("<Q", data, off + 0x10)[0]
        sh_size = struct.unpack_from("<Q", data, off + 0x20)[0]
        if sh_flags & SHF_ALLOC and sh_addr != 0:
            mem_end = max(mem_end, sh_addr + sh_size)

    print(f"entry={e_entry:#x}")
    print(f"mem_end={mem_end:#x}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
