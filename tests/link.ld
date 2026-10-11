ENTRY(_start)
SECTIONS {
 . = 0;
 .text : { *(.text.start) *(.text*) }
 .rodata : { *(.rodata*) }
 . = ALIGN(16);
 .data : { *(.data*) *(.sdata*) }
 .bss : { *(.bss*) *(.sbss*) *(COMMON) }
 /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame) }
}
