# LingOS

A basic, from-scratch OS kernel written in [Ling](../ling), booting on
x86_64 (BIOS/GRUB, tested in QEMU and VirtualBox) and Raspberry Pi
(aarch64, tested in QEMU's `raspi3b` machine; real Pi 5 hardware needs
follow-up — see "Raspberry Pi 5 caveat" below).

## What's here today

- A GRUB boot menu (x86_64) offering **LingOS (Live)** and **LingOS
  (Install)**, like a real distro installer ISO. Live boots straight to
  the interactive shell; Install currently prints an honest placeholder
  (no filesystem/disk driver exists yet to install *to* — see
  `packages/README.md`) and then drops into the same shell, rather than
  silently doing nothing.
- A live, interactive text-console shell (`kernel/x86_64/main.ling`,
  `kernel/rpi/main.ling`) — boots to a colorful banner and echoes typed
  characters back.
- A themable console palette (`ling-kernel`'s `vga::Theme`) — LingOS's
  default reprograms the VGA hardware palette itself (not just which of
  16 slots a cell picks), so retheming is "define a different 16-entry
  RGB table and call `apply_theme`," not a font/asset swap.
- 4 virtual terminals (`term0`-`term3`), switchable with F1-F4 (x86_64
  only — see `ling/crates/ling-kernel/src/drivers/term.rs`).
- A build-time font pipeline: drop an `.otf`/`.ttf` in `font/` and it gets
  rasterized into the VGA console's character generator. Leave the
  keyboard idle for a while and the console swaps to it.
- Both kernels share one HAL surface (`ling_kernel_vga_write_str`,
  `ling_kernel_kbd_read_char`, ...) so `.ling` kernel source is portable
  between the two architectures — only `ling-kernel`'s backing
  implementation differs (VGA+PS/2 on x86_64, PL011 UART on aarch64).

**What's not here yet:** a filesystem, more than one running program,
persistent storage, user accounts, or a package manager. LingOS boots
fresh from the ISO/SD card every time — there's nowhere to save anything
yet. See `packages/README.md` for the build order that gets there.

## Layout

```
kernel/x86_64/            Ling source + manifest for the x86_64 (GRUB) Live kernel
kernel/x86_64-installer/  Ling source + manifest for the x86_64 Install placeholder
kernel/rpi/               Ling source + manifest for the Raspberry Pi kernel
font/                     Drop an .otf/.ttf here — square.otf is the current console font
live/                     Build/test/flash scripts (below)
packages/                 Package roadmap (nothing installable yet)
bootloader/               Placeholder — custom installed-system bootloader, not built yet
file_system/              Placeholder — FAT32 driver, in progress
dist/                     Build output (gitignored-style scratch; safe to delete)
```

## Building

The Ling compiler (`../ling`) does the actual compiling — build it once:

```powershell
cd ..\ling
cargo build --release --bin ling
```

Then, from Windows (PowerShell or this Bash tool):

```powershell
# x86_64 kernel -> dist/kernel/lingos-kernel-x86_64 (ELF)
..\ling\target\release\ling.exe build kernel\x86_64 --platform kernel --out dist

# Raspberry Pi kernel -> dist/rpi/kernel8.img (raw binary) + dist/rpi/lingos-kernel-rpi (ELF)
..\ling\target\release\ling.exe build kernel\rpi --platform rpi --out dist
```

Packaging the x86_64 ELF into a bootable GRUB ISO, and assembling the RPi
FAT32 boot image, need Linux-only tools (`grub-mkrescue`, `xorriso`,
`mtools`) that Windows doesn't have — run those two steps under WSL:

```bash
# from WSL (any distro with grub, xorriso, mtools installed via pacman/apt)
bash live/build-iso-x86_64.sh      # -> dist/lingos-x86_64.iso
bash live/build-sdcard-rpi.sh      # -> dist/lingos-rpi-boot.img
```

`build-iso-x86_64.sh`/`build-sdcard-rpi.sh` only do the packaging step —
they expect the ELF/`kernel8.img` to already exist (built on Windows,
above), since WSL's Windows-interop for directly executing `ling.exe`
isn't reliable in every distro (confirmed broken in this repo's WSL Arch
install).

## Testing

**QEMU (WSL):**

```bash
bash live/run-qemu-x86_64.sh    # boots dist/lingos-x86_64.iso, serial on stdio
bash live/run-qemu-rpi.sh       # boots dist/rpi/kernel8.img on QEMU's raspi3b
```

**VirtualBox (Windows):** create a VM (type "Other, 64-bit"), set
**firmware to BIOS, not EFI** (this is a legacy Multiboot2/GRUB boot path),
attach `dist/lingos-x86_64.iso` as an optical drive, boot. Confirmed
working this way (tested in a throwaway VM during development).

## Flashing to real media

Once you've got `dist/lingos-x86_64.iso` or `dist/lingos-rpi-boot.img`,
flash them with whatever tool you'd normally use — **Rufus** or
**balenaEtcher** for the x86_64 ISO onto a USB stick, **Raspberry Pi
Imager** or balenaEtcher for the RPi image onto an SD card ("write my own
image" / custom image option). There's no bespoke flashing script here on
purpose: writing to a raw disk is exactly the kind of action worth doing
through a tool with a device picker you can double-check, not a script
that already guessed which disk you meant.

For **real Raspberry Pi hardware**, the FAT32 boot partition also needs
the official RPi firmware blobs (`bootcode.bin`, `start*.elf`,
`fixup*.dat`) alongside `config.txt`/`kernel8.img` — fetch them yourself
from the Raspberry Pi Foundation's public `firmware` repo to match your
board's revision; they're not bundled here.

### Raspberry Pi 5 caveat

The aarch64 HAL (`ling-kernel`'s `drivers/uart.rs`/`arch/aarch64/mmio.rs`) targets the
BCM2837/BCM2711 (Pi 3/4) peripheral memory map, which is also what QEMU's
`raspi3b` emulates — the fast dev-loop target. Real Pi 5 hardware
(BCM2712) puts GPIO/UART behind a different chip (RP1, attached over
PCIe) with a different memory map entirely, and QEMU has no Pi 5 machine
model to develop against. Booting on a real Pi 5 needs follow-up HAL work
against real hardware, not just a base-address change — treat it as
untested until that happens, even though the same SD image will boot fine
on a real Pi 3/4.

## Architecture notes

- **x86_64 boot chain**: GRUB (Multiboot2) → `ling-kernel`'s `arch/x86_64/boot.rs`
  (a hand-written 32-bit→64-bit long mode trampoline: GRUB's Multiboot2
  handoff lands in 32-bit protected mode with paging off *even for a
  64-bit ELF* — that's the spec, not a GRUB quirk — so this sets up
  identity-mapped page tables, PAE, EFER.LME, a 64-bit GDT, and SSE
  before it's safe to run any Rust-compiled code) → the generated
  per-project `kernel_entry()` → your `.ling` program's `__main__`.
- **aarch64 boot chain**: RPi firmware loads `kernel8.img` (a raw binary,
  no ELF loader) at a fixed address → `ling-kernel`'s `arch/aarch64/boot.rs` (parks
  secondary cores, sets the stack pointer, zeroes `.bss` — raw binary
  loading has no ELF program headers to do that for you) →
  `kernel_entry()` → `__main__`.
- Both platforms compile kernel `.ling` source through the same AOT
  (Cranelift) pipeline as any other Ling program, cross-targeted by bare
  architecture name (`CraneliftBackend::new_for_arch`) rather than the
  host's native triple — necessary because building on a non-Linux host
  (this repo's dev machine is Windows) would otherwise emit COFF/Mach-O
  instead of the ELF the bare-metal linker step needs.
