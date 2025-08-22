// -----------------------------
// HarvOS capability bits (SCAPS)
// -----------------------------
// [0] W^X enforced
// [1] NX on D-path
// [2] Paging always on
// [3] DMA firewall present
// [4] Sv32 MMU scheme
// [5] Strict Harvard (separate I/D + Harvard trap)
// [6] FENCE.I supported
// [7..31] reserved (0)
`ifndef HARVOS_SCAPS_BITS_DEFINED
  localparam int unsigned SCAPS_WX_ENFORCED_BIT    = 0;
  localparam int unsigned SCAPS_NX_D_BIT           = 1;
  localparam int unsigned SCAPS_PAGING_ALWAYS_BIT  = 2;
  localparam int unsigned SCAPS_DMA_FW_BIT         = 3;
  localparam int unsigned SCAPS_SV32_BIT           = 4;
  localparam int unsigned SCAPS_HARVARD_BIT        = 5;
  localparam int unsigned SCAPS_FENCEI_BIT         = 6;
  `define HARVOS_SCAPS_BITS_DEFINED
`endif

// CSR address for SCAPS
`ifndef CSR_SCAPS
  localparam logic [11:0] CSR_SCAPS = 12'h140;
`endif
