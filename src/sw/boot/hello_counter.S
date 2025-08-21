.section .text
.global _start
_start:
  /* set mtvec to 0 (not used here) */
  csrw mtvec, x0

  /* zero bss (optional minimal) */

  /* main: bump a counter in RAM and loop */
  la   t0, counter
  lw   t1, 0(t0)
  addi t1, t1, 1
  sw   t1, 0(t0)

1: j 1b

.section .bss
.align 4
.global counter
counter: .word 0
