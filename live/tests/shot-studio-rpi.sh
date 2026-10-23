#!/usr/bin/env bash
# Pi studio image (QEMU raspi3b, SD image): every bundled app opens from the
# Applications menu and Ctrl+Q comes back to the desktop -- LingStationX,
# LingDev, LingModeler, Horizon (its start page; no network in raspi3b),
# Messenger -- then the Wi-Fi window (no radio on a Pi 3 -> its message; with
# the console's `wifi demo` a made-up list, pick one, type a passphrase, join)
# and Files showing the Projects folder.
#   bash live/tests/shot-studio-rpi.sh [boot-seconds]
# The menu keeps its last selection, so every launch steps from the previous
# one. Visual order: LingStationX, HDMI test, LingDev, LingModeler, Horizon,
# Messenger, Wi-Fi, Files, Console, Packages, Settings, About (wraps).
SP=/tmp/pistudio
OUT=$(cd "$(dirname "$0")" && pwd)/out
KIMG=/mnt/c/Users/User/Programs/LingOS/dist-lsx/rpi/kernel8.img
SD=$OUT/sd.img
[ -f "$SD" ] || python3 "$(dirname "$0")/make-sd-image.py" "$SD"
BOOT=${1:-40}
rm -rf $SP; mkdir -p $SP; mkfifo $SP/ser.in $SP/ser.out
cat $SP/ser.out > $SP/serial.log &
exec 3<>$SP/ser.in
slow() { local s="$1" i; for ((i = 0; i < ${#s}; i++)); do printf '%s' "${s:i:1}" >&3; sleep 0.03; done; printf '\r' >&3; }
down() { local n=$1; for ((i = 0; i < n; i++)); do printf '\033[B' >&3; sleep 0.5; done; }
up() { local n=$1; for ((i = 0; i < n; i++)); do printf '\033[A' >&3; sleep 0.5; done; }
launch() { printf '\033' >&3; sleep 3; down "$1"; printf '\r' >&3; sleep "$2"; }
quit_app() { printf '\021' >&3; sleep 6; }   # Ctrl+Q
( sleep $BOOT
  echo "screendump $SP/s0.ppm"; sleep 1                       # the desktop
  launch 0 18; echo "screendump $SP/s1.ppm"; sleep 1; quit_app # LingStationX (selection starts there)
  launch 2 25; echo "screendump $SP/s2.ppm"; sleep 1; quit_app # LingDev
  launch 1 25; echo "screendump $SP/s3.ppm"; sleep 1; quit_app # LingModeler
  launch 1 14; echo "screendump $SP/s4.ppm"; sleep 1           # Horizon: start page
  printf 'l' >&3; sleep 1; slow 'example.com'; sleep 12          # a fetch with no network -> the error page
  echo "screendump $SP/s4b.ppm"; sleep 1; quit_app
  launch 1 10; echo "screendump $SP/s5.ppm"; sleep 1; quit_app # Messenger
  launch 1 6; echo "screendump $SP/s6.ppm"; sleep 1            # Wi-Fi: no radio on this board
  printf '\033' >&3; sleep 2
  launch 2 8                                                    # Console
  slow 'wifi demo'; sleep 2; slow 'wifi scan'; sleep 3; slow 'exit'; sleep 6
  printf '\033' >&3; sleep 3; up 2; printf '\r' >&3; sleep 6    # Wi-Fi again: demo list
  echo "screendump $SP/s7.ppm"; sleep 1
  printf '\033[B' >&3; sleep 1; printf '\r' >&3; sleep 2        # second network -> passphrase
  slow 'moonpalace99'; sleep 4; echo "screendump $SP/s8.ppm"; sleep 1
  printf '\033' >&3; sleep 2
  launch 1 6; echo "screendump $SP/s9.ppm"; sleep 1            # Files: home with Projects
  echo quit ) \
  | timeout $((BOOT + 290)) qemu-system-aarch64 -M raspi3b -kernel "$KIMG" -drive file=$SD,if=sd,format=raw \
      -chardev pipe,id=s0,path=$SP/ser -serial chardev:s0 -monitor stdio -vnc 127.0.0.1:4 >/dev/null 2>&1
for f in s0 s1 s2 s3 s4 s4b s5 s6 s7 s8 s9; do [ -f $SP/$f.ppm ] && ffmpeg -y -loglevel error -i $SP/$f.ppm $OUT/studio-$f.png && echo "$f ok"; done
tr -d '\000\r' < $SP/serial.log | grep -a -E 'wifi|messenger|app:|storage:|panic|exception|lingrt' | awk '!seen[$0]++' | head -30
