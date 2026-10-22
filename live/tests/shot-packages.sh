#!/usr/bin/env bash
# x86 desktop: Applications -> Packages: catalog sync, Tab to all, install
# bob-hello (2nd row), Enter again runs it in the Terminal, then the menu
# shows it as an installed app.
set -uo pipefail
OUT=$(cd "$(dirname "$0")" && pwd)/out
W=/tmp/x86pkgs; rm -rf $W; mkdir -p $W/iso/boot/grub
cp /mnt/c/Users/User/Programs/LingOS/dist/kernel/lingos-wm-x86_64 $W/iso/boot/wm.elf
printf 'set timeout=0\nmenuentry "Live" {\n multiboot2 /boot/wm.elf\n boot\n}\n' > $W/iso/boot/grub/grub.cfg
grub-mkrescue -o $W/t.iso $W/iso >/dev/null 2>&1 || { echo "grub-mkrescue failed"; exit 1; }
truncate -s 128M $W/disk.img
k() { echo "sendkey $1"; sleep ${2:-0.5}; }
{
  sleep 25; k ret 8; k n 8
  k meta_l 2; for i in 1 2 3 4 5 6 7 8 9 10; do k down 0.5; done
  echo "screendump $W/k0.ppm"; sleep 1
  k ret 25
  echo "screendump $W/k1.ppm"; sleep 1
  k tab 2; echo "screendump $W/k2.ppm"; sleep 1
  k down 1; k ret 90
  echo "screendump $W/k3.ppm"; sleep 1
  k ret 8
  echo "screendump $W/k4.ppm"; sleep 1
  k meta_l 3
  echo "screendump $W/k5.ppm"; sleep 1
  echo quit
} | timeout 320 qemu-system-x86_64 -cdrom $W/t.iso -drive file=$W/disk.img,format=raw,if=ide,index=0,cache=writethrough \
    -serial file:$W/serial.log -display none -monitor stdio -m 1G -cpu max -vga std -nic user,model=e1000 >/dev/null 2>&1
for f in k0 k1 k2 k3 k4 k5; do [ -f $W/$f.ppm ] && ffmpeg -y -loglevel error -i $W/$f.ppm $OUT/x86pkgs-$f.png && echo "$f ok"; done
tr -d '\000\r' < $W/serial.log | grep -a -E 'panic|exception|lingfu|hi from bob' | head
