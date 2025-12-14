[BITS 32]

global _idt_set_gate 
global idt
global idt_descriptor



section .data
align 8
idt: times 256*8 db 0       ; allocate 256*8 bytes initialized to 0


idt_descriptor:
    dw 0
    dd 0 

section .text

; EBX = vector number (0...255)
; EAX = handler adress
_idt_set_gate:
    push ebp
    push ecx
    mov ebp, esp 

    ; Compute entry adress 
    mov edx, idt
    mov ecx, ebx 
    shl ecx, 3
    add edx, ecx

    ; Fill entry
    mov word [edx], ax           ; offset low
    mov word [edx+2], 0x08       ; selector (kernel code segment)
    mov byte [edx+4], 0          ; zero
    mov byte [edx+5], 0x8E       ; type & attributes
    shr eax, 16
    mov word [edx+6], ax         ; offset high

    pop ecx
    pop ebp
    ret
