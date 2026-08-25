#!/usr/bin/env bash
# End-to-end installed-system boot test: write the diskboot image (stage1 +
# stage2-with-VBE + desktop kernel) onto the head of the test disk -- the
# same raw write the installer performs -- keeping the disk's existing
# lingfs (which already holds the "live" account from earlier Live boots).
# Boot from the DISK ONLY (no CD anywhere): stage2 must set the VBE mode,
# the kernel must find the LFBI handoff block, and the greeter must accept
# live/live before the desktop appears.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)/out"; mkdir -p "$DIR"
DIST=/mnt/c/Users/User/Programs/LingOS/dist
DISK="$DIST/lingos-test-disk.img"

# Same raw write the installer does to LBA 0: payload onto the disk head.
dd if="$DIST/diskboot-x86_64.img" of="$DISK" conv=notrunc status=none

type_word() { # sendkey one lowercase word + Enter
    for c in $(echo "$1" | grep -o .); do
        echo "sendkey $c"
        sleep 0.4
    done
    echo "sendkey ret"
}

{
    sleep 15                       # BIOS + stage1/2 + kernel + greeter up
    echo "screendump $DIR/greeter.ppm"
    sleep 1
    type_word live                 # username field
    sleep 2
    type_word live                 # password field (masked)
    sleep 6                        # login jingle + desktop up
    echo "screendump $DIR/installed-desktop.ppm"
    sleep 1
    echo "quit"
} | qemu-system-x86_64 \
    -drive file="$DISK",format=raw,if=ide,index=0 \
    -serial file:"$DIR/serial-installed.log" \
    -audiodev wav,id=snd0,path="$DIR/installed-audio.wav",out.frequency=48000 \
    -device AC97,audiodev=snd0 \
    -display none -monitor stdio -m 256M -nic user,model=e1000 >/dev/null 2>&1

ffmpeg -y -loglevel error -i "$DIR/greeter.ppm" "$DIR/greeter.png" 2>/dev/null || echo "no greeter dump"
ffmpeg -y -loglevel error -i "$DIR/installed-desktop.ppm" "$DIR/installed-desktop.png" 2>/dev/null || echo "no desktop dump"
echo "--- serial ---"
grep -E "greeter|wm:|initialized|mounted" "$DIR/serial-installed.log" | head -12
ls -la "$DIR"/greeter.png "$DIR"/installed-desktop.png 2>/dev/null
