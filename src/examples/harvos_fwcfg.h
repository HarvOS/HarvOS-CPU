#ifndef HARVOS_FWCFG_H
#define HARVOS_FWCFG_H

#include <stdint.h>

#define FWCFG_BASE      0x1000F000u
#define FWCFG_CONTROL   (*(volatile uint32_t*)(FWCFG_BASE + 0x00)) // bit0=LOCK (write 1 to set, sticky)
#define FWCFG_ROM_BYTES (*(volatile uint32_t*)(FWCFG_BASE + 0x04)) // I-space threshold (bytes)
#define FWCFG_PBASE0    (*(volatile uint32_t*)(FWCFG_BASE + 0x08)) // region0 base
#define FWCFG_PMASK0    (*(volatile uint32_t*)(FWCFG_BASE + 0x0C)) // region0 mask
#define FWCFG_PCTRL0    (*(volatile uint32_t*)(FWCFG_BASE + 0x10)) // bit0=WRITE_ONLY

static inline void fwcfg_lock(void) { FWCFG_CONTROL = 1u; }

static inline void fwcfg_program(uint32_t rom_bytes,
                                 uint32_t pbase0, uint32_t pmask0, uint32_t write_only)
{
    FWCFG_ROM_BYTES = rom_bytes;
    FWCFG_PBASE0    = pbase0;
    FWCFG_PMASK0    = pmask0;
    FWCFG_PCTRL0    = (write_only & 1u);
}

#endif // HARVOS_FWCFG_H
