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
LFB_INFO_ADDR    equ 0x6000   ; VBE handoff block (keep in sync with
                              ; framebuffer.rs's disk-boot fallback)
LFB_INFO_MAGIC   equ 0x4942464C ; "LFBI" little-endian
CODE_SEL         equ 0x08
DATA_SEL         equ 0x10
KERNEL_HEADER_MAGIC equ 0x474E4B4C ; keep in sync with pack_header.py's MAGIC

start:
    mov dl, [BOOT_DRIVE_ADDR]

    ; --- Dual-boot: if the MBR carries a valid, active, non-LingOS bootable
    ; partition (e.g. a Windows/Linux install this LingOS was installed
    ; alongside), offer a short boot menu and chainload it on request. A raw
    ; whole-disk LingOS install writes an all-zero partition table here
    ; (stage1 zero-pads 0x1BE..0x1FD), so this is completely inert on a
    ; single-boot disk -- it falls straight through to booting LingOS. ---
    call maybe_boot_menu

    ; --- Enable A20 (BIOS call, then fast-A20 port as a harmless backup) ---
    mov ax, 0x2401
    int 0x15
    in al, 0x92
    or al, 2
    out 0x92, al

    ; --- Enter unreal mode: briefly flip to protected mode to load DS/ES
    ; with the flat 4GiB data descriptor, then drop back to real mode. The
    ; 386+ keeps the cached 4GiB segment LIMIT across the return (real-mode
    ; segment reloads only change the base), so `a32 rep movsd` can write
    ; above 1MiB from real mode. This removes the old design's hard cap:
    ; the whole kernel had to fit in low memory (staging ceiling ~589KiB),
    ; and the graphics-desktop kernel is already at 559KiB and growing.
    ; BIOS int 10h/13h keep working -- they run real-mode code below 1MiB
    ; and never notice the wider limits.
    cli
    lgdt [gdt_desc]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    mov bx, DATA_SEL
    mov ds, bx
    mov es, bx
    and eax, 0xFFFFFFFE
    mov cr0, eax
    xor bx, bx
    mov ds, bx
    mov es, bx
    sti

    ; --- Read the on-disk kernel header (1 sector, fixed LBA) FIRST, so
    ; the display-mode preference byte (offset 16) is available before the
    ; VBE mode-set below. ---
    mov si, header_dap
    mov ah, 0x42
    int 0x13
    jc disk_error

    ; --- VBE: set a linear-framebuffer graphics mode BEFORE loading the
    ; kernel, and leave a tagged handoff block at LFB_INFO_ADDR for
    ; framebuffer.rs's disk-boot path (no Multiboot2 info exists here).
    ; The preferred-mode list starts at the byte the user persisted
    ; (header offset 16 -> DISPLAY_MODES table), then falls through the
    ; rest so a mode the hardware lacks still lands on something. On total
    ; VBE failure the handoff block isn't written and the kernel runs
    ; framebuffer-less (serial/VGA text still work).
    movzx bx, byte [header_buf + 16]
    cmp bx, DISPLAY_MODE_COUNT
    jb .pref_ok
    xor bx, bx
.pref_ok:
    ; Try the preferred mode first.
    mov si, display_modes
    add si, bx
    add si, bx                       ; *2 (word entries)
    mov ax, [si]
    mov [vbe_try_mode], ax
    call vbe_try
    jnc .vbe_done
    ; Then walk the whole table in order as fallbacks.
    xor bx, bx
.vbe_fallback:
    cmp bx, DISPLAY_MODE_COUNT
    jae .vbe_done
    mov si, display_modes
    add si, bx
    add si, bx
    mov ax, [si]
    mov [vbe_try_mode], ax
    call vbe_try
    jnc .vbe_done
    inc bx
    jmp .vbe_fallback
.vbe_done:

    cmp dword [header_buf], KERNEL_HEADER_MAGIC
    jne header_error

    mov eax, [header_buf + 4]   ; file_size_sectors
    mov [total_sectors], eax
    mov [remaining_sectors], eax
    mov eax, [header_buf + 8]   ; entry_phys
    mov [kernel_entry], eax
    mov eax, [header_buf + 12]  ; bss_extra_bytes
    mov [bss_extra], eax

    ; --- Load the kernel: bounce each 32KiB chunk through the fixed low
    ; staging buffer, then unreal-copy it straight up to its 1MiB link
    ; address. The destination cursor is 32-bit; the kernel image can now
    ; be as large as RAM, not as large as low memory.
    mov dword [cur_dest], KERNEL_LINK_BASE
    mov dword [cur_lba], KERNEL_START_LBA
    mov word [chunk_seg], STAGING_SEG

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

    mov eax, [cur_lba]
    mov [chunk_lba], eax

    mov si, chunk_dap
    mov ah, 0x42
    int 0x13
    jc disk_error

    ; Unreal copy: DS/ES still carry 4GiB cached limits from the dance
    ; above; bases are 0, so esi/edi are plain linear addresses.
    movzx ecx, word [chunk_count]
    shl ecx, 7               ; sectors -> dwords (512/4 = 128)
    mov esi, STAGING_SEG << 4
    mov edi, [cur_dest]
    cld
    a32 rep movsd
    mov [cur_dest], edi

    movzx eax, word [chunk_count]
    add [cur_lba], eax
    sub [remaining_sectors], eax
    jmp .load_loop

.load_done:
    cli
    lgdt [gdt_desc]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp CODE_SEL:pm_entry

; --- VBE helper: query [vbe_try_mode]; if it exists with a linear
; framebuffer and 24/32bpp, set it (LFB bit 14) and write the handoff
; block. Returns CF clear on success, set on failure. Real mode, es=0.
vbe_try:
    mov ax, 0x4F01
    mov cx, [vbe_try_mode]
    mov di, vbe_mode_buf
    int 0x10
    cmp ax, 0x004F
    jne .fail
    test byte [vbe_mode_buf], 0x80  ; ModeAttributes bit 7: LFB supported
    jz .fail
    mov al, [vbe_mode_buf + 0x19]   ; BitsPerPixel
    cmp al, 24
    je .bpp_ok
    cmp al, 32
    jne .fail
.bpp_ok:
    mov ax, 0x4F02
    mov bx, [vbe_try_mode]
    or bx, 0x4000                    ; bit 14: use the linear framebuffer
    int 0x10
    cmp ax, 0x004F
    jne .fail
    ; Handoff block for framebuffer.rs's disk-boot path.
    mov dword [LFB_INFO_ADDR], LFB_INFO_MAGIC
    mov eax, [vbe_mode_buf + 0x28]  ; PhysBasePtr
    mov [LFB_INFO_ADDR + 4], eax
    movzx eax, word [vbe_mode_buf + 0x10] ; BytesPerScanLine
    mov [LFB_INFO_ADDR + 8], eax
    movzx eax, word [vbe_mode_buf + 0x12] ; XResolution
    mov [LFB_INFO_ADDR + 12], eax
    movzx eax, word [vbe_mode_buf + 0x14] ; YResolution
    mov [LFB_INFO_ADDR + 16], eax
    movzx eax, byte [vbe_mode_buf + 0x19] ; BitsPerPixel
    mov [LFB_INFO_ADDR + 20], eax
    clc
    ret
.fail:
    stc
    ret

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
cur_dest: dd 0
cur_lba: dd 0
vbe_try_mode: dw 0

align 4
header_buf: times 512 db 0
align 4
vbe_mode_buf: times 256 db 0

; Display-mode table -- index by the persisted preference byte (header
; offset 16). VBE mode numbers for linear-framebuffer graphics; must stay
; in sync with drivers/display.rs's list and the Settings Display row.
;   0 = 1024x768  1 = 800x600  2 = 1280x1024  3 = 640x480  4 = 1280x720
display_modes:
    dw 0x0118, 0x0115, 0x011B, 0x0111, 0x0117
DISPLAY_MODE_COUNT equ 5

; --- Dual-boot menu + chainloader (real mode) ------------------------------
; Reads the MBR partition table; if an active partition with a known bootable
; type exists, prints a menu and, on '2', chainloads that partition's boot
; sector the standard way (VBR -> 0x7C00, DL = drive, DS:SI -> the partition
; entry). '1'/Enter/timeout falls through to booting LingOS. Returns (to keep
; booting LingOS) when there's nothing to offer or the user declines.
maybe_boot_menu:
    pusha
    ; Read the MBR (LBA 0) into mbr_buf.
    mov si, mbr_dap
    mov ah, 0x42
    mov dl, [BOOT_DRIVE_ADDR]
    int 0x13
    jc .done                       ; unreadable -> just boot LingOS
    ; Scan the 4 primary partition entries for an active, bootable one.
    mov si, mbr_buf + 0x1BE
    mov cx, 4
.scan:
    mov al, [si]                   ; boot flag: must be 0x80 (active)
    cmp al, 0x80
    jne .next
    mov al, [si + 4]               ; partition type: must be whitelisted
    call is_bootable_type
    jc .found
.next:
    add si, 16
    loop .scan
    jmp .done                      ; no other OS -> boot LingOS
.found:
    mov [chain_entry], si
    mov si, menu_msg
    call print_str
    ; ~5 second countdown using the BIOS tick counter at 0040:006C (ds=0).
    mov eax, [0x046C]
    add eax, 91                    ; 18.2 ticks/s * 5s
    mov [deadline_ticks], eax
.wait:
    mov ah, 0x01                   ; any key pressed?
    int 0x16
    jz .no_key
    xor ah, ah
    int 0x16                       ; consume it
    cmp al, '2'
    je .chain
    jmp .done                      ; any other key -> boot LingOS
.no_key:
    mov eax, [0x046C]
    cmp eax, [deadline_ticks]
    jb .wait
    jmp .done                      ; timeout -> boot LingOS
.chain:
    mov si, [chain_entry]
    mov eax, [si + 8]              ; partition start LBA (LBA32 in the entry)
    mov [vbr_lba], eax
    mov dword [vbr_lba + 4], 0
    mov si, vbr_dap
    mov ah, 0x42
    mov dl, [BOOT_DRIVE_ADDR]
    int 0x13
    jc .done                       ; VBR read failed -> boot LingOS
    ; Hand off exactly like a real MBR: DL = drive, DS:SI -> partition entry.
    mov dl, [BOOT_DRIVE_ADDR]
    mov si, [chain_entry]
    jmp 0x0000:0x7C00
.done:
    popa
    ret

; CF=1 if AL is a partition type we'll offer to chainload (common bootable
; filesystems: FAT12/16/32, NTFS/exFAT, Linux).
is_bootable_type:
    cmp al, 0x07                   ; NTFS / exFAT / HPFS
    je .yes
    cmp al, 0x0B                   ; FAT32 (CHS)
    je .yes
    cmp al, 0x0C                   ; FAT32 (LBA)
    je .yes
    cmp al, 0x06                   ; FAT16
    je .yes
    cmp al, 0x0E                   ; FAT16 (LBA)
    je .yes
    cmp al, 0x83                   ; Linux
    je .yes
    cmp al, 0x01                   ; FAT12
    je .yes
    clc
    ret
.yes:
    stc
    ret

; Print a NUL-terminated string via BIOS teletype (ds:si).
print_str:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    jmp print_str
.done:
    ret

menu_msg:
    db 13, 10, "LingOS boot menu:", 13, 10
    db "  1) LingOS  (default)", 13, 10
    db "  2) other OS on this disk", 13, 10
    db "booting LingOS shortly -- press 2 for the other OS...", 13, 10, 0

align 4
mbr_dap:
    db 0x10
    db 0
    dw 1
    dw mbr_buf
    dw 0
    dq 0
align 4
vbr_dap:
    db 0x10
    db 0
    dw 1
    dw 0x7C00
    dw 0
vbr_lba: dq 0
chain_entry: dw 0
deadline_ticks: dd 0
align 4
mbr_buf: times 512 db 0

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
    ; The kernel is already at its link address (the load loop unreal-
    ; copied each chunk as it was read) -- only .bss remains: zero-fill
    ; right after the file content.
    mov edi, KERNEL_LINK_BASE
    mov eax, [total_sectors]
    shl eax, 9              ; sectors -> bytes
    add edi, eax
    mov ecx, [bss_extra]
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
