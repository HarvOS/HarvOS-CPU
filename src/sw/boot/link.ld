ENTRY(_start)
MEMORY {
  ROM (rx) : ORIGIN = 0x00000000, LENGTH = 64K
  RAM (rw) : ORIGIN = 0x20000000, LENGTH = 64K
}
SECTIONS {
  .text : {
    *(.text.startup .text .text.*)
    *(.rodata .rodata.*)
  } > ROM
  .data : { *(.data .data.*) } > RAM AT > ROM
  .bss  : { *(.bss .bss.*) *(COMMON) } > RAM
}
