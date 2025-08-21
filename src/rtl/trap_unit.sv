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


`include "harvos_pkg_flat.svh"
module trap_unit (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        trap_req,
  input  [4:0]        trap_scause,
  input  [31:0]       trap_stval,
  input  [31:0]       cur_pc,
  input  [31:0]       csr_stvec_q,
  output logic [31:0] trap_target_pc,
  output logic [31:0] sepc_to_write
);
  // precise traps: record faulting PC, vector to stvec
  assign sepc_to_write   = cur_pc;
  assign trap_target_pc  = csr_stvec_q; // aligned earlier

endmodule
