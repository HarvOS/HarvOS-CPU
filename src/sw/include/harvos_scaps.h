#pragma once
#include <stdint.h>

#define CSR_SCAPS 0x140u

#define SCAPS_WX_ENFORCED_BIT     0u
#define SCAPS_NX_D_BIT            1u
#define SCAPS_PAGING_ALWAYS_BIT   2u
#define SCAPS_DMA_FW_BIT          3u
#define SCAPS_SV32_BIT            4u
#define SCAPS_HARVARD_BIT         5u
#define SCAPS_FENCEI_BIT          6u

#define SCAPS_WX_ENFORCED     (1u << SCAPS_WX_ENFORCED_BIT)
#define SCAPS_NX_D            (1u << SCAPS_NX_D_BIT)
#define SCAPS_PAGING_ALWAYS   (1u << SCAPS_PAGING_ALWAYS_BIT)
#define SCAPS_DMA_FW          (1u << SCAPS_DMA_FW_BIT)
#define SCAPS_SV32            (1u << SCAPS_SV32_BIT)
#define SCAPS_HARVARD         (1u << SCAPS_HARVARD_BIT)
#define SCAPS_FENCEI          (1u << SCAPS_FENCEI_BIT)

static inline uint32_t csr_read_scaps(void) {
  uint32_t v;
  asm volatile ("csrr %0, %1" : "=r"(v) : "i"(CSR_SCAPS));
  return v;
}
