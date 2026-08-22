#!/usr/bin/env bash
# Wrap an already-built LingOS x86_64 kernel ELF in a bootable GRUB
# (Multiboot2) ISO. Run under WSL (needs grub-mkrescue, xorriso, mtools).
#
# This script only does the packaging step — it does NOT invoke ling.exe
# itself. WSL interop for executing Windows .exe files isn't reliable in
# every distro (confirmed broken in this repo's WSL Arch install: it fails
# with "cannot execute binary file"), so the kernel build runs natively on
# Windows instead (see build-iso-x86_64.ps1, which does both steps).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINGOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$LINGOS_ROOT/dist"
ISO_ROOT="$SCRIPT_DIR/.isoroot-x86_64"
ISO_OUT="$DIST_DIR/lingos-x86_64.iso"

LIVE_ELF="$DIST_DIR/kernel/lingos-kernel-x86_64"
INSTALLER_ELF="$DIST_DIR/kernel/lingos-installer-x86_64"
WM_ELF="$DIST_DIR/kernel/lingos-wm-x86_64"
for f in "$LIVE_ELF" "$INSTALLER_ELF" "$WM_ELF"; do
    if [ ! -f "$f" ]; then
        echo "error: expected kernel ELF not found at $f" >&2
        echo "  build all three first (from Windows): live/build-iso-x86_64.ps1, or:" >&2
        echo "  ling.exe build kernel/x86_64 --platform kernel --out dist" >&2
        echo "  ling.exe build kernel/x86_64-installer --platform kernel --out dist" >&2
        echo "  ling.exe build kernel/x86_64-wm --platform kernel --out dist" >&2
        exit 1
    fi
done

echo "==> building disk-boot payload (bootloader + flattened Live kernel)"
"$SCRIPT_DIR/build-diskboot-x86_64.sh"

echo "==> assembling GRUB ISO (Live + Install + Desktop menu entries)"
rm -rf "$ISO_ROOT"
mkdir -p "$ISO_ROOT/boot/grub"
cp "$LIVE_ELF" "$ISO_ROOT/boot/lingos-x86_64.elf"
cp "$INSTALLER_ELF" "$ISO_ROOT/boot/lingos-installer-x86_64.elf"
cp "$WM_ELF" "$ISO_ROOT/boot/lingos-wm-x86_64.elf"
cp "$DIST_DIR/diskboot-x86_64.img" "$ISO_ROOT/boot/diskboot.img"
cp "$SCRIPT_DIR/grub.cfg" "$ISO_ROOT/boot/grub/grub.cfg"

mkdir -p "$DIST_DIR"
grub-mkrescue -o "$ISO_OUT" "$ISO_ROOT"

echo "==> wrote $ISO_OUT"
echo "    test in QEMU:       live/run-qemu-x86_64.ps1"
echo "    test in VirtualBox: attach $ISO_OUT as an optical drive (BIOS mode, not EFI) and boot"
