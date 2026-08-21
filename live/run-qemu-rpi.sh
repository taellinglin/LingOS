#!/usr/bin/env bash
# Boot the LingOS Raspberry Pi kernel in QEMU's raspi3b machine (the best-
# supported QEMU RPi model; there is no QEMU machine for real Pi 5/BCM2712
# hardware yet). Run under WSL (needs qemu-system-aarch64).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_IMG="${1:-$SCRIPT_DIR/../dist/rpi/kernel8.img}"

if [ ! -f "$KERNEL_IMG" ]; then
    echo "error: kernel8.img not found at $KERNEL_IMG — run build-sdcard-rpi.sh first" >&2
    exit 1
fi

exec qemu-system-aarch64 -M raspi3b -kernel "$KERNEL_IMG" -serial stdio -display none
