#include "harvos_fwcfg.h"

// Example: block any DMA R/W to 0x3000_0000..0x3000_FFFF (mask 0xFFFF_0000),
// allow DMA writes only restriction via WRITE_ONLY=1 if desired.
void harvos_firewall_boot_init(void) {
    // Set I-space threshold (ROM_BYTES) to 64 KiB (0x0001_0000)
    fwcfg_program(0x00010000u,  // ROM_BYTES
                  0x30000000u,  // PBASE0
                  0xFFFF0000u,  // PMASK0
                  0u);          // WRITE_ONLY=0 → block reads & writes
    fwcfg_lock();               // make config sticky
}
