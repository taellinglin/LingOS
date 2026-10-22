#!/usr/bin/env bash
# x86 desktop with a FAT32 image as the second IDE disk (media/disk1):
# Terminal cp / mkdir / mv / cat / rm on it, then the image is checked from
# the host with mtools (and fsck.vfat when available): the proof that what
# LingOS wrote is a valid FAT volume another machine will read.
set -uo pipefail
OUT=$(cd "$(dirname "$0")" && pwd)/out
W=/tmp/x86fat; rm -rf $W; mkdir -p $W/iso/boot/grub
cp /mnt/c/Users/User/Programs/LingOS/dist/kernel/lingos-wm-x86_64 $W/iso/boot/wm.elf
printf 'set timeout=0\nmenuentry "Live" {\n multiboot2 /boot/wm.elf\n boot\n}\n' > $W/iso/boot/grub/grub.cfg
grub-mkrescue -o $W/t.iso $W/iso >/dev/null 2>&1 || { echo "grub-mkrescue failed"; exit 1; }
truncate -s 128M $W/disk.img
# the stick: 64 MiB FAT32 superfloppy with one file on it
truncate -s 64M $W/fat.img
mformat -i $W/fat.img -F -v LINGSTICK :: || { echo "mformat failed"; exit 1; }
printf 'hello from the host\n' > $W/hello.txt
mcopy -i $W/fat.img $W/hello.txt ::hello.txt
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
  type_str "ls media"; k ret 2
  type_str "ls media/disk1"; k ret 3
  type_str "cp home/live/Scripts/fib.ling media/disk1"; k ret 4
  type_str "mkdir media/disk1/LongFolder-Name_Mixed"; k ret 3
  type_str "mv media/disk1/fib.ling media/disk1/LongFolder-Name_Mixed/fibonacci-korean.ling"; k ret 4
  type_str "cat media/disk1/LongFolder-Name_Mixed/fibonacci-korean.ling"; k ret 4
  type_str "rm media/disk1/hello.txt"; k ret 3
  type_str "cp media/disk1/LongFolder-Name_Mixed/fibonacci-korean.ling home/live/Documents/from-stick.ling"; k ret 4
  type_str "ls media/disk1"; k ret 3
  type_str "ls media/disk1/LongFolder-Name_Mixed"; k ret 3
  echo "screendump $W/f1.ppm"; sleep 1
  echo quit
} | timeout 200 qemu-system-x86_64 -cdrom $W/t.iso -drive file=$W/disk.img,format=raw,if=ide,index=0,cache=writethrough \
    -drive file=$W/fat.img,format=raw,if=ide,index=1,cache=writethrough \
    -serial file:$W/serial.log -display none -monitor stdio -m 1G -cpu max -vga std >/dev/null 2>&1
[ -f $W/f1.ppm ] && ffmpeg -y -loglevel error -i $W/f1.ppm $OUT/x86fat-f1.png && echo "f1 ok"
echo "=== serial: media lines ==="
tr -d '\000\r' < $W/serial.log | grep -a -E 'media:|panic|exception' | head
echo "=== host view of the stick afterwards (mtools) ==="
mdir -i $W/fat.img ::
mdir -i $W/fat.img "::LongFolder-Name_Mixed"
echo "--- fibonacci-korean.ling, first 3 lines ---"
mtype -i $W/fat.img "::LongFolder-Name_Mixed/fibonacci-korean.ling" | head -3
echo "--- fsck ---"
command -v fsck.vfat >/dev/null && fsck.vfat -n $W/fat.img || echo "(fsck.vfat not installed)"
