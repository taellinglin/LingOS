#!/usr/bin/env bash
# x86 desktop: Terminal -> `ling eval` of http_get over HTTPS to the registry,
# http_get_status and net_test (needs -cpu max: RDRAND for TLS).
set -uo pipefail
OUT=$(cd "$(dirname "$0")" && pwd)/out
W=/tmp/x86net; rm -rf $W; mkdir -p $W/iso/boot/grub
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
      ':') k shift-semicolon 0.12 ;; '?') k shift-slash 0.12 ;;
      [A-Z]) k "shift-$(printf '%s' "$c" | tr 'A-Z' 'a-z')" 0.12 ;;
      *) k "$c" 0.12 ;;
    esac
  done
}
{
  sleep 25; k ret 8; k n 8
  k meta_l 2; k down 0.4; k down 0.4; k down 0.4; k ret 4
  type_str 'ling eval bind main = do { print(http_get("https://fu.ling-lang.org/api/package?name=bob-hello")) print(http_get_status()) print(net_test(7777)) }'; k ret 50
  echo "screendump $W/n1.ppm"; sleep 1
  echo quit
} | timeout 200 qemu-system-x86_64 -cdrom $W/t.iso -drive file=$W/disk.img,format=raw,if=ide,index=0,cache=writethrough \
    -serial file:$W/serial.log -display none -monitor stdio -m 1G -cpu max -vga std -nic user,model=e1000 >/dev/null 2>&1
[ -f $W/n1.ppm ] && ffmpeg -y -loglevel error -i $W/n1.ppm $OUT/x86net-n1.png && echo "n1 ok"
tr -d '\000\r' < $W/serial.log | grep -a -E 'panic|exception|bob-hello|checksum|TCP bind|tls:|\[http\]|^[0-9]{3}$' | head -20
