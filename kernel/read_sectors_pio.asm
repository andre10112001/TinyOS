; =======================================================
; read_sectors_pio: Protected Mode 32-bit ATA PIO I/O
; Input: [ebp+8] = LBA (32-bit)
;        [ebp+12]  = Count (8-bit)
;        [ebp+16]  = Buffer Address (32-bit)
; =======================================================
[BITS 32]
global read_sectors_pio

; ===================================
; ATA Register Port Definitions
; ===================================

; Primary Bus I/O Port Base (for Data/Error/Count/LBA/Command)
ATA_IO_BASE            equ 0x1F0

; Command Block Registers
ATA_DATA_PORT          equ ATA_IO_BASE + 0     ; 0x1F0 (R/W)
ATA_ERROR_PORT         equ ATA_IO_BASE + 1     ; 0x1F1 (R)
ATA_COUNT_PORT         equ ATA_IO_BASE + 2     ; 0x1F2 (R/W)
ATA_LBA_LOW            equ ATA_IO_BASE + 3     ; 0x1F3 (R/W)
ATA_LBA_MID            equ ATA_IO_BASE + 4     ; 0x1F4 (R/W)
ATA_LBA_HIGH           equ ATA_IO_BASE + 5     ; 0x1F5 (R/W)
ATA_DRIVE_PORT         equ ATA_IO_BASE + 6     ; 0x1F6 (R/W)
ATA_CMD_PORT           equ ATA_IO_BASE + 7     ; 0x1F7 (R/W Status)

; Control Block Registers
ATA_ALT_STATUS_PORT    equ 0x3F6               ; 0x3F6 (Read-only, used for 400ns delay)
; ATA_DEVICE_CONTROL   equ 0x3F6               ; 0x3F6 (Write-only, used for reset/interrupt mask)


read_sectors_pio:
    push ebp
    mov ebp, esp 

    mov esi, [ebp + 8]
    movzx ecx, byte [ebp+12]
    mov edi, [ebp + 16]

    ; 1. Send Count
    mov al, cl
    out ATA_COUNT_PORT, al      ; Send sector count

    ; 2. Send LBA (Low, Mid, High)
    mov eax, esi                ; EAX = LBA
    out ATA_LBA_LOW, al         ; Send LBA Bits 0-7
    
    shr eax, 8
    out ATA_LBA_MID, al         ; Send LBA Bits 8-15

    shr eax, 8
    out ATA_LBA_HIGH, al        ; Send LBA Bits 16-23

    ; 3. Select Drive and LBA bits 24-27
    ; LBA mode requires bits 7, 6, 5 to be set (111b). E0h is 11100000b.
    shr eax, 8              ; EAX now holds LBA bits 24-31 (previously 16-23)
    and al, 0x0F            ; Isolate LBA bits 24-27 (0000xxxx)
    or al, 0xE0             ; 0xE0 = LBA, Master Drive (11100000b)
    out ATA_DRIVE_PORT, al  ; Send to Drive/Head Register (0x1F6)


    ; 4. Send Read Command
    mov al, 0x20                ; 0x20 = READ SECTORS (with retries)
    out ATA_CMD_PORT, al

    ; 4b. Mandatory 400ns delay (Read Alternate Status 4 times)
    ; This ensures the drive has time to set the BSY bit before we poll it.
    in al, ATA_ALT_STATUS_PORT
    in al, ATA_ALT_STATUS_PORT
    in al, ATA_ALT_STATUS_PORT
    in al, ATA_ALT_STATUS_PORT

    ; 5. Wait for Disk Ready (Polling)
.wait_loop:
    in al, ATA_CMD_PORT         ; Read status register
    and al, 0x88                ; Check BSY (bit 7) and DRDY (bit 3)
    cmp al, 0x08                ; BSY must be 0, DRDY must be 1
    jne .wait_loop              ; Loop until disk is ready

; 6. Read Data Loop
.read_data:
    push ecx                    ; Save remaining count
    
    mov cx, 256                 ; 512 bytes per sector = 256 words
    rep insw                    ; Read 256 words (512 bytes) from port 0x1F0 into [EDI]
    
    pop ecx                     ; Restore remaining count
    loop .read_data             ; Loop for the number of sectors
    
    xor eax, eax                ; Return 0 (Success)
    
    mov esp, ebp                ; Clean up stack frame
    pop ebp
    ret 12                      ; Pop 12 bytes of arguments (3 args: 4+1+4, rounded to dword=12)