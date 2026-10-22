#!/usr/bin/env bash
# Pi desktop in QEMU raspi3b over serial: start menu -> console, then
# `ling run home/ling/Graphics/gfx.ling`, screendump, Ctrl+Q, `exit`.
SP=/tmp/pigfx
OUT=$(cd "$(dirname "$0")" && pwd)/out
KIMG=/mnt/c/Users/User/Programs/LingOS/dist-lsx/rpi/kernel8.img
BOOT=${1:-35}
rm -rf $SP; mkdir -p $SP; mkfifo $SP/ser.in $SP/ser.out
cat $SP/ser.out > $SP/serial.log &
exec 3<>$SP/ser.in
( sleep $BOOT; printf '\033' >&3; sleep 4
  printf '\033[B' >&3; sleep 1; printf '\033[B' >&3; sleep 1; printf '\033[B' >&3; sleep 1; printf '\033[B' >&3; sleep 1; printf '\033[B' >&3; sleep 1
  printf '\r' >&3; sleep 6
  printf 'ling run home/ling/Graphics/gfx.ling\r' >&3; sleep 12; echo "screendump $SP/g1.ppm"; sleep 1
  printf '\021' >&3; sleep 5; echo "screendump $SP/g2.ppm"; sleep 1
  printf 'exit\r' >&3; sleep 5; echo quit ) \
  | timeout $((BOOT + 60)) qemu-system-aarch64 -M raspi3b -kernel "$KIMG" \
      -chardev pipe,id=s0,path=$SP/ser -serial chardev:s0 -monitor stdio -vnc 127.0.0.1:4 >/dev/null 2>&1
for f in g1 g2; do [ -f $SP/$f.ppm ] && ffmpeg -y -loglevel error -i $SP/$f.ppm $OUT/pigfx-$f.png && echo "$f ok"; done
tr -d '\000\r' < $SP/serial.log | grep -v "daw_\|ui_" | sed -n '/ling run/,$p' | head -12
