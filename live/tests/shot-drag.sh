#!/usr/bin/env bash
# Drag test: grab the About window's titlebar, drag down-left, release.
# Screendumps before and after -- the window must follow the drag (liquid
# spring) and settle at the drop point, proving titlebar hit-testing,
# drag-target tracking, and release all work.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)/out"; mkdir -p "$DIR"
ISO=/mnt/c/Users/User/Programs/LingOS/dist/lingos-x86_64.iso
DISK=/mnt/c/Users/User/Programs/LingOS/dist/lingos-test-disk.img

{
    sleep 24
    echo "sendkey ret"
    sleep 6
    echo "screendump $DIR/drag-before.ppm"
    sleep 1
    # Cursor (0,0) -> About titlebar (~635, 205 at 1280x800 after the
    # spawn clamp); then press, drag down-left in steps, release.
    for i in 1 2 3 4; do
        echo "mouse_move 159 51"
        sleep 0.3
    done
    echo "mouse_button 1"
    sleep 0.5
    for i in 1 2 3; do
        echo "mouse_move -80 60"
        sleep 0.4
    done
    echo "mouse_button 0"
    sleep 3
    echo "screendump $DIR/drag-after.ppm"
    sleep 1
    echo "quit"
} | qemu-system-x86_64 \
    -cdrom "$ISO" \
    -drive file="$DISK",format=raw,if=ide,index=0 \
    -serial file:"$DIR/serial-drag.log" \
    -display none -monitor stdio -m 256M -nic user,model=e1000 >/dev/null 2>&1

ffmpeg -y -loglevel error -i "$DIR/drag-before.ppm" "$DIR/drag-before.png"
ffmpeg -y -loglevel error -i "$DIR/drag-after.ppm" "$DIR/drag-after.png"
ls -la "$DIR"/drag-*.png
