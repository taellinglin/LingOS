#!/usr/bin/env bash
# Audio verification: boot with an AC'97 device whose output QEMU records
# to a host WAV, get to the desktop (boot jingle fires after login), let it
# play, then assert the jingle's actual pentatonic frequencies appear in
# the recording -- the audio equivalent of the screendump rule.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)/out"; mkdir -p "$DIR"
ISO=/mnt/c/Users/User/Programs/LingOS/dist/lingos-x86_64.iso
DISK=/mnt/c/Users/User/Programs/LingOS/dist/lingos-test-disk.img
WAV="$DIR/boot-audio.wav"
rm -f "$WAV"

{
    sleep 24
    echo "sendkey ret"      # locale -> desktop -> boot jingle
    sleep 8
    echo "quit"
} | qemu-system-x86_64 \
    -cdrom "$ISO" \
    -drive file="$DISK",format=raw,if=ide,index=0 \
    -serial file:"$DIR/serial-audio.log" \
    -audiodev wav,id=snd0,path="$WAV",out.frequency=48000 \
    -device AC97,audiodev=snd0 \
    -display none -monitor stdio -m 256M -nic user,model=e1000 >/dev/null 2>&1

ls -la "$WAV"
python3 - "$WAV" <<'EOF'
import sys, wave, math, struct, io

# QEMU's wav audiodev only writes the RIFF/data chunk sizes on a clean
# audiodev close, which a monitor `quit` skips -- patch them from the real
# file length before parsing.
data = bytearray(open(sys.argv[1], "rb").read())
if data[4:8] == b"\x00\x00\x00\x00":
    total = len(data)
    struct.pack_into("<I", data, 4, total - 8)
    struct.pack_into("<I", data, 40, total - 44)

w = wave.open(io.BytesIO(bytes(data)), "rb")
n, sr, ch, sw = w.getnframes(), w.getframerate(), w.getnchannels(), w.getsampwidth()
raw = w.readframes(n)
w.close()
print(f"wav: {n} frames @ {sr} Hz, {ch}ch, {sw*8}-bit")
if sw != 2:
    sys.exit("unexpected sample width")
samples = struct.unpack(f"<{n*ch}h", raw)[::ch]  # left channel

peak = max(abs(s) for s in samples) if samples else 0
print(f"peak amplitude: {peak}")

def goertzel(block, freq, sr):
    k = 2.0 * math.cos(2.0 * math.pi * freq / sr)
    s1 = s2 = 0.0
    for x in block:
        s0 = x + k * s1 - s2
        s2, s1 = s1, s0
    return s2*s2 + s1*s1 - k*s1*s2

# Boot jingle (Dawn Chimes): C4 E4 G4 A4 C5. Control tone F#4 (369.99 Hz)
# is NOT in the pentatonic scale -- it must score far lower or we're
# measuring noise, not the melody.
notes = {"C4": 261.63, "E4": 329.63, "G4": 392.00, "A4": 440.00, "C5": 523.25}
control = 369.99
active = [s for s in samples if abs(s) > 300] and samples
block = samples[: sr * 4] if len(samples) > sr * 4 else samples
ctrl = goertzel(block, control, sr) + 1.0
ok = True
for name, f in notes.items():
    score = goertzel(block, f, sr)
    ratio = score / ctrl
    mark = "PASS" if ratio > 3.0 else "FAIL"
    if ratio <= 3.0:
        ok = False
    print(f"{name} ({f:.1f} Hz): energy ratio vs non-pentatonic control = {ratio:8.1f}  {mark}")
print("AUDIO VERDICT:", "PASS -- pentatonic boot jingle present" if (ok and peak > 1000) else "FAIL")
EOF
