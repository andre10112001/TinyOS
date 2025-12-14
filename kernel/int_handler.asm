
[BITS 32]

global general_handler

extern send_eoi        ; function to tell PIC "interrupt handled"

section .text

general_handler:
    cli
    call send_eoi
    sti 
    iret