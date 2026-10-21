#!/usr/bin/env bash
# x86 desktop: Applications menu -> Terminal, then `ling demo`, `ling run` of
# the live user's fib.ling and spiral.ling (Esc quits), typed with sendkey.
set -uo pipefail
OUT=$(cd "$(dirname "$0")" && pwd)/out
W=/tmp/x86ling; rm -rf $W; mkdir -p $W/iso/boot/grub
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
  type_str "ling demo"; k ret 5
  echo "screendump $W/t1.ppm"; sleep 1
  type_str "ling run home/live/Scripts/fib.ling"; k ret 6
  echo "screendump $W/t2.ppm"; sleep 1
  type_str "ling run home/live/Graphics/spiral.ling"; k ret 12
  echo "screendump $W/t3.ppm"; sleep 1
  k esc 4
  echo "screendump $W/t4.ppm"; sleep 1
  echo quit
} | timeout 200 qemu-system-x86_64 -cdrom $W/t.iso -drive file=$W/disk.img,format=raw,if=ide,index=0,cache=writethrough \
    -serial file:$W/serial.log -display none -monitor stdio -m 1G -vga std >/dev/null 2>&1
for f in t1 t2 t3 t4; do [ -f $W/$f.ppm ] && ffmpeg -y -loglevel error -i $W/$f.ppm $OUT/x86ling-$f.png && echo "$f ok"; done
echo "=== serial: ling-related + errors ==="
tr -d '\000\r' < $W/serial.log | grep -iE "panic|exception|ling run|ling:|lingrt|fib|running in" | head -30
