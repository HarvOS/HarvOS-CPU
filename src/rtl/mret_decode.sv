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
module mret_decode (
  input  logic                 clk,
  input  logic                 rst_n,
  input  opcode_e  opcode,
  input  logic [2:0]           funct3,
  input  logic [31:0]          imm_i,
  input  priv_e    cur_priv,
  output logic                 mret_pulse  // 1-cycle pulse when valid MRET in M-mode
);
  // SYSTEM opcode + funct3==000 + imm[11:0]==12'h302 → MRET
  wire is_mret = (opcode == OPC_SYSTEM) &&
                 (funct3 == 3'b000) &&
                 (imm_i[11:0] == 12'h302);
  wire mret_ok = is_mret && (cur_priv == PRIV_M);
  logic seen_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) seen_q <= 1'b0;
    else        seen_q <= mret_ok;
  end
  assign mret_pulse = mret_ok & ~seen_q;
endmodule
