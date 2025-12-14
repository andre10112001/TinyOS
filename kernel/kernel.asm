[BITS 16]

extern pic_init
extern _idt_set_gate
extern idt
extern idt_descriptor
extern general_handler
extern test_disk_read

global start

section .text.start
start:
    cli
    lgdt [gdt_descriptor]

    mov eax, cr0
    or eax, 1           ; set PE bit
    mov cr0, eax

    jmp 0x08:protected_mode_entry

[BITS 32]
protected_mode_entry:
    mov ax, 0x10        ; data segment selector
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000    ; stack


    call pic_init       ; Reprogram PIC 


mov ecx, 0           ; vector index
populate_idt_loop:
    mov eax, general_handler
    mov ebx, ecx      ; vector number
    call _idt_set_gate
    inc ecx
    cmp ecx, 256
    jl populate_idt_loop


    ; Load IDT
    mov word [idt_descriptor], 256*8 - 1
    mov eax, idt
    mov [idt_descriptor+2], eax
    lidt [idt_descriptor]

    call test_disk_read
    call print_hello

    sti                 ; allow interrupts


kernel_idle_loop:
    hlt
    jmp kernel_idle_loop




print_hello:
    ; Register Preservation (Good practice)
    pusha           ; Save all general-purpose registers (EAX, ECX, EDX, EBX, ESP, EBP, ESI, EDI)

    mov edi, 0xB8000    ; EDI = Destination Address (Start of Video Memory)
    mov esi, hello_msg  ; ESI = Source Address (Address of the string)
    mov ebx, 0x07       ; EBX = Attribute (0x07 = Light Gray on Black)
                        ; (The attribute byte is written after every character)
    
.print_loop:
    ; 1. Load the next character
    lodsb               ; Load Byte from [DS:ESI] into AL, then increment ESI
    
    ; 2. Check for End-of-String (0-byte)
    cmp al, 0           ; Check if AL is the null terminator (0)
    je .print_done      ; If yes, finish printing
    
    ; 3. Write Character to Video Memory
    mov [edi], al       ; Write the character (in AL) to the video cell (EDI)
    
    ; 4. Write Attribute Byte
    mov [edi+1], bl     ; Write the attribute byte (in BL) to the next byte
    
    ; 5. Advance Video Memory Pointer
    add edi, 2          ; Move to the next character cell (each cell is 2 bytes: char + attribute)
    
    jmp .print_loop     ; Loop back for the next character

.print_done:
    popa            ; Restore all general-purpose registers
    ret             ; Return to the caller (e.g., kernel_idle_loop)






; GDT table
gdt_start:
    dq 0                 ; null descriptor

    ; code segment
    dw 0xFFFF            ; limit low
    dw 0x0000            ; base low
    db 0x00              ; base middle
    db 10011010b         ; access byte: present, ring0, code, executable
    db 11001111b         ; flags: 4K granularity, 32-bit
    db 0x00              ; base high

    ; data segment
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10010010b         ; access byte: present, ring0, data, writable
    db 11001111b
    db 0x00
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1    ; limit
    dd gdt_start                  ; base



section .data
hello_msg db "Hello from the kernel", 0  ; The string, terminated by a null byte (0)
