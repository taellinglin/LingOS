#!/usr/bin/env bash
# Boot the LingOS x86_64 live ISO in QEMU. Run under WSL (needs qemu-system-x86_64).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO="${1:-$SCRIPT_DIR/../dist/lingos-x86_64.iso}"

if [ ! -f "$ISO" ]; then
    echo "error: ISO not found at $ISO — run build-iso-x86_64.sh first" >&2
    exit 1
fi

exec qemu-system-x86_64 -cdrom "$ISO" -serial stdio -m 256M
