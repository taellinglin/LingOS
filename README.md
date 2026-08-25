# LingOS

A production-grade, from-scratch operating system kernel and userspace written in [Ling](../ling-lang), booting on x86_64 (BIOS/GRUB, QEMU, VirtualBox) and Raspberry Pi (aarch64, QEMU `raspi3b` and real hardware).

## Architecture & Subsystems

This section describes what's actually built and verified — see [`packages/README.md`](packages/README.md)
for the honest roadmap of what's planned but not there yet (real process isolation, package
signing, and more all belong there, not here, until they're real).

- **Real interrupts, two schedulers, and ring-3 (`proc/`, `arch/{x86_64,aarch64}/`)**:
  - Genuine IDT/PIC (x86_64) and VBAR_EL1/intc (aarch64) interrupt handling, IRQ-driven keyboard
    and mouse input (plus a per-frame 8042 poll-drain — QEMU's controller holds data without
    re-edging IRQ12; see `drivers/mouse.rs`), a 100Hz timer heartbeat.
  - A cooperative round-robin scheduler (`proc/sched.rs`) for in-kernel tasks, **and** a real
    preemptive ring-3 layer (`proc/uproc.rs`): syscall/sysret, per-process page tables, a static
    ELF loader, 16 frozen syscall numbers (several still ENOSYS — see `abi/syscalls.rs`). Only
    diagnostics (`proctest`, `ps`) drive ring-3 so far; `apps/*` remain `use`-shared source
    compiled into kernel targets, not separate processes yet.

- **Real memory management (`mm/`, `arch/*/paging.rs`)**: a buddy physical-frame allocator, a slab
  heap with working `free()`, and real 4-level paging with NX/W^X on the kernel image plus
  per-process address spaces for ring-3 — the old "identity map only" note is history.

- **Desktop (`kernel/x86_64-wm` + `drivers/{wm,theme,mixer,ac97,...}.rs`)**: a multi-window
  manager (z-order, focus, titlebar drag with liquid-spring physics, close/minimize), dock,
  RTC clock, Settings/Files/About apps, switchable UI themes + wallpapers (incl. ROYGBIV), a
  Windows-style per-app audio mixer over an AC'97 driver with pentatonic sound themes, and a
  MATE-style tray (volume popover, ethernet status). Installed disks boot to a login greeter
  via a VBE-mode-setting, unreal-mode stage2 (`bootloader/stage2.asm`). Interaction-verified in
  headless QEMU — see `live/tests/`.

- **Networking (`drivers/{net_e1000,netstack,lingfu}.rs`)**: the e1000 driver's long-standing
  silent-wire mystery is fixed (PCI bus mastering + a TCG-fast timeout — module doc has the
  story); on top sit a minimal real IPv4/TCP/HTTP client and `lingfu sync|search|install`,
  which downloads and installs `.lpkg`s from any HTTP repo (default: QEMU's host alias;
  configurable via lingfs `/repo`). Unsigned + plain HTTP until roadmap steps land — see
  `packages/README.md`.

- **Content-Addressed Root Filesystem (`lingfs/`)**:
  - Git-style immutable object store identified by BLAKE3 cryptographic hashes.
  - O(1) object lookup via open-addressed hash index.
  - Incremental dirty-block writeback caching.
  - Double-buffered superblock with commit log history.
  - Multi-level directory trees and path resolution.

- **Local package format (`fs/packages.rs`)**: `.lpkg`, a simple length-prefixed
  (filename, content) blob unpacked into `lingfs`. Not signed, no catalog/dependency resolution,
  no execution — see `packages/README.md` for what's actually planned there.

- **Cross-Platform Parity**:
  - Shared driver/filesystem/scheduler code across `x86_64` and `aarch64`, arch-specific HAL under
    `arch/{x86_64,aarch64}/`.
  - Automated QEMU boot regression test suite (`live/boot-test.sh`).

## Repository Layout

```
apps/                     .ling source shared into kernel targets (lsh, hello, top, edit, lingwm)
kernel/x86_64/            Ling source + manifest for the x86_64 Live kernel
kernel/x86_64-installer/  Ling source + manifest for the x86_64 installer kernel
kernel/x86_64-wm/         Ling source + manifest for the x86_64 graphics/window-manager kernel
kernel/rpi/               Ling source + manifest for Raspberry Pi (aarch64) kernel
font/                     Console fonts rasterized into the VGA character generator
live/                     Boot, build, and automated test scripts
packages/                 Package format + the honest roadmap for what's not built yet
dist/                     Build output directory
```

## Building

Build the Ling compiler:
```bash
cd ../ling
cargo build --release --bin ling
```

Build the kernel targets (each is a real, standalone `--platform kernel`/`rpi` build — there is no
separate userland-app build step; `apps/*` are `use`-shared straight into whichever kernel target
calls them, per the module system's real capabilities, not compiled as independent binaries):
```bash
../ling/target/release/ling build kernel/x86_64 --platform kernel --out dist
../ling/target/release/ling build kernel/x86_64-installer --platform kernel --out dist
../ling/target/release/ling build kernel/x86_64-wm --platform kernel --out dist
../ling/target/release/ling build kernel/rpi --platform rpi --out dist

# Assemble bootable ISO
bash live/build-iso-x86_64.sh
```

## Automated Verification

Run automated boot and regression testing in QEMU:
```bash
bash live/boot-test.sh
```
