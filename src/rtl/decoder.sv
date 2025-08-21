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
module decoder (
  input  logic [31:0] instr,
  output logic        valid,
    output logic [6:0] opcode,
  output logic [2:0]  funct3,
  output logic [6:0]  funct7,
  output logic [4:0]  rd,
  output logic [4:0]  rs1,
  output logic [4:0]  rs2,
  output logic [31:0] imm_i,
  output logic [31:0] imm_s,
  output logic [31:0] imm_b,
  output logic [31:0] imm_j,
  output logic [31:0] imm_u,
  output logic          is_clrreg,
  output logic          is_clrmem
  );
    assign opcode = instr[6:0];
  assign rd     = instr[11:7];
  assign funct3 = instr[14:12];
  assign rs1    = instr[19:15];
  assign rs2    = instr[24:20];
  assign funct7 = instr[31:25];

  // immediates
  assign imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
  assign imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
  assign imm_j = {
    {11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
  assign imm_u = {instr[31:12], 12'b0};

  // Security opcode decodes (custom-0)
  assign is_clrreg = (instr[6:0] == `OPCODE_SEC) && (instr[14:12] == `FUNCT3_CLRREG);
  assign is_clrmem = (instr[6:0] == `OPCODE_SEC) && (instr[14:12] == `FUNCT3_CLRMEM);

  assign valid = 1'b1; // structural validity checked later
endmodule
