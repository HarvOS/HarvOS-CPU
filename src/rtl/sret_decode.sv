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
module sret_decode (
  input  logic                 clk,
  input  logic                 rst_n,
  input  opcode_e  opcode,
  input  logic [2:0]           funct3,
  input  logic [31:0]          imm_i,     // sign-extended imm (we'll check [11:0])
  input  priv_e    cur_priv,
  output logic                 sret_pulse // 1-cycle pulse when valid SRET in S-mode
);
  // SYSTEM opcode + funct3==000 + imm[11:0]==12'h102 indicates SRET
  wire is_sret = (opcode == OPC_SYSTEM) &&
                 (funct3 == 3'b000) &&
                 (imm_i[11:0] == 12'h102);

  // Only honor SRET in S-mode (in M-mode this would be MRET; U-mode illegal)
  wire sret_ok = is_sret && (cur_priv == PRIV_S);

  // Edge-pulse
  logic seen_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) seen_q <= 1'b0;
    else        seen_q <= sret_ok;
  end
  assign sret_pulse = sret_ok & ~seen_q;
endmodule
