#!/usr/bin/env bash
# x86 desktop: Terminal -> `ling eval` a one-liner that opens a window and the
# in-app file dialog over home/live/Scripts, screendump the dialog, pick the
# first entry with Enter, and show what the program printed.
set -uo pipefail
OUT=$(cd "$(dirname "$0")" && pwd)/out
W=/tmp/x86dlg; rm -rf $W; mkdir -p $W/iso/boot/grub
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
      '"') k shift-apostrophe 0.12 ;; '(') k shift-9 0.12 ;; ')') k shift-0 0.12 ;; ',') k comma 0.12 ;;
      '{') k shift-bracket_left 0.12 ;; '}') k shift-bracket_right 0.12 ;; '=') k equal 0.12 ;;
      [A-Z]) k "shift-$(printf '%s' "$c" | tr 'A-Z' 'a-z')" 0.12 ;;
      *) k "$c" 0.12 ;;
    esac
  done
}
{
  sleep 25; k ret 8; k n 8
  k meta_l 2; k down 0.4; k down 0.4; k down 0.4; k ret 4
  type_str 'ling eval bind main = do { open_window(640, 480, "dialog test", 1) print(dlg_open("Pick a script", "ling", "home/live/Scripts")) }'; k ret 6
  echo "screendump $W/e1.ppm"; sleep 1
  k down 1; echo "screendump $W/e2.ppm"; sleep 1
  k ret 5
  echo "screendump $W/e3.ppm"; sleep 1
  echo quit
} | timeout 180 qemu-system-x86_64 -cdrom $W/t.iso -drive file=$W/disk.img,format=raw,if=ide,index=0,cache=writethrough \
    -serial file:$W/serial.log -display none -monitor stdio -m 1G -cpu max -vga std >/dev/null 2>&1
for f in e1 e2 e3; do [ -f $W/$f.ppm ] && ffmpeg -y -loglevel error -i $W/$f.ppm $OUT/x86dlg-$f.png && echo "$f ok"; done
tr -d '\000\r' < $W/serial.log | grep -iE "panic|exception|dialog|home/live" | head
