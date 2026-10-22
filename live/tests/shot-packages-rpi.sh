#!/usr/bin/env bash
# Pi desktop (QEMU raspi3b, SD image): the Packages window opens (no network ->
# its message), a runnable package is seeded on storage from the console, and
# the Applications menu then lists it under Installed.
SP=/tmp/pipkgs
OUT=$(cd "$(dirname "$0")" && pwd)/out
KIMG=/mnt/c/Users/User/Programs/LingOS/dist-lsx/rpi/kernel8.img
SD=$OUT/sd.img
[ -f "$SD" ] || python3 "$(dirname "$0")/make-sd-image.py" "$SD"
BOOT=${1:-35}
rm -rf $SP; mkdir -p $SP; mkfifo $SP/ser.in $SP/ser.out
cat $SP/ser.out > $SP/serial.log &
exec 3<>$SP/ser.in
slow() { local s="$1" i; for ((i = 0; i < ${#s}; i++)); do printf '%s' "${s:i:1}" >&3; sleep 0.03; done; printf '\r' >&3; }
down() { local n=$1; for ((i = 0; i < n; i++)); do printf '\033[B' >&3; sleep 0.5; done; }
( sleep $BOOT
  printf '\033' >&3; sleep 3; down 6; printf '\r' >&3; sleep 8      # menu -> Packages (visual row 7)
  echo "screendump $SP/q1.ppm"; sleep 1
  printf '\033' >&3; sleep 2                                         # close the Packages window
  printf '\033' >&3; sleep 3; printf '\033[A' >&3; sleep 1; printf '\r' >&3; sleep 6   # menu: Up from Packages -> Console
  slow 'ling eval bind main = do { print(write_file("pkg-hello/main.ling", "bind main = do { print(1 + 1) }")) }'; sleep 5
  slow 'ls pkg-hello'; sleep 3
  slow 'exit'; sleep 6
  printf '\033' >&3; sleep 4; echo "screendump $SP/q2.ppm"; sleep 1   # menu with Installed
  for i in 1 2 3 4 5; do printf '\033[B' >&3; sleep 0.5; done; printf '\r' >&3; sleep 6   # Installed -> hello
  echo quit ) \
  | timeout $((BOOT + 100)) qemu-system-aarch64 -M raspi3b -kernel "$KIMG" -drive file=$SD,if=sd,format=raw \
      -chardev pipe,id=s0,path=$SP/ser -serial chardev:s0 -monitor stdio -vnc 127.0.0.1:4 >/dev/null 2>&1
for f in q1 q2; do [ -f $SP/$f.ppm ] && ffmpeg -y -loglevel error -i $SP/$f.ppm $OUT/pipkgs-$f.png && echo "$f ok"; done
tr -d '\000\r' < $SP/serial.log | grep -a -E 'lingos\$|^true|^false|main.ling|^2$|panic|exception' | awk '!seen[$0]++' | head -12
