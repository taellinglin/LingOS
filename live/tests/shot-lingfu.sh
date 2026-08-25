#!/usr/bin/env bash
# THE package-manager end-to-end test: a real HTTP server on the host
# serves catalog.txt + a real .lpkg; the guest's lingfu syncs the catalog,
# downloads the package over its own TCP stack, unpacks, and `cat`s an
# installed file. Every byte crosses the emulated wire.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)/out"; mkdir -p "$DIR"
ISO=/mnt/c/Users/User/Programs/LingOS/dist/lingos-x86_64.iso
DISK=/mnt/c/Users/User/Programs/LingOS/dist/lingos-test-disk.img

cd "$(dirname "$DIR")/repo"
python3 -m http.server 8000 --bind 127.0.0.1 >/dev/null 2>&1 &
SRV=$!
trap "kill $SRV 2>/dev/null" EXIT
sleep 1

type_line() {
    # fold+read preserves spaces (a bare for-loop word-splits them away).
    echo "$1" | fold -w1 | while IFS= read -r c; do
        case "$c" in
            " ") c=spc ;;
            "-") c=minus ;;
            "/") c=slash ;;
            ".") c=dot ;;
        esac
        echo "sendkey $c"
        sleep 0.3
    done
    echo "sendkey ret"
}

{
    sleep 4
    echo "sendkey down"; sleep 0.4
    echo "sendkey down"; sleep 0.4
    echo "sendkey down"; sleep 0.4
    echo "sendkey ret"           # Rescue
    sleep 14
    type_line "lingfu sync"
    sleep 8
    type_line "lingfu install hello-ling"
    sleep 10
    type_line "cat pkg-hello-ling/hello.txt"
    sleep 4
    echo "quit"
} | qemu-system-x86_64 \
    -boot d \
    -cdrom "$ISO" \
    -drive file="$DISK",format=raw,if=ide,index=0 \
    -serial file:"$DIR/serial-lingfu.log" \
    -object filter-dump,id=fd0,netdev=n0,file="$DIR/lingfu.pcap" \
    -netdev user,id=n0 -device e1000,netdev=n0 \
    -display none -monitor stdio -m 256M >/dev/null 2>&1

echo "--- serial transcript ---"
grep -aE "lingfu|Hello|catalog|installed|hello" "$DIR/serial-lingfu.log" | head -25
echo "--- wire ---"
python3 - "$DIR/lingfu.pcap" <<'EOF'
import struct, sys
f = open(sys.argv[1],'rb').read()
off = 24; i = 0
while off + 16 <= len(f) and i < 14:
    ts, tus, caplen, length = struct.unpack('<IIII', f[off:off+16])
    fr = f[off+16:off+16+caplen]
    et = fr[12:14].hex()
    desc = 'arp' if et == '0806' else ('ip' if et == '0800' else et)
    extra = ''
    if desc == 'ip' and len(fr) > 34 and fr[23] == 6:
        flags = fr[14+20+13]
        extra = f' tcp flags=0x{flags:02x} sport={int.from_bytes(fr[34:36],"big")} dport={int.from_bytes(fr[36:38],"big")} len={caplen}'
    print(f'frame {i}: {desc}{extra}')
    off += 16 + caplen; i += 1
EOF
