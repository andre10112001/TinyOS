SECTIONS
{
    /* Start kernel at 0x1000 */
    . = 0x1000;

    /* Place the start.o code first */
    .text : {
        KEEP(*(.text.start))   /* keep only symbols labeled start */
    }

    /* Then place the rest of the kernel .text sections */
    .text_rest : {
        *(.text.*)
    }

    .data : { *(.data) }
    .bss  : { *(.bss) }
}