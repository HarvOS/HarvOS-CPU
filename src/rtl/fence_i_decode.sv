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
module fence_i_decode (
  input  logic                   clk,
  input  logic                   rst_n,
  input  opcode_e    opcode,
  input  logic [2:0]             funct3,
  // Optionally track privilege, but not gating the pulse here
  input  priv_e      cur_priv,
  output logic                   fencei_flush_pulse  // 1-cycle pulse on FENCE.I
);
  // FENCE.I encoding: opcode = MISC-MEM (0x0F), funct3 = 3'b001
  wire is_fencei = (opcode == OPC_MISC_MEM) && (funct3 == 3'b001);
  logic seen_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) seen_q <= 1'b0;
    else        seen_q <= is_fencei;
  end
  assign fencei_flush_pulse = is_fencei & ~seen_q;
endmodule
