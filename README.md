# LingOS

A production-grade, from-scratch operating system kernel and userspace written in [Ling](../ling-lang), booting on x86_64 (BIOS/GRUB, QEMU, VirtualBox) and Raspberry Pi (aarch64, QEMU `raspi3b` and real hardware).

## Architecture & Subsystems

This section describes what's actually built and verified — see [`packages/README.md`](packages/README.md)
for the honest roadmap of what's planned but not there yet (real process isolation, package
signing, and more all belong there, not here, until they're real).

- **Real interrupts + cooperative task scheduling (`proc/`, `arch/{x86_64,aarch64}/`)**:
  - Genuine IDT/PIC (x86_64) and VBAR_EL1/intc (aarch64) interrupt handling, IRQ-driven keyboard
    and mouse input, a 100Hz timer heartbeat.
  - A cooperative (**not** preemptive) round-robin scheduler (`proc/sched.rs`) — every task shares
    one flat, identity-mapped address space and runs in ring 0 (no TSS/ring-3 anywhere in this
    kernel); a task must voluntarily `yield` for anything else to run. `apps/*` are separate
    `.ling` source directories today, but there's no ELF loader or process-isolation boundary yet —
    they aren't independently runnable binaries, they're either compiled directly into a kernel
    target or (once Track A/B of the current work lands) `use`-shared source modules.

- **Real memory management (`mm/`)**: a buddy physical-frame allocator and a slab heap allocator
  with working `free()` — replaced the old bump-arena-that-never-frees. Paging beyond the one-time
  boot-time identity map (NX/W^X, per-process address spaces) is deliberately not built yet.

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
