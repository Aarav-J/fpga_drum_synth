ENTRY(_start)
MEMORY { 
    RAM (rwx) :  ORIGIN = 0x00000000, LENGTH = 0x1000 
}

SECTIONS { 
    .text : { 
        *(.text.start)
        *(.text)
        *(.text*)
        *(.rodata)
        *(.rodata*)
    } > RAM

    .data : { 
        _sdata = .; 
        *(.data)
        *(.data*)
        _edata = .; 
    } > RAM

    .bss : { 
        _sbss = .; 
        *(.bss)
        *(.bss*)
        *(COMMON)
        _ebss = .; 
    } > RAM
}
