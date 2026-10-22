#!/usr/bin/env bash
# Pi desktop in QEMU raspi3b, driven over serial: start menu -> Console, then
# `ling demo`, `ling run` of the embedded fib.ling (Korean polyglot source) and
# of the spiral graphics program (Esc quits it), then `exit` back to the desktop.
# Console output fans out to serial, so the log is the primary check; the
# screendumps show the console / spiral window / desktop.
SP=/tmp/lingt
OUT=$(cd "$(dirname "$0")" && pwd)/out
KIMG=/mnt/c/Users/User/Programs/LingOS/dist-lsx/rpi/kernel8.img
BOOT=${1:-35}
rm -rf $SP; mkdir -p $SP; mkfifo $SP/ser.in $SP/ser.out
cat $SP/ser.out > $SP/serial.log &
exec 3<>$SP/ser.in
( sleep $BOOT; printf '\033' >&3; sleep 4
  printf '\033[B' >&3; sleep 1; printf '\033[B' >&3; sleep 1; printf '\033[B' >&3; sleep 1; printf '\033[B' >&3; sleep 1; printf '\033[B' >&3; sleep 1
  echo "screendump $SP/m.ppm"; sleep 1
  printf '\r' >&3; sleep 6; echo "screendump $SP/c.ppm"; sleep 1
  printf 'ling demo\r' >&3; sleep 6; echo "screendump $SP/d.ppm"; sleep 1
  printf 'ling run home/ling/Scripts/fib.ling\r' >&3; sleep 6; echo "screendump $SP/f.ppm"; sleep 1
  printf 'ling list\r' >&3; sleep 3
  printf 'ling run home/ling/Graphics/spiral.ling\r' >&3; sleep 14; echo "screendump $SP/s.ppm"; sleep 1
  printf '\033' >&3; sleep 5; echo "screendump $SP/q.ppm"; sleep 1
  printf 'exit\r' >&3; sleep 6; echo "screendump $SP/x.ppm"; sleep 1; echo quit ) \
  | timeout $((BOOT + 100)) qemu-system-aarch64 -M raspi3b -kernel "$KIMG" \
      -chardev pipe,id=s0,path=$SP/ser -serial chardev:s0 -monitor stdio -vnc 127.0.0.1:4 >/dev/null 2>&1
for f in m c d f s q x; do [ -f $SP/$f.ppm ] && ffmpeg -y -loglevel error -i $SP/$f.ppm $OUT/lingt-$f.png && echo "$f ok"; done
echo "=== serial (from the console on) ==="
tr -d '\000\r' < $SP/serial.log | grep -v "daw_\|ui_" | sed -n '/LingOS console/,$p' | head -90
