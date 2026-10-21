#!/usr/bin/env bash
# x86 desktop: Terminal -> `lingfu install <pkg>` from fu.ling-lang.org over
# QEMU user networking -> `ls pkg-<pkg>` -> `ling run pkg-<pkg>` on the
# in-kernel interpreter. Needs `-cpu max`: the kernel's TLS takes its entropy
# from RDRAND, which QEMU's default CPU model lacks (DNS + TCP connect then
# succeed but no ClientHello is ever sent: "could not reach the registry").
# The packet capture is decoded by pcap-summary.py next to this script.
set -uo pipefail
OUT=$(cd "$(dirname "$0")" && pwd)/out; mkdir -p "$OUT"
PKG=${1:-bob-hello}
W=/tmp/x86lingfu; rm -rf $W; mkdir -p $W/iso/boot/grub
cp /mnt/c/Users/User/Programs/LingOS/dist/kernel/lingos-wm-x86_64 $W/iso/boot/wm.elf
printf 'set timeout=0\nmenuentry "Live" {\n multiboot2 /boot/wm.elf\n boot\n}\n' > $W/iso/boot/grub/grub.cfg
grub-mkrescue -o $W/t.iso $W/iso >/dev/null 2>&1 || { echo "grub-mkrescue failed"; exit 1; }
truncate -s 128M $W/disk.img
k() { echo "sendkey $1"; sleep ${2:-0.5}; }
type_str() {
  local s="$1" i c
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      ' ') k spc 0.12 ;; '/') k slash 0.12 ;; '.') k dot 0.12 ;; '-') k minus 0.12 ;; '_') k shift-minus 0.12 ;;
      [A-Z]) k "shift-$(printf '%s' "$c" | tr 'A-Z' 'a-z')" 0.12 ;;
      *) k "$c" 0.12 ;;
    esac
  done
}
{
  sleep 25; k ret 8; k n 8
  k meta_l 2; k down 0.4; k down 0.4; k down 0.4; k ret 4
  type_str "lingfu install $PKG"; k ret 30
  echo "screendump $W/p1.ppm"; sleep 1
  type_str "ls pkg-$PKG"; k ret 3
  type_str "ling run pkg-$PKG"; k ret 8
  echo "screendump $W/p2.ppm"; sleep 1
  echo quit
} | timeout 220 qemu-system-x86_64 -cdrom $W/t.iso -drive file=$W/disk.img,format=raw,if=ide,index=0,cache=writethrough \
    -serial file:$W/serial.log -display none -monitor stdio -m 1G -cpu max -vga std \
    -object filter-dump,id=fd0,netdev=n0,file=$W/net.pcap -netdev user,id=n0 -device e1000,netdev=n0 >/dev/null 2>&1
for f in p1 p2; do [ -f $W/$f.ppm ] && ffmpeg -y -loglevel error -i $W/$f.ppm "$OUT/lingfu-registry-$f.png" && echo "$f ok"; done
echo "=== wire (DNS / TCP / TLS record types) ==="
python3 "$(dirname "$0")/pcap-summary.py" $W/net.pcap | grep -v "udp 10.0.2.15:41337\|proto=1 127.0.0.1\|arp$" | head -40
