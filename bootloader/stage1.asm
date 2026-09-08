; LingOS disk-boot stage1 (MBR boot sector).
;
; BIOS loads this at 0x7C00 in 16-bit real mode, DL = boot drive number, and
; jumps to it. All this stage does: set up a stack, load stage2 (LBA 1-16,
; see the layout below) right after itself at 0x7E00 via one INT13h
; extended (LBA) read, and jump into it. No CHS fallback — INT13h AH=42h
; (extended read) has been mandatory on any BIOS shipped in the last ~25
; years (anything supporting disks over 8.4GB), and this only ever boots a
; disk LingOS's own installer just formatted, so there's no "unknown old
; hardware" case to be defensive about.
;
; On-disk layout (see ling-kernel/src/lingfs.rs's LINGFS_BASE_LBA doc, which
; this must stay in sync with):
;   LBA 0        this file (512 bytes)
;   LBA 1-16     stage2 (8KiB)
;   LBA 17       kernel header (magic/size, see stage2.asm)
;   LBA 18-32767 flattened kernel image (~16MiB budget)
;   LBA 32768+   lingfs volume
[bits 16]
[org 0x7C00]

STAGE2_SEG equ 0x0000
STAGE2_OFF equ 0x7E00
STAGE2_LBA equ 1
STAGE2_SECTORS equ 16
BOOT_DRIVE_ADDR equ 0x0500 ; shared with stage2.asm -- keep in sync

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    ; Stashed at a fixed, shared low-memory address (not a label inside this
    ; sector) so stage2 -- a separately assembled file -- can read it too.
    mov [BOOT_DRIVE_ADDR], dl

    mov si, dap
    mov ah, 0x42
    mov dl, [BOOT_DRIVE_ADDR]
    int 0x13
    jc disk_error

    jmp STAGE2_SEG:STAGE2_OFF

disk_error:
    mov si, err_msg
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

err_msg: db "LingOS: stage1 disk read failed", 0

; Disk Address Packet for INT13h AH=42h.
align 4
dap:
    db 0x10          ; packet size
    db 0              ; reserved
    dw STAGE2_SECTORS ; sectors to read
    dw STAGE2_OFF     ; transfer buffer offset
    dw STAGE2_SEG      ; transfer buffer segment
    dq STAGE2_LBA      ; starting LBA

times 510 - ($ - $$) db 0
dw 0xAA55
