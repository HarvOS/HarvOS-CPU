// SV-to-V2005 shim (auto-inserted)
`ifndef HARVOS_SV2V_SHIM
`define HARVOS_SV2V_SHIM
`ifndef FORMAL
`define logic wire
`define always_ff always
`define always_comb always @*
`define always_latch always @*
`define bit wire
`endif
`endif

// (flatten) removed package block// mstatus bits (subset)
  localparam integer MSTATUS_MIE = 3;
  localparam integer MSTATUS_MPIE = 7;
  localparam integer MSTATUS_MPP_LO = 11;
  localparam integer MSTATUS_MPP_HI = 12;
  localparam integer MSTATUS_SIE = 1;
  localparam integer MSTATUS_SPIE = 5;
  localparam integer MSTATUS_SPP  = 8;

  // ECALL causes per mode
  localparam logic [4:0] SCAUSE_ECALL_UMODE = 5'd8;
  localparam logic [4:0] SCAUSE_ECALL_SMODE = 5'd9;
  localparam logic [4:0] SCAUSE_ECALL_MMODE = 5'd11;
