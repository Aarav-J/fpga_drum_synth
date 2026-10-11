.section .text.start
.global _start

_start:
    li sp, 0x1000

    la a0, _sbss
    la a1, _ebss
    bge a0, a1, bss_done

bss_loop:
    sw zero, 0(a0) // store word
    addi a0, a0, 4 // Add 4(next word)
    blt a0, a1, bss_loop // Check if a0 < a1 if so continue loop

bss_done:
    call main

hang:
    j hang
