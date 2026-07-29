; LingOS disk-boot stage2. Loaded by stage1 at 0x7E00, real mode, still
; 16-bit. Responsible for everything stage1 was too small (512 bytes) to
; do: enable A20, load the kernel image, switch to protected mode, and jump
; into the kernel with the same register convention GRUB's Multiboot2
; handoff uses (so `ling-kernel`'s `boot32.rs::_start` needs no changes at
; all for this boot path).
;
; The kernel is linked at 1MiB (`KERNEL_LINKER_SCRIPT`'s `. = 1M;`), but
; real-mode INT13h reads can't target memory much past 1MiB directly (the
; DAP's transfer buffer is a 16-bit segment:offset pair). Since the whole
; flattened kernel comfortably fits in conventional low memory (~450KiB,
; confirmed against the actual build — nowhere near the ~600KiB available
; below 0xA0000), the simplest correct approach beats a cleverer one: load
; the entire kernel real-mode, into one contiguous staging area starting at
; linear 0x10000, THEN make one single switch to protected mode and do one
; `rep movsd` to copy it up to 0x100000 — no repeated real/protected-mode
; toggling, no INT15h AH=87h "move extended memory" call needed.
;
; `objcopy -O binary`'s flat kernel image does NOT include `.bss` (it's a
; trailing NOBITS section with no file content — confirmed by actually
; running objcopy on a real build and checking the output size). So after
; copying the file content up, this also zero-fills `bss_extra_bytes` (from
; the on-disk header, computed at build time from the ELF's real total
; memory footprint minus the flat file's real size — not a hand-guessed
; offset) immediately after it, matching what the kernel's linker script
; expects to find zeroed at its `.bss` address.
[bits 16]
[org 0x7E00]

BOOT_DRIVE_ADDR  equ 0x0500  ; stage1 stashes the BIOS boot-drive number here
HEADER_LBA       equ 17
KERNEL_START_LBA equ 18
CHUNK_SECTORS    equ 64      ; 32KiB/read -- stays within one 64KiB real-mode segment
STAGING_SEG      equ 0x1000  ; linear 0x10000: contiguous low-memory staging area
KERNEL_LINK_BASE equ 0x100000 ; must match KERNEL_LINKER_SCRIPT's `. = 1M;`
CODE_SEL         equ 0x08
DATA_SEL         equ 0x10
KERNEL_HEADER_MAGIC equ 0x474E4B4C ; keep in sync with pack_header.py's MAGIC

start:
    mov dl, [BOOT_DRIVE_ADDR]

    ; --- Enable A20 (BIOS call, then fast-A20 port as a harmless backup) ---
    mov ax, 0x2401
    int 0x15
    in al, 0x92
    or al, 2
    out 0x92, al

    ; --- Read the on-disk kernel header (1 sector, fixed LBA) ---
    mov si, header_dap
    mov ah, 0x42
    int 0x13
    jc disk_error

    cmp dword [header_buf], KERNEL_HEADER_MAGIC
    jne header_error

    mov eax, [header_buf + 4]   ; file_size_sectors
    mov [total_sectors], eax
    mov [remaining_sectors], eax
    mov eax, [header_buf + 8]   ; entry_phys
    mov [kernel_entry], eax
    mov eax, [header_buf + 12]  ; bss_extra_bytes
    mov [bss_extra], eax

    ; --- Load the whole kernel into one contiguous staging area ---
    mov word [cur_seg], STAGING_SEG
    mov dword [cur_lba], KERNEL_START_LBA

.load_loop:
    mov eax, [remaining_sectors]
    or eax, eax
    jz .load_done
    mov ecx, CHUNK_SECTORS
    cmp eax, ecx
    jae .chunk_size_ok
    mov ecx, eax
.chunk_size_ok:
    mov [chunk_count], cx

    mov ax, [cur_seg]
    mov [chunk_seg], ax
    mov eax, [cur_lba]
    mov [chunk_lba], eax

    mov si, chunk_dap
    mov ah, 0x42
    int 0x13
    jc disk_error

    movzx eax, word [chunk_count]
    add [cur_lba], eax
    sub [remaining_sectors], eax
    shl eax, 5              ; sectors -> paragraphs (512/16 = 32 per sector)
    add [cur_seg], ax
    jmp .load_loop

.load_done:
    cli
    lgdt [gdt_desc]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp CODE_SEL:pm_entry

disk_error:
    mov si, err_msg
    jmp print_and_halt
header_error:
    mov si, hdr_err_msg
print_and_halt:
.print:
    lodsb
    or al, al
    jz .halt
    mov ah, 0x0E
    int 0x10
    jmp .print
.halt:
    hlt
    jmp .halt

err_msg: db "LingOS: stage2 disk read failed", 0
hdr_err_msg: db "LingOS: no kernel installed (bad header)", 0

align 4
header_dap:
    db 0x10
    db 0
    dw 1
    dw header_buf
    dw 0
    dq HEADER_LBA

align 4
chunk_dap:
    db 0x10
    db 0
chunk_count: dw 0
    dw 0
chunk_seg: dw 0
chunk_lba: dq 0

total_sectors: dd 0
remaining_sectors: dd 0
kernel_entry: dd 0
bss_extra: dd 0
cur_seg: dw 0
cur_lba: dd 0

align 4
header_buf: times 512 db 0

align 8
gdt_start:
    dq 0
    ; flat code: base 0, limit 0xFFFFF (x4KiB via G=1) -> 4GiB
    dw 0xFFFF, 0x0000
    db 0x00, 10011010b, 11001111b, 0x00
    ; flat data
    dw 0xFFFF, 0x0000
    db 0x00, 10010010b, 11001111b, 0x00
gdt_end:
gdt_desc:
    dw gdt_end - gdt_start - 1
    dd gdt_start

[bits 32]
pm_entry:
    mov ax, DATA_SEL
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000

    cld
    ; Copy the staged kernel image up to its link address.
    mov esi, STAGING_SEG << 4
    mov edi, KERNEL_LINK_BASE
    mov eax, [total_sectors]
    shl eax, 9              ; sectors -> bytes
    mov ecx, eax
    add ecx, 3
    shr ecx, 2               ; round up to whole dwords
    rep movsd

    ; Zero-fill .bss right after the copied file content (edi is already
    ; sitting at KERNEL_LINK_BASE + file_size_bytes here).
    mov eax, [bss_extra]
    mov ecx, eax
    add ecx, 3
    shr ecx, 2
    xor eax, eax
    rep stosd

    mov eax, 0x36D76289     ; Multiboot2 magic -- boot32.rs::_start never
                             ; actually checks it, but costs nothing to set.
    xor ebx, ebx             ; no Multiboot2 info structure on this path;
                             ; framebuffer.rs already tolerates ebx == 0.
    jmp dword [kernel_entry]

times 8192 - ($ - $$) db 0
