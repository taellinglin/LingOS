#!/usr/bin/env bash
# Verify the Files window: boot to desktop, click the dock's F icon,
# screendump the lingfs listing, then Enter on the first entry.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)/out"; mkdir -p "$DIR"
ISO=/mnt/c/Users/User/Programs/LingOS/dist/lingos-x86_64.iso
DISK=/mnt/c/Users/User/Programs/LingOS/dist/lingos-test-disk.img

{
    sleep 24
    echo "sendkey ret"
    sleep 6
    for i in 1 2 3 4; do
        echo "mouse_move 160 186"
        sleep 0.3
    done
    echo "mouse_move 71 0"      # from S center to F center
    sleep 0.5
    echo "mouse_button 1"
    sleep 0.3
    echo "mouse_button 0"
    sleep 2
    echo "screendump $DIR/files-list.ppm"
    sleep 1
    echo "sendkey ret"          # open first entry (a directory or file)
    sleep 2
    echo "screendump $DIR/files-open.ppm"
    sleep 1
    echo "quit"
} | qemu-system-x86_64 \
    -cdrom "$ISO" \
    -drive file="$DISK",format=raw,if=ide,index=0 \
    -serial file:"$DIR/serial-files.log" \
    -display none -monitor stdio -m 256M -nic user,model=e1000 >/dev/null 2>&1

ffmpeg -y -loglevel error -i "$DIR/files-list.ppm" "$DIR/files-list.png"
ffmpeg -y -loglevel error -i "$DIR/files-open.ppm" "$DIR/files-open.png"
ls -la "$DIR"/files-*.png
