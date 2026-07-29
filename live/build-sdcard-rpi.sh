#!/usr/bin/env bash
# Wrap an already-built LingOS Raspberry Pi kernel8.img in a bootable FAT32
# boot-partition image (config.txt + kernel8.img). Run under WSL (needs
# mtools). This script only does the packaging step — it does NOT invoke
# ling.exe itself; WSL's Windows-interop for executing .exe files isn't
# reliable in every distro (confirmed broken in this repo's WSL Arch
# install), so the kernel build runs natively on Windows instead (see
# build-sdcard-rpi.ps1, which does both steps).
#
# This image alone boots in QEMU (run-qemu-rpi.sh reads kernel8.img directly).
# For REAL Raspberry Pi hardware you additionally need the official RPi
# firmware blobs (bootcode.bin, start*.elf, fixup*.dat) copied onto the same
# FAT32 partition — fetch them yourself from the Raspberry Pi Foundation's
# public `firmware` repo to match your board's revision; they aren't bundled
# or auto-downloaded here.
#
# Also note: this targets the BCM2837/BCM2711-style memory map (Pi 3/4). Real
# Pi 5 (BCM2712 + the RP1 southbridge) uses a different peripheral layout and
# needs follow-up HAL work before it will boot on that specific board.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINGOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DIST_DIR="$LINGOS_ROOT/dist"
IMG_OUT="$DIST_DIR/lingos-rpi-boot.img"
IMG_SIZE_MB=64

KERNEL_IMG="$DIST_DIR/rpi/kernel8.img"
if [ ! -f "$KERNEL_IMG" ]; then
    echo "error: expected kernel8.img not found at $KERNEL_IMG" >&2
    echo "  build it first (from Windows): live/build-sdcard-rpi.ps1, or:" >&2
    echo "  ling.exe build kernel/rpi --platform rpi --out dist" >&2
    exit 1
fi

echo "==> assembling FAT32 boot partition image"
mkdir -p "$DIST_DIR"
rm -f "$IMG_OUT"
truncate -s "${IMG_SIZE_MB}M" "$IMG_OUT"
mformat -i "$IMG_OUT" -F ::

mcopy -i "$IMG_OUT" "$SCRIPT_DIR/config.txt" ::config.txt
mcopy -i "$IMG_OUT" "$KERNEL_IMG" ::kernel8.img

echo "==> wrote $IMG_OUT"
echo "    test in QEMU:  live/run-qemu-rpi.sh"
echo "    real hardware: add bootcode.bin/start*.elf/fixup*.dat to this image"
echo "                   (or to the SD card's boot partition) before flashing"
