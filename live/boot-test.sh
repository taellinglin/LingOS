#!/usr/bin/env bash
# Boot LingOS's x86_64 ISO and aarch64 kernel8.img headless in QEMU, capture
# their serial logs, and assert on markers that only appear if the kernel
# actually reached a stable, interactive state — not just "the emulator
# didn't crash." Used by CI (.github/workflows/ci.yml) and locally
# (`bash live/boot-test.sh` after building dist/, from repo root or here).
#
# Each phase of the LingOS work adds its own markers to EXPECT_X86_64 /
# EXPECT_AARCH64 below as new subsystems come online (e.g. a fault-dump
# format once Phase 2 lands real interrupt handlers) — this file is the
# single place that check lives, so both CI and a local run stay in sync.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$SCRIPT_DIR/../dist"
TIMEOUT_S="${LINGOS_BOOT_TIMEOUT:-20}"
X86_64_DISK="$DIST_DIR/lingos-test-disk.img"

# A real disk on its own explicit primary-IDE slot, same reasoning as
# `run-qemu-x86_64.sh`: `-cdrom` with no `-drive` at all lands the ATAPI
# CD-ROM on the primary IDE channel `ata.rs` reads from, and an ATAPI drive
# doesn't answer plain ATA READ SECTORS — `lingfs mount` was observed
# hanging well past any single poll's bounded timeout as a result (dozens
# of polls during first-boot format, each waiting out its own budget).
[ -f "$X86_64_DISK" ] || truncate -s 64M "$X86_64_DISK"

# Markers a healthy boot must print, in order. Not a full transcript match —
# new banner text/theme colors shouldn't break this — just proof each named
# subsystem actually initialized.
EXPECT_X86_64=(
    "ling-kernel initialized"
    "timer: TSC_PER_US="
    "interrupts enabled (IDT+PIC, 100Hz heartbeat)"
    "paging enabled (NX, W^X kernel image)"
    "lingfs mounted"
    "type 'help' for commands"
)
EXPECT_AARCH64=(
    "ling-kernel initialized"
    "interrupts enabled (VBAR_EL1+intc, 100Hz heartbeat)"
    "LingOS aarch64"
)

fail=0

check_markers() {
    local name="$1" log="$2"; shift 2
    local marker missing=0
    for marker in "$@"; do
        if ! grep -qF "$marker" <<<"$log"; then
            echo "FAIL [$name]: missing marker: $marker"
            missing=1
        fi
    done
    # A healthy boot never legitimately hits a CPU exception on either
    # architecture — this is the check that would have caught the aarch64
    # vector-table misalignment bug Phase 2 shipped with initially (the
    # ordinary EXPECT markers above all still printed before the fault
    # storm started, so only a negative check on the fault-dump text itself
    # catches it).
    if grep -qF "CPU EXCEPTION" <<<"$log"; then
        echo "FAIL [$name]: unexpected CPU EXCEPTION in boot log"
        missing=1
    fi
    if [ "$missing" -eq 0 ]; then
        echo "PASS [$name]: all $# markers present, no unexpected faults"
    else
        fail=1
        echo "--- full serial log [$name] ---"
        echo "$log"
        echo "--- end log [$name] ---"
    fi
}

boot_and_capture() {
    local name="$1"; shift
    local log rc
    log="$(timeout "$TIMEOUT_S" "$@" 2>&1)"
    rc=$?
    # `timeout` exits 124 when it has to kill the child (expected — this
    # kernel has no shutdown path, so a healthy boot always ends this way)
    # or 143 if the child dies from the resulting SIGTERM instead of the
    # timeout wrapper reporting it itself; anything else means QEMU failed
    # to start/run at all, a real failure distinct from "the markers didn't
    # show up."
    if [ "$rc" -ne 124 ] && [ "$rc" -ne 143 ] && [ "$rc" -ne 0 ]; then
        echo "FAIL [$name]: qemu exited $rc (not a boot timeout) — treating as crash"
        fail=1
    fi
    printf '%s' "$log"
}

if [ -f "$DIST_DIR/lingos-x86_64.iso" ]; then
    log="$(boot_and_capture x86_64 qemu-system-x86_64 \
        -cdrom "$DIST_DIR/lingos-x86_64.iso" \
        -drive file="$X86_64_DISK",format=raw,if=ide,index=0 \
        -serial stdio -m 256M -display none)"
    check_markers x86_64 "$log" "${EXPECT_X86_64[@]}"
else
    echo "SKIP [x86_64]: $DIST_DIR/lingos-x86_64.iso not built"
fi

if [ -f "$DIST_DIR/rpi/kernel8.img" ]; then
    log="$(boot_and_capture aarch64 qemu-system-aarch64 \
        -M raspi3b -kernel "$DIST_DIR/rpi/kernel8.img" -serial stdio -display none)"
    check_markers aarch64 "$log" "${EXPECT_AARCH64[@]}"
else
    echo "SKIP [aarch64]: $DIST_DIR/rpi/kernel8.img not built"
fi

exit "$fail"
