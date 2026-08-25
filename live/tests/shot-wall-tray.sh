#!/usr/bin/env bash
# Verify the ROYGBIV wallpaper (Settings > Wallpaper > right) and the
# volume tray popover (click the speaker icon, adjust a stream).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)/out"; mkdir -p "$DIR"
ISO=/mnt/c/Users/User/Programs/LingOS/dist/lingos-x86_64.iso
DISK=/mnt/c/Users/User/Programs/LingOS/dist/lingos-test-disk.img

{
    sleep 24
    echo "sendkey ret"
    sleep 6
    # Dock: open Settings.
    for i in 1 2 3 4; do
        echo "mouse_move 160 186"
        sleep 0.3
    done
    echo "mouse_button 1"; sleep 0.3; echo "mouse_button 0"
    sleep 2
    # Wallpaper row (row 2), switch to ROYGBIV.
    echo "sendkey down"; sleep 0.5
    echo "sendkey down"; sleep 0.5
    echo "sendkey right"; sleep 2
    echo "screendump $DIR/wall-roygbiv.ppm"
    sleep 1
    # Volume tray: cursor (640,744) -> speaker icon (~1146,15).
    for i in 1 2 3 4; do
        echo "mouse_move 127 -183"
        sleep 0.3
    done
    echo "mouse_button 1"; sleep 0.3; echo "mouse_button 0"
    sleep 2
    # Down to the "player" stream row, drop its volume twice.
    echo "sendkey down"; sleep 0.4
    echo "sendkey down"; sleep 0.4
    echo "sendkey down"; sleep 0.4
    echo "sendkey left"; sleep 0.4
    echo "sendkey left"; sleep 1
    echo "screendump $DIR/tray-popover.ppm"
    sleep 1
    echo "quit"
} | qemu-system-x86_64 \
    -cdrom "$ISO" \
    -drive file="$DISK",format=raw,if=ide,index=0 \
    -serial file:"$DIR/serial-walltray.log" \
    -audiodev wav,id=snd0,path="$DIR/ui-sounds.wav",out.frequency=48000 \
    -device AC97,audiodev=snd0 \
    -display none -monitor stdio -m 256M -nic user,model=e1000 >/dev/null 2>&1

ffmpeg -y -loglevel error -i "$DIR/wall-roygbiv.ppm" "$DIR/wall-roygbiv.png"
ffmpeg -y -loglevel error -i "$DIR/tray-popover.ppm" "$DIR/tray-popover.png"
ls -la "$DIR"/wall-roygbiv.png "$DIR"/tray-popover.png "$DIR"/ui-sounds.wav
