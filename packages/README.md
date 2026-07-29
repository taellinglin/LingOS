# LingOS packages

This is where installable packages live once the package manager exists.
Nothing in here is built yet — this file is the roadmap for what has to
exist first, and in what order, before each package below is buildable.

## Why this is empty right now

A package manager needs, at minimum: somewhere to install files to (a real
filesystem), a way to run more than one program, and a format to verify
before trusting. None of that exists yet. LingOS today is a single
`while` loop with no filesystem, no processes, and no persistent storage —
it boots fresh from the ISO/SD card every time. Building a package manager
before those foundations exist would just mean rebuilding it once they do.

## Build order

1. **Filesystem** (done for x86_64) — `lingfs`: a git-style content-addressed
   object store (blake3-hashed blobs/trees, dedup, append-only commit log
   for real history) as the root filesystem, on top of a real block device
   driver (ATA PIO + a full AHCI/SATA driver with automatic fallback, both
   verified in QEMU and real VirtualBox; SD/EMMC for RPi not started). The
   boot partition stays FAT32 — GRUB and the RPi firmware only know how to
   read that, it isn't replaceable. Compression and encryption layer onto
   each object next (see `ling-kernel/src/lingfs.rs`'s module doc); a real
   no_std crypto module (not `ling-crypto` directly — see below) is a
   prerequisite for the encryption half.
2. **Shell commands** (done, basic set) — `help`/`clear`/`ls [dir]`/
   `cat <name>`/`write <name> <text>`/`hostname`/`about`/`selftest`/`theme`
   operate on the real filesystem from step 1, in both the Live and Install
   shells. `dev/` and `bin/` are real (synthetic, re-seeded every mount)
   lingfs directories — `ls` shows them, `ls dev` shows whichever disk
   driver actually got detected this boot (`ahci0`/`ata0`), `ls bin` lists
   the built-in commands, `cat dev/<name>`/`cat bin/<name>` read them. The
   GRUB "Install" entry runs a real one-time setup wizard (mount/format the
   target disk, prompt for a hostname, persist it) before dropping into the
   same shell.
3. **Standalone disk boot** (done) — Install writes a real bootloader, so
   the installed disk boots without the Live CD/GRUB present at all;
   verified end-to-end (install a fresh disk, reboot with no CD attached,
   land in the same shell with the same persisted hostname). A custom MBR
   bootloader (`bootloader/stage1.asm` + `stage2.asm`, real-mode x86,
   assembled with `nasm`) since BIOS only loads 512 bytes and INT13h disk
   reads only work in real mode, but the kernel needs protected mode.
   `lingfs` starts at LBA 8192 (`LINGFS_BASE_LBA` in `lingfs.rs`) instead of
   LBA 0 specifically to leave room for this: LBA 0 is the MBR/stage1,
   LBA 1-16 is stage2, LBA 17 is a small kernel header (entry point + sizes,
   built by `bootloader/pack_header.py` from real `bootloader/elf_info.py`
   measurements of the linked ELF — not hand-guessed offsets), LBA 18+
   holds the flattened kernel image (`objcopy -O binary`; its trailing
   `.bss` isn't in the file at all, so stage2 zero-fills that region itself
   after copying, sized from the header). Stage2 enables A20, loads the
   whole kernel real-mode into one contiguous low-memory staging buffer via
   INT13h AH=42h (extended/LBA read — safe to assume on QEMU/VirtualBox/
   real hardware from the last ~25 years, no CHS fallback needed), then
   makes one switch to protected mode (flat GDT, `CR0.PE`) to copy it up to
   its 1MiB link address and jump in with `eax=0x36D76289`/`ebx=0` —
   `boot32.rs`'s `_start` already tolerated `ebx==0` (no Multiboot2 info),
   so no kernel-side changes were needed for this path. The installer gets
   the bootloader+kernel payload (`dist/diskboot-x86_64.img`, built by
   `live/build-diskboot-x86_64.sh`) via a Multiboot2 *module*
   (`live/grub.cfg`'s `module2` line) rather than an ISO9660 driver — GRUB
   reads the file off the CD itself and hands the installer a plain
   (address, size) pointer already in RAM, which
   `ling_kernel_disk_write_raw` writes straight to LBA 0, bypassing lingfs
   entirely (the one region it never touches).
4. **Package format + local install** (done) — `.lpkg`: a small
   length-prefixed binary format (`ling-kernel/src/packages.rs`) — magic,
   name, version, then a list of (filename, content) entries. `pkginstall
   <blob>` unpacks one already sitting in lingfs into its own one-level
   `pkg-<name>` directory and records `<name> -> version` under
   `packages/`; `ls packages`, `ls pkg-<name>`, `cat pkg-<name>/<file>`
   all just work (existing one-level-directory commands, nothing
   package-specific needed there). Still not signed (see step 5) — content
   is trusted as-is. **Not yet solved: getting a package's binary bytes
   onto the machine at all.** There's no network stack and no way to type
   binary content at a keyboard, so `write` can't carry a real package.
   The one proven path today is the same one the disk-boot bootloader
   payload uses: a Multiboot2 *module* (`ling_kernel_pkg_install_module`,
   verified end-to-end against a real host-built `.lpkg` delivered via
   `module2` in a GRUB config) — real, but only useful for one
   pre-baked-at-ISO-build-time package per boot today, not a general
   "install anything, anytime" flow yet. Also worth being explicit about:
   this kernel has **no process model**, so an installed package can only
   ever be data/config written into lingfs — there's no way to *run* an
   installed program separately from the one kernel image currently
   executing. That includes `ling-lang` itself: packaging it (as data)
   doesn't change the earlier infeasibility assessment below of actually
   running the compiler inside LingOS.
5. **Signing & verification, no_std** — `ling-crypto` has real primitives
   (AES-256-GCM, Argon2id, HKDF-SHA3, Blake3/SHA3 — see
   `ling/crates/ling-crypto`) but the crate itself assumes a hosted OS
   (`Vec`/`String`/`OsRng` throughout) and can't be linked into
   `ling-kernel` as-is. This needs a separate, kernel-native module using
   the same underlying crates in their `no_std`/in-place-AEAD mode (already
   done for hashing — see `ling-kernel/src/hash.rs`), plus a kernel-side
   entropy source (no OS `getrandom` on bare metal). Argon2id in
   particular needs its ~64MiB working set as a fixed *static* buffer
   (no heap = no problem, just no dynamic sizing) rather than the
   allocator-backed buffer the crate normally expects.
6. **User accounts + password hashing** — needs a real multi-user
   permission model, which needs a real process/privilege model, which the
   kernel doesn't have yet either. Password hashing itself (via the
   kernel-native crypto module above) is small and separable once there's
   somewhere to store the hash.
7. **A real public repository** (`pacman`/`apt`-style network fetch) — not
   started. This needs an actual server someone hosts and maintains
   security on indefinitely; that's a hosting decision, not a code change,
   and hasn't been made yet. Until then, "installing a package" means
   installing a file you already have.
8. **Full-disk encryption by default** — deliberately last. Encrypting a
   filesystem that doesn't fully exist yet, or claiming a distro is
   "secure by default" before there's a permission model to secure,
   would be a false claim. Once steps 1-5 are solid, this becomes: derive
   a key from a boot-time passphrase, encrypt the filesystem's block
   layer with it (AES via `ling-crypto`).

## Packages planned (not yet buildable)

- `ling-lang`/`lingfu` as installed commands (`ling build`, `ling run`,
  `ling ast`, …) — **assessed and currently infeasible, not just deferred.**
  `ling build`'s AOT path shells out to a full external `cargo`/`rustc`
  toolchain to link the generated object file (see how `ling build
  --platform kernel` itself works) — that's an entire hosted Rust
  toolchain, not something a freestanding kernel can invoke. `ling run`'s
  JIT path depends on `cranelift-jit`, which needs OS-level executable
  memory mapping and is written against `std`, with no realistic no_std
  port upstream. Both also assume a process model (load a binary, run it,
  reclaim its memory) that doesn't exist here yet — LingOS today runs one
  statically-linked kernel image, not "a kernel that launches programs."
  Making this real needs, at minimum: a no_std/`alloc`-only port of the
  compiler front end, a from-scratch no_std JIT or a switch to interpreting
  the MIR directly, and a program-loading/process abstraction in
  `ling-kernel`. `ling ast` alone (lex → parse → print, no codegen) is the
  one piece that *might* be narrow enough to port on its own — untested,
  and not attempted yet.
- A text editor with syntax highlighting (nano-like) — realistic on the
  current text-mode kernel once there's a filesystem to edit files on.
- A file manager, a picture/video/media player, a window manager, a
  MATE-style/`ling-sun-and-moon` desktop environment, a graphical installer
  wizard, and a `ling-ui` component crate (icons, dropdowns, checkboxes,
  radio buttons, text inputs, dark/light theming) — **greenlit as of
  2026-07-27** (previously deferred at the user's request across several
  earlier decisions; the user has now asked to start this work). Needs a
  graphics framebuffer driver first (none exists yet — build order:
  Multiboot2 linear framebuffer → 2D primitives/font rendering → window
  manager → desktop environment chrome), plus a heap allocator (the
  existing bump allocator in `ling-kernel/src/alloc.rs` never frees, fine
  for short-lived kernel objects but not for a long-running windowed UI)
  and, eventually, a process scheduler for running more than one graphical
  program at once. If/when `ling-ui` is built, it will not be published to
  crates.io without asking first, regardless of what's said elsewhere in
  the meantime.

## Git/GitHub compatibility — not the same thing as `lingfs`

`lingfs` (above) borrows git's *conceptual* model — content-addressed,
immutable objects, dedup, history via an append-only log — but it is not
git-compatible: it hashes with BLAKE3 (not SHA-1/SHA-256), has its own
on-disk layout, and has no network component at all. Actually talking to
a real GitHub repository needs, at minimum: a TCP/IP network stack (none
exists — no NIC driver, no networking code anywhere in `ling-kernel`),
TLS (GitHub requires HTTPS or SSH, not plain `git://`), and an
implementation of git's actual object format and smart-HTTP wire
protocol. That's three substantial subsystems stacked on top of each
other, each bigger than `lingfs` itself, and none has been started. Worth
doing eventually if LingOS wants real interop with existing git hosting,
but it's a distinct, much larger project from the filesystem work
currently in progress — not a checkbox on top of it.
