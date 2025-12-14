; Reprogram PIC Programable Interrup Controller

[BITS 32]

global pic_init
global send_eoi

pic_init:
    ; Restarting the PICs
    mov al, 0x11
    out 0x20, al 
    out 0xA0, al 

    ; Reprogram adresses
    mov al, 0x20
    out 0x21, al 
    mov al, 0x28 
    out 0xA1, al 

    mov al, 0x04
    out 0x21, al     ;setup cascading
    mov al, 0x02
    out 0xA1, al

    mov al, 0x01
    out 0x21, al
    out 0xA1, al     ;done!
    ret

send_eoi:
    mov al, 0x20
    out 0x20, al        ; tell master PIC interrupt handled
    ret