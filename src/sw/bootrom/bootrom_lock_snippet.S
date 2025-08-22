    .section .text.bootlock
    .globl harvos_boot_lock_mpu
    .type  harvos_boot_lock_mpu, @function
    .option norvc
    .align  2

# harvos_boot_lock_mpu:
# - Annahme: MPU-Regionen bereits programmiert (ROM=RX, RAM=RW (NX), MMIO=RW (NX,U=0))
# - Setzt smpuctl.LOCK (CSR 0x130, Bit0) und führt einen I-Cache Flush aus.
harvos_boot_lock_mpu:
    # Interrupts kurz deaktivieren (SIE=0)
    csrr    t0, sstatus
    li      t1, (1<<1)
    and     t0, t0, ~t1
    csrw    sstatus, t0

    # smpuctl.LOCK setzen (Bit0)
    li      t2, 1
    csrs    0x130, t2

    # I-Cache flush
    fence.i

    # SIE optional wieder setzen
    csrr    t0, sstatus
    ori     t0, t0, (1<<1)
    csrw    sstatus, t0

    ret
.size harvos_boot_lock_mpu, .-harvos_boot_lock_mpu
