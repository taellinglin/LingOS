#!/usr/bin/env bash
# Interaction test: boot to desktop, click the dock's Settings icon with
# scripted PS/2 mouse moves, switch UI theme with Right arrow (Dusk ->
# Daylight), screendump. Verifies mouse hit-testing, the Settings content
# renderer, and live theme switching end to end.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)/out"; mkdir -p "$DIR"
ISO=/mnt/c/Users/User/Programs/LingOS/dist/lingos-x86_64.iso
DISK=/mnt/c/Users/User/Programs/LingOS/dist/lingos-test-disk.img
SERIAL="$DIR/serial-settings.log"

{
    sleep 24
    echo "sendkey ret"          # locale picker -> desktop
    sleep 6
    echo "info mice"
    # Cursor starts at (0,0); dock Settings icon center ~= (640, 744) at
    # 1280x800. PS/2 deltas are small; several medium moves.
    # HMP mouse_move uses screen convention (positive dy = down); QEMU
    # does the PS/2 sign conversion itself.
    for i in 1 2 3 4; do
        echo "mouse_move 160 186"
        sleep 0.3
    done
    sleep 1
    echo "mouse_button 1"
    sleep 0.3
    echo "mouse_button 0"
    sleep 2
    echo "screendump $DIR/settings-dusk.ppm"
    sleep 1
    echo "sendkey right"        # UI theme row: Dusk -> Daylight
    sleep 2
    echo "screendump $DIR/settings-daylight.ppm"
    sleep 1
    echo "quit"
} | qemu-system-x86_64 \
    -cdrom "$ISO" \
    -drive file="$DISK",format=raw,if=ide,index=0 \
    -serial file:"$SERIAL" \
    -display none -monitor stdio -m 256M -nic user,model=e1000 >"$DIR/monitor.log" 2>&1

ffmpeg -y -loglevel error -i "$DIR/settings-dusk.ppm" "$DIR/settings-dusk.png"
ffmpeg -y -loglevel error -i "$DIR/settings-daylight.ppm" "$DIR/settings-daylight.png"
ls -la "$DIR"/settings-*.png
