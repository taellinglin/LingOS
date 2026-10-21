"""A 64 MiB SD card image for QEMU's raspi3b: an MBR with one FAT-type
partition (LBA 2048, 16 MiB) and free space after it for lingfs."""
import os, struct, sys
out = sys.argv[1]
img = bytearray(256 * 1024 * 1024)
img[446:462] = bytes([0x80, 0, 0, 0, 0x0C, 0, 0, 0]) + struct.pack("<II", 2048, 32768)
img[510] = 0x55
img[511] = 0xAA
img[2048 * 512:2048 * 512 + 3] = b"\xEB\x3C\x90"  # a boot-sector-looking start, not blank
open(out, "wb").write(img)
print("wrote", out, len(img), "bytes")
