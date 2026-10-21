#!/usr/bin/env bash
# Pi (QEMU raspi3b) with an SD card image: lingfs is formatted in the free space
# after the card's partition at boot; the console then lists the home, writes a
# file from a Ling one-liner and reads it back; a second boot reads it again.
SP=/tmp/pisd
OUT=$(cd "$(dirname "$0")" && pwd)/out
KIMG=/mnt/c/Users/User/Programs/LingOS/dist-lsx/rpi/kernel8.img
SD=$OUT/sd.img
[ -f "$SD" ] || python3 "$(dirname "$0")/make-sd-image.py" "$SD"
BOOT=${1:-35}
run() {  # $1 = log name, rest = serial lines after the console opens
  local log=$1; shift
  rm -rf $SP; mkdir -p $SP; mkfifo $SP/ser.in $SP/ser.out
  cat $SP/ser.out > $SP/$log &
  exec 3<>$SP/ser.in
  ( sleep $BOOT; printf '\033' >&3; sleep 4
    printf '\033[B' >&3; sleep 1; printf '\033[B' >&3; sleep 1; printf '\033[B' >&3; sleep 1
    printf '\r' >&3; sleep 6
    for line in "$@"; do
      # typed slowly: the console polls the UART between commands only
      for ((i = 0; i < ${#line}; i++)); do printf '%s' "${line:i:1}" >&3; sleep 0.03; done
      printf '\r' >&3; sleep 4
    done
    echo "screendump $SP/$log.ppm"; sleep 1; echo quit ) \
    | timeout $((BOOT + 60)) qemu-system-aarch64 -M raspi3b -kernel "$KIMG" -drive file=$SD,if=sd,format=raw \
        -chardev pipe,id=s0,path=$SP/ser -serial chardev:s0 -monitor stdio -vnc 127.0.0.1:4 >/dev/null 2>&1
  exec 3>&-
  cp $SP/$log $OUT/$log
  [ -f $SP/$log.ppm ] && ffmpeg -y -loglevel error -i $SP/$log.ppm $OUT/pisd-$log.png
}
run boot1.log "sd" "ls" 'ling eval bind main = do { print(write_file("home/ling/Documents/note.txt", "saved on the sd card")) }' "cat home/ling/Documents/note.txt" "ls home/ling/Documents"
echo "=== boot 1 ==="
tr -d '\000\r' < $OUT/boot1.log | grep -v "daw_\|ui_" | sed -n '/SD card/,/starting the desktop/p;/LingOS console/,$p' | head -60
run boot2.log "cat home/ling/Documents/note.txt" "ls home/ling/Documents"
echo "=== boot 2 ==="
tr -d '\000\r' < $OUT/boot2.log | grep -v "daw_\|ui_" | sed -n '/storage:/p;/LingOS console/,$p' | head -20
