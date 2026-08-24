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
#
# Two separate x86_64 checks since the GRUB "Live" default now boots the
# graphics desktop (kernel/x86_64-wm), not the text shell -- EXPECT_X86_64
# still covers the text/shell/lingfs path (navigated to via the monitor,
# landing on "Rescue", the unchanged text kernel), and EXPECT_X86_64_LIVE
# covers the new default entry with the one marker it actually prints
# (vga_write_str mirrors to serial regardless of display mode).
EXPECT_X86_64=(
    "ling-kernel initialized"
    "timer: TSC_PER_US="
    "interrupts enabled (IDT+PIC, 100Hz heartbeat)"
    "paging enabled (NX, W^X kernel image)"
    "lingfs mounted"
    "type 'help' for commands"
)
EXPECT_X86_64_LIVE=(
    "ling-kernel initialized"
    "timer: TSC_PER_US="
    "interrupts enabled (IDT+PIC, 100Hz heartbeat)"
    "wm: entering interactive loop"
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
    local tmp_log
    tmp_log="$(mktemp)"
    local rc=0
    timeout "$TIMEOUT_S" "$@" -serial file:"$tmp_log" 2>/dev/null || rc=$?
    if [ "$rc" -ne 124 ] && [ "$rc" -ne 143 ] && [ "$rc" -ne 0 ]; then
        echo "FAIL [$name]: qemu exited $rc (not a boot timeout) — treating as crash"
        fail=1
    fi
    cat "$tmp_log"
    rm -f "$tmp_log"
}

# Same as boot_and_capture, but drives a monitor connection first to
# navigate GRUB down `down_count` entries before pressing Enter -- for
# reaching a non-default menu entry (Rescue) headlessly. Uses bash's
# built-in /dev/tcp (no netcat dependency); generous, fixed sleeps
# throughout, matching the timing this project's own interactive QEMU test
# scripts needed for reliable scancode delivery (a tight loop can
# outrun the guest's per-frame keyboard poll and silently drop a keypress
# -- confirmed the hard way writing those scripts).
boot_and_capture_navigated() {
    local name="$1" down_count="$2"; shift 2
    local tmp_log mon_port
    tmp_log="$(mktemp)"
    mon_port=$((14000 + RANDOM % 4000))

    timeout "$TIMEOUT_S" "$@" \
        -serial file:"$tmp_log" \
        -monitor "tcp:127.0.0.1:${mon_port},server,nowait" \
        &
    local qemu_pid=$!

    # Bash prints "connect: Connection refused" straight to the script's own
    # stderr for a failed /dev/tcp redirection regardless of a local
    # `2>/dev/null` on the `if` -- a known bash quirk (the message comes from
    # the redirection machinery itself, not a command this script runs) --
    # so the whole retry loop's stderr is redirected instead. Cosmetic only:
    # the loop's actual pass/fail (did `mon_fd` get set) is unaffected.
    local mon_fd=""
    for _ in $(seq 1 15); do
        if exec 9<>"/dev/tcp/127.0.0.1/${mon_port}"; then
            mon_fd=9
            break
        fi
        sleep 1
    done 2>/dev/null

    if [ -n "$mon_fd" ]; then
        sleep 2 # let GRUB itself finish loading before it can read scancodes
        for _ in $(seq 1 "$down_count"); do
            echo "sendkey down" >&"$mon_fd"
            sleep 1
        done
        echo "sendkey ret" >&"$mon_fd"
        exec 9<&- 9>&- 2>/dev/null || true
    else
        echo "WARN [$name]: never connected to the QEMU monitor -- menu navigation skipped, GRUB's own default will auto-boot instead" >&2
    fi

    wait "$qemu_pid" 2>/dev/null
    local rc=$?
    if [ "$rc" -ne 124 ] && [ "$rc" -ne 143 ] && [ "$rc" -ne 0 ]; then
        echo "FAIL [$name]: qemu exited $rc (not a boot timeout) — treating as crash"
        fail=1
    fi
    cat "$tmp_log"
    rm -f "$tmp_log"
}

if [ -f "$DIST_DIR/lingos-x86_64.iso" ]; then
    log="$(boot_and_capture x86_64-live qemu-system-x86_64 \
        -cdrom "$DIST_DIR/lingos-x86_64.iso" \
        -drive file="$X86_64_DISK",format=raw,if=ide,index=0 \
        -m 256M -display none)"
    check_markers x86_64-live "$log" "${EXPECT_X86_64_LIVE[@]}"

    # 3 "down"s from the GRUB default (Live) reaches Rescue -- see grub.cfg
    # (Live, Install-GUI, Install-text, Rescue).
    log="$(boot_and_capture_navigated x86_64-rescue 3 qemu-system-x86_64 \
        -cdrom "$DIST_DIR/lingos-x86_64.iso" \
        -drive file="$X86_64_DISK",format=raw,if=ide,index=0 \
        -m 256M -display none)"
    check_markers x86_64-rescue "$log" "${EXPECT_X86_64[@]}"
else
    echo "SKIP [x86_64]: $DIST_DIR/lingos-x86_64.iso not built"
fi

if [ -f "$DIST_DIR/rpi/kernel8.img" ]; then
    log="$(boot_and_capture aarch64 qemu-system-aarch64 \
        -M raspi3b -kernel "$DIST_DIR/rpi/kernel8.img" -display none)"
    check_markers aarch64 "$log" "${EXPECT_AARCH64[@]}"
else
    echo "SKIP [aarch64]: $DIST_DIR/rpi/kernel8.img not built"
fi

exit "$fail"
