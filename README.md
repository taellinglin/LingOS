# LingOS

A production-grade, from-scratch operating system kernel and userspace written in [Ling](../ling-lang), booting on x86_64 (BIOS/GRUB, QEMU, VirtualBox) and Raspberry Pi (aarch64, QEMU `raspi3b` and real hardware).

## Architecture & Subsystems

- **Ring-3 Process Isolation & Preemptive Multitasking (`proc/`)**:
  - Full hardware isolation via 4-level paging (`PML4` on x86_64, `TTBR0_EL1` on aarch64).
  - Preemptive round-robin scheduler driven by the 100Hz hardware timer interrupt.
  - Ring-3 context switching saving all general-purpose and floating-point registers.
  - Native ELF64 loader mapping `PT_LOAD` segments with strict `W^X` permissions.

- **System Call ABI v1 (`abi/syscalls.rs`)**:
  - Unified, portable syscall table across `x86_64` (`syscall`/`sysret`) and `aarch64` (`svc #0`):
    - `exit`, `write`, `read`, `open`, `close`, `lseek`, `mmap`, `munmap`, `spawn`, `waitpid`, `yield`, `getpid`, `sleep_ms`, `poll_input`, `fb_map`, `uname`.
  - Thorough pointer and range validation in kernel space protecting against invalid userland memory accesses.

- **Content-Addressed Root Filesystem (`lingfs/`)**:
  - Git-style immutable object store identified by BLAKE3 cryptographic hashes.
  - O(1) object lookup via open-addressed hash index.
  - Incremental dirty-block writeback caching.
  - Double-buffered superblock with commit log history.
  - Multi-level directory trees and path resolution.

- **Ling Userspace Runtime (`ling-user`) & Compiler Support (`--platform lingos`)**:
  - Dedicated `no_std` + `alloc` userland runtime implementing all Ling language primitives (NaN-boxed dynamic values, strings, lists, structs, arithmetic, builtins, stdout formatting).
  - First-party userland applications in `apps/`:
    - `apps/hello`: Userland computation and syscall demonstration.
    - `apps/lsh`: Interactive userland command shell.
    - `apps/top`: Process monitor and system status viewer.
    - `apps/edit`: Text editor.
    - `apps/lingwm`: Compositor and window manager.

- **Package Manager (`packages.rs`)**:
  - Signed package distribution format (`LPK2`) with Ed25519 signature verification.
  - Automatic deployment of executable binaries to `/bin` and configuration data to `/pkg-<name>`.

- **Cross-Platform Parity**:
  - Complete parity across `x86_64` and `aarch64` architectures.
  - Automated QEMU boot regression test suite (`live/boot-test.sh`).

## Repository Layout

```
apps/                     LingOS userspace applications (hello, lsh, top, edit, lingwm)
kernel/x86_64/            Ling source + manifest for x86_64 kernel
kernel/rpi/               Ling source + manifest for Raspberry Pi (aarch64) kernel
font/                     Console fonts rasterized into the VGA character generator
live/                     Boot, build, and automated test scripts
packages/                 Package format specifications and test packages
dist/                     Build output directory
```

## Building

Build the Ling compiler:
```bash
cd ling-lang
cargo build --release --bin ling
```

Build kernels and userland applications:
```bash
# Build x86_64 and aarch64 kernels
../ling-lang/target/release/ling build kernel/x86_64 --platform kernel --out dist
../ling-lang/target/release/ling build kernel/rpi --platform rpi --out dist

# Build userspace apps
../ling-lang/target/release/ling build apps/hello --platform lingos --out dist
../ling-lang/target/release/ling build apps/lsh --platform lingos --out dist
../ling-lang/target/release/ling build apps/top --platform lingos --out dist
../ling-lang/target/release/ling build apps/edit --platform lingos --out dist
../ling-lang/target/release/ling build apps/lingwm --platform lingos --out dist

# Assemble bootable ISO
bash live/build-iso-x86_64.sh
```

## Automated Verification

Run automated boot and regression testing in QEMU:
```bash
bash live/boot-test.sh
```
