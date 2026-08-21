#!/usr/bin/env bash
# Boot the LingOS x86_64 live ISO in QEMU. Run under WSL (needs qemu-system-x86_64).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO="${1:-$SCRIPT_DIR/../dist/lingos-x86_64.iso}"

if [ ! -f "$ISO" ]; then
    echo "error: ISO not found at $ISO — run build-iso-x86_64.sh first" >&2
    exit 1
fi

# -nic user,model=e1000: explicit rather than relying on QEMU's
# version-dependent default NIC (recent QEMU defaults to e1000 on the PC
# target, but that's changed across versions before). The "user"/SLIRP
# backend does real NAT, so this also reaches the actual internet from
# inside the VM -- needed for anything past the driver/link-up self-test.
exec qemu-system-x86_64 -cdrom "$ISO" -serial stdio -m 256M -nic user,model=e1000
