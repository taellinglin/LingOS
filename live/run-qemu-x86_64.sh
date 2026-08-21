#!/usr/bin/env bash
# Boot the LingOS x86_64 live ISO in QEMU. Run under WSL (needs qemu-system-x86_64).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO="${1:-$SCRIPT_DIR/../dist/lingos-x86_64.iso}"
DISK="$SCRIPT_DIR/../dist/lingos-test-disk.img"

if [ ! -f "$ISO" ]; then
    echo "error: ISO not found at $ISO — run build-iso-x86_64.sh first" >&2
    exit 1
fi

# A real disk, explicitly on the primary IDE channel, is required: with no
# `-drive` at all, QEMU puts the `-cdrom` ATAPI device on that same primary
# channel — the one `ata.rs`'s PIO driver reads from — and an ATAPI drive
# doesn't answer a plain ATA READ SECTORS the way a PATA disk does, which
# left `lingfs mount` stuck well past its bounded per-poll timeout (dozens
# of polls during a first-boot format, each waiting out the full budget).
# Giving `-drive` its own explicit primary slot pushes the CD-ROM onto the
# secondary channel instead, which is also just the realistic config: a
# real installed system always has a real disk. Reused (not recreated)
# across runs, matching real media persisting between boots.
if [ ! -f "$DISK" ]; then
    echo "==> creating $DISK (64M scratch disk for lingfs)"
    truncate -s 64M "$DISK"
fi

exec qemu-system-x86_64 -cdrom "$ISO" -drive file="$DISK",format=raw,if=ide,index=0 -serial stdio -m 256M
