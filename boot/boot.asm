; boot.asm - simple bootloader
[BITS 16]
[ORG 0x7C00]


start_1:
    jmp short start          ; Jump over BPB
    nop                         ; padding

OEMName: db "MYOS    "          ; 8 bytes
; -----------------------------
; BIOS Parameter Block (BPB) - FAT12
; -----------------------------
BytesPerSector      dw 512      ; 0x0200
SectorsPerCluster   db 1        ; 1 sector per cluster
ReservedSectors     dw 1        ; boot sector reserved
NumFATs             db 2
MaxRootDirEntries   dw 224
TotalSectorsShort   dw 2880     ; small total sectors
MediaDescriptor     db 0xF0
SectorsPerFAT       dw 9
SectorsPerTrack     dw 18
NumberOfHeads       dw 2
HiddenSectors       dd 0
TotalSectorsLong    dd 0

; Extended BPB
DriveNumber         db 0
Reserved1           db 0
BootSignature       db 0x29
VolumeID            dd 0x12345678
VolumeLabel         db "NO NAME    "
FileSystemType      db "FAT12   "





start:
    cli                 ; disable interrupts
    xor ax, ax
    mov ds, ax
    mov es, ax
    call load_root
    call load_fat
    call find_kernel
    call load_file

halt_loop:
    hlt 
    jmp halt_loop



; --- Assume RootDirSectors has been calculated and stored ---
; --- The result will be stored in [DataAreaStartLBA] ---
KERNEL_LOAD_ADDR equ 0x1000

load_file:
    ; 1. Calculate the size of the FAT Region (2 FATs * 9 Sectors/FAT = 18)
    mov al, [NumFATs]               ; AL = 2
    cbw                             ; AX = 2
    mov cx, [SectorsPerFAT]         ; CX = 9
    mul cx                          ; AX = 18 (Size of both FATs)
    
    ; 2. Add Root Directory size (14 sectors)
    add ax, [RootDirSectors]        ; AX = 18 + 14 = 32
    
    ; 3. Add Reserved Region size (1 sector)
    add ax, [ReservedSectors]       ; AX = 32 + 1 = 33
    
    mov [DataAreaStartLBA], ax      ; Store the result: LBA 33

        ; 1. Convert LBA to CHS
    mov ax, [DataAreaStartLBA]  ; AX = LBA 33
    
    ; We need to preserve BX and the original AX value used for CHS setup
    ; Assume ES is already 0x0000
    mov bx, KERNEL_LOAD_ADDR    ; BX = 0x1000 (The destination offset)
    mov cx, [kernel_first_cluster]
read_cluster:
    ; 2. Set up INT 13h parameters
    push cx
    push ax                     ; Save AX (LBA)
    push bx                     ; Save BX (if it was holding anything important)
    mov di, ax
    call lba_to_chs             ; Sets CH, CL, DH based on AX (LBA)
                                ; *** Assumes lba_to_chs restores AX, BX, DX, etc. ***
    pop bx                      ; Restore BX (if necessary)
    pop ax                      ; Restore AX (if necessary)
        ; 3. Set the Destination Buffer (ES:BX)
    mov ah, 0x02                ; Read sector
    mov al, 1                   ; 1 sector (SectorsPerCluster)
    mov dl, 0x00                ; Drive 0 (Floppy)
    
    int 0x13
    jc disk_error

done_reading:
    ; ----------------------------------------------------
    ; STEP 1: Find Next Cluster Number (N_next)
    ; Assume CX holds the current cluster number (N)
    ; ----------------------------------------------------
    pop cx
    push bx                         ; Preserve BX (holds the load address)
    push ax                         ; Preserve AX (might hold LBA)
    
    mov ax, cx                      ; AX = Current Cluster Number (N)
    call get_next_cluster           ; Function returns N_next in AX.
                                    ; (See implementation below)
    
    mov cx, ax                      ; CX = Next Cluster Number (N_next)
    
    pop ax                          ; Restore AX
    pop bx                          ; Restore BX (kernel load address)

    ; ----------------------------------------------------
    ; STEP 2: Check for End-Of-File (EOF) or Error
    ; ----------------------------------------------------
    
    ; FAT12 EOF markers range from 0xFF8 to 0xFFF
    cmp cx, 0xFF8                   
    jge kernel_loaded               ; If N_next >= 0xFF8, we're done!

    ; Check for error clusters (0xFF0 to 0xFF6)
    cmp cx, 0xFF0
    jge fat_error                   ; If N_next >= 0xFF0, there might be a bad cluster

    ; ----------------------------------------------------
    ; STEP 3: Continue Reading
    ; ----------------------------------------------------
    
    ; Advance the memory buffer for the next read
    add bx, 512                     ; BX = BX + 512 (Next memory location for the kernel)
    
    ; Calculate the LBA of the new cluster (N_next)
    mov ax, cx                      ; AX = N_next (the new cluster number)
    call cluster_to_lba             ; AX returns the new LBA
    
    jmp read_cluster    ; Jump back to the LBA-to-CHS conversion and INT 13h call

fat_error:
    ; ... (Handle error or halt)
    jmp disk_error

kernel_loaded:
    ; Kernel is fully loaded, transfer control!
    jmp 0x0000:0x1000                 ; Jump to the kernel entry point (0x1000)


; --- Assumptions ---
; [DataAreaStartLBA] is calculated (e.g., 33)
; [SectorsPerCluster] is 1 (from BPB)

cluster_to_lba:
    ; Input: AX = Cluster number N
    ; Output: AX = Calculated LBA

    push cx                     ; Preserve CX, as it might hold the cluster loop counter
    push dx                     ; Preserve DX

    ; 1. Calculate N - 2
    sub ax, 2                       ; AX = N - 2
    
    ; 2. Multiply by SectorsPerCluster
    ; We need to calculate: (N - 2) * SectorsPerCluster.
    
    ; Check if SectorsPerCluster is 1 (the likely scenario for your FAT12 setup)
    cmp byte [SectorsPerCluster], 1
    je skip_multiplication          ; If 1, no multiplication needed (AX remains AX * 1)
    
    ; --- Full multiplication required if SectorsPerCluster > 1 ---
    mov cl, [SectorsPerCluster]     ; CL = SectorsPerCluster
    xor ch, ch                      ; Clear CH
    mul cx                          ; AX = AX * CX (result is 16-bit, safe in AX)
                                    ; DX is unused here
    
skip_multiplication:
    
    ; 3. Add DataAreaStartLBA
    add ax, [DataAreaStartLBA]      ; AX = LBA of Cluster N
    
    ; The result (LBA) is now in AX

    pop dx
    pop cx
    ret




get_next_cluster:
    ; AX = Cluster number to look up (N)
    push bx
    push dx
    
    ; 1. Calculate the byte offset: (N * 1.5)
    mov bx, ax                      ; BX = N
    shr bx, 1                       ; BX = N / 2
    add bx, ax                      ; BX = N + (N/2) = 1.5 * N (Offset in bytes)
    
    add bx, fat_buffer            ; BX = Physical address in RAM of the 2-byte window
    
    mov dx, word [bx]               ; Read the 2 bytes (16 bits) into DX
    
    ; 2. Unpack the 12-bit entry based on Odd/Even cluster number
    test al, 0x01                   ; Check if N is an ODD cluster (AL is the low byte of N)
    jnz is_odd_cluster
    
    ; If N is EVEN: Keep the low 12 bits (mask off the upper 4 bits)
    and dx, 0x0FFF                  
    jmp get_next_cluster_end
    
is_odd_cluster:
    ; If N is ODD: Shift 4 bits right (get the high 12 bits)
    shr dx, 4                       
    
get_next_cluster_end:
    mov ax, dx                      ; AX = 12-bit next cluster value (0-0xFFF)
    
    pop dx
    pop bx
    ret








kernel_name:     db "KERNEL  "     ; 8 bytes name (padded with spaces)
kernel_ext:      db "BIN"          ; 3 bytes extension
kernel_first_cluster:   dw 0               ; will store first cluster number of kernel
file_size:       dd 0               ; optional, size in bytes

section .text
find_kernel:
    mov cx, [MaxRootDirEntries]    ; CX = Loop counter (224 entries)
    mov si, root_dir_buffer    ; BX = Pointer to the current 32-byte entry

find_kernel_loop:
    ; 1. Check for end of directory or erased entry
    cmp byte [si], 0x00         ; Is it the end of the directory (0x00)?
    je not_found                ; If yes, file not found.

    cmp byte [si], 0xE5         ; Is it an erased entry (0xE5)?
    je next_entry               ; If yes, skip it.

    ; 2. Compare the 8-byte Name (Bytes 0-7)
    push cx                     ; Save entry counter
    
    mov di, kernel_name         ; DI = Source (the target name)
    mov bx, si                  ; Use BX to hold the current directory entry address
    mov cx, 8                   ; Compare 8 bytes
    repe cmpsb                  ; Repeatedly compares [SI] to [DI]. Sets ZF=1 if match.

    jnz name_mismatch           ; If ZF=0 (no match), skip to next_entry cleanup
    
    ; 3. Compare the 3-byte Extension (Bytes 8-10)
    ; SI is now at offset 8 (the extension field of the directory entry)
    mov di, kernel_ext          ; DI = Source (the target extension)
    mov cx, 3                   ; Compare 3 bytes
    repe cmpsb                  ; Compares [SI+8] to [DI]. Sets ZF=1 if match.

    jnz name_mismatch           ; If ZF=0 (no match), skip to next_entry cleanup

    ; --- KERNEL.BIN FOUND! ---
    
    ; 4. Extract the First Cluster (Offset 26)
    ; BX still holds the original entry address (SI was the iterator, DI the search string)
    mov ax, word [bx + 26]      ; AX = 16-bit word at Entry Address + 26
    mov [kernel_first_cluster], ax ; Store the cluster number (0x0002)

    pop cx                      ; Restore loop counter (we are done)
    jmp found_kernel_complete

name_mismatch:
    pop cx                      ; Restore entry counter

next_entry:
    add si, 32      ; Move SI 32 bytes to the next entry
    loop find_kernel_loop       ; Decrement CX and loop if not zero

not_found:
    ; ... error handling ...
    jmp disk_error

found_kernel_complete:
    ret


load_fat:
    mov di, 1
    mov bx, fat_buffer
    mov si, [SectorsPerFAT]
load_fat_loop:
    push di    
    push bx 
    push si 

    mov ax, di
    call lba_to_chs            ; Convert DI (LBA) to CHS (sets CH, CL, DH)

    ; Read 1 sector
    mov ah, 0x02               ; Read sector
    mov al, 1                  ; 1 sector
    mov dl, 0x00               ; Drive 0 (Floppy)

    pop si 
    pop bx 
    pop di
    int 0x13
    jc disk_error

    ; Update loop variables (must happen after popa if using pusha/popa)
    add bx, 512                ; Advance memory buffer by 512 bytes
    inc di                     ; Next LBA
    dec si                     ; Decrement sector counter
    jnz load_fat_loop



; Load the Root section into memory
load_root:

    ; LBA of the Root section (bx) 
    mov al, [NumFATs]
    cbw
    mov cx, [SectorsPerFAT]
    mul cx
    add ax, [ReservedSectors]
    mov [RootDirLBA], ax

    ; Total number of sectors
    mov ax, [MaxRootDirEntries]
    mov cx, 32
    mul cx
    mov cx, [BytesPerSector]
    xor dx, dx
    div cx
    mov [RootDirSectors], ax


mov di, [RootDirLBA]        ; DI = starting LBA
mov bx, root_dir_buffer     ; BX = memory destination
mov si, [RootDirSectors]    ; SI = number of sectors to read
load_root_loop:
    ; Save registers that CHS routine destroys
    push di
    push bx
    push si

    ; DI = LBA (copy to AX for CHS conversion)
    mov ax, di
    call lba_to_chs          ; sets CH, CL, DH

    ; Read 1 sector
    mov ah, 0x02             ; read sector
    mov al, 1                ; number of sectors
    mov dl, 0x00             ; floppy

    pop si
    pop bx
    pop di
    int 0x13
    jc disk_error

    ;popa

    ; Advance memory buffer
    add bx, 512

    ; Next LBA
    inc di

    ; Loop using SI (safe)
    dec si
    jnz load_root_loop
    ret




    mov ah, 0x02     ; read sector
    mov al, 1        ; sectors per read
    mov dl, 0        ; drive A
    int 0x13
    jc disk_error       ; jump if error

    ; Jump to kernel
    jmp 0x0000:0x1000







lba_to_chs:
    mov ax, [NumberOfHeads]     ; AX = HPC
    mov bx, [SectorsPerTrack]   ; BX = SPT
    mul bx                       ; DX:AX = HPC*SPT
    mov si, ax                   ; SI = HPC*SPT (36)
    mov ax, di         ; AX = LBA (0x0E)
    xor dx, dx                   ; clear DX for division
    div si                        ; AX = LBA / (HPC*SPT), DX = remainder
    mov ch, al                   ; CH = cylinder

    mov ax, di
    mov bx, [SectorsPerTrack]
    xor dx, dx
    div bx              ; AX = quotient = LBA / SPT = 1, DX = remainder = LBA % SPT = 1
    mov cl, dl          ; CL = remainder
    inc cl              ; CL = 1 + remainder = 2

    mov ax, di
    mov bx, [SectorsPerTrack]  ; BX = SPT = 18
    xor dx, dx          ; clear DX for div
    div bx              ; AX = quotient, DX = remainder
    mov si, ax          ; SI = quotient = 1
    mov ax, si          ; AX = quotient
    mov bx, [NumberOfHeads] ; CX = HPC = 2
    xor dx, dx
    div bx              ; AX = ignored, DX = remainder
    mov dh, dl          ; DH = head
    ret



disk_error:
    hlt                 ; hang on error
    jmp $



; Fill to 512 bytes
times 510-($-$$) db 0
dw 0xAA55




section .data
msg db "Boot error or kernel not found!", 0

; --- Buffers ---
DataAreaStartLBA: dw 0
RootDirLBA dw 0   ; reserve 2 bytes for the LBA of the root directory
RootDirSectors dw 0   ; reserve 2 bytes for the total number of sectors in Root dir
root_dir_buffer: times 7168 db 0   ; 14 sectors × 512 bytes = 7168 B
fat_buffer:      times 9*512 db 0  ; FAT1 = 9 sectors × 512 B (optional)


section .bss
; --- Temporary / scratch variables ---
temp_entry:      resb 32            ; one directory entry size


