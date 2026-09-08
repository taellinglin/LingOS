#!/usr/bin/env bash
# Assemble the disk-boot payload: stage1 (MBR) + stage2 + a small kernel
# header + the flattened Live kernel image, laid out exactly as
# bootloader/stage1.asm and stage2.asm expect (see their header comments)
# and matching ling-kernel/src/lingfs.rs's LINGFS_BASE_LBA reservation.
#
# Run under WSL (needs nasm, objcopy, python3). Does NOT invoke ling.exe —
# run live/build-iso-x86_64.ps1 (or ling.exe build) first so
# dist/kernel/lingos-kernel-x86_64 exists.
#
# The installer can't read this file directly off the ISO (no ISO9660
# driver in the kernel) -- instead grub.cfg loads it as a Multiboot2
# *module* alongside the installer kernel, which hands the installer a
# plain (address, size) pointer to it already sitting in RAM. This script
# only needs to produce the file and get it onto the ISO; live/grub.cfg's
# `module2` line is what actually gets it into the installer's hands.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINGOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOT_DIR="$LINGOS_ROOT/bootloader"
DIST_DIR="$LINGOS_ROOT/dist"
WORK_DIR="$DIST_DIR/.diskboot-work"
OUT="$DIST_DIR/diskboot-x86_64.img"

# Installed disks boot the graphics DESKTOP kernel now (login greeter ->
# WM/DE), not the text shell: stage2 sets a VBE mode and leaves its LFB
# handoff block, and kernel/x86_64-wm's main.ling shows the greeter when
# ling_kernel_boot_is_disk() reports the no-Multiboot2 path. The text
# kernel remains reachable via the Live ISO's Rescue entry.
KERNEL_ELF="$DIST_DIR/kernel/lingos-wm-x86_64"
if [ ! -f "$KERNEL_ELF" ]; then
    echo "error: expected kernel ELF not found at $KERNEL_ELF" >&2
    echo "  build it first: ling.exe build kernel/x86_64-wm --platform kernel --out dist" >&2
    exit 1
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

echo "==> assembling stage1/stage2"
nasm -f bin "$BOOT_DIR/stage1.asm" -o "$WORK_DIR/stage1.bin"
nasm -f bin "$BOOT_DIR/stage2.asm" -o "$WORK_DIR/stage2.bin"
[ "$(stat -c%s "$WORK_DIR/stage1.bin")" = "512" ] || { echo "error: stage1.bin isn't exactly 512 bytes" >&2; exit 1; }
[ "$(stat -c%s "$WORK_DIR/stage2.bin")" = "8192" ] || { echo "error: stage2.bin isn't exactly 8192 bytes" >&2; exit 1; }

echo "==> flattening kernel ELF"
objcopy -O binary "$KERNEL_ELF" "$WORK_DIR/kernel.bin"
FLAT_SIZE=$(stat -c%s "$WORK_DIR/kernel.bin")

echo "==> extracting entry point + true (.bss-inclusive) memory footprint"
ELF_INFO=$(python3 "$BOOT_DIR/elf_info.py" "$KERNEL_ELF")
ENTRY=$(echo "$ELF_INFO" | grep '^entry=' | cut -d= -f2)
MEM_END=$(echo "$ELF_INFO" | grep '^mem_end=' | cut -d= -f2)

LINK_BASE=0x100000
MEM_SIZE=$((MEM_END - LINK_BASE))
BSS_EXTRA=$((MEM_SIZE - FLAT_SIZE))
if [ "$BSS_EXTRA" -lt 0 ]; then
    echo "error: computed negative bss_extra ($BSS_EXTRA) -- flat file bigger than ELF's own memory footprint?" >&2
    exit 1
fi
FILE_SIZE_SECTORS=$(( (FLAT_SIZE + 511) / 512 ))

# The kernel image loads contiguously from KERNEL_START_LBA (18); the lingfs
# volume begins at LINGFS_BASE_LBA. If the kernel spills into that region the
# two overlap on disk and installs corrupt each other's data (this once wiped
# user accounts). Keep this value in sync with objects.rs::LINGFS_BASE_LBA.
KERNEL_START_LBA=18
LINGFS_BASE_LBA=32768
KERNEL_END_LBA=$(( KERNEL_START_LBA + FILE_SIZE_SECTORS ))
if [ "$KERNEL_END_LBA" -ge "$LINGFS_BASE_LBA" ]; then
    echo "error: kernel image ends at LBA $KERNEL_END_LBA but lingfs starts at $LINGFS_BASE_LBA -- they OVERLAP." >&2
    echo "       Shrink the kernel (embedded assets?) or raise LINGFS_BASE_LBA in objects.rs + here." >&2
    exit 1
fi

echo "    entry=$ENTRY  flat_size=$FLAT_SIZE  mem_end=$MEM_END  bss_extra=$BSS_EXTRA  sectors=$FILE_SIZE_SECTORS  (kernel LBA 18..$KERNEL_END_LBA, lingfs @ $LINGFS_BASE_LBA)"

echo "==> building header sector"
python3 "$BOOT_DIR/pack_header.py" "$FILE_SIZE_SECTORS" "$ENTRY" "$BSS_EXTRA" "$WORK_DIR/header.bin"

echo "==> padding kernel image to a sector boundary"
PADDED_SIZE=$((FILE_SIZE_SECTORS * 512))
cp "$WORK_DIR/kernel.bin" "$WORK_DIR/kernel_padded.bin"
truncate -s "$PADDED_SIZE" "$WORK_DIR/kernel_padded.bin"

echo "==> concatenating diskboot image"
cat "$WORK_DIR/stage1.bin" "$WORK_DIR/stage2.bin" "$WORK_DIR/header.bin" "$WORK_DIR/kernel_padded.bin" > "$OUT"

echo "==> wrote $OUT ($(stat -c%s "$OUT") bytes)"
