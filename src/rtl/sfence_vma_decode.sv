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

// sfence_vma_decode.sv
// Decodes SFENCE.VMA rs1, rs2 and produces flush signals for MMU/TLBs.
// Usage: instantiate in the execute stage with access to decoded fields and RF read values.
`include "harvos_pkg_flat.svh"
module sfence_vma_decode (
  input  logic        clk,
  input  logic        rst_n,
  // decoded fields
  input  opcode_e opcode,
  input  logic [2:0]  funct3,
  input  logic [6:0]  funct7,
  input  logic [4:0]  rs1,
  input  logic [4:0]  rs2,
  // register values
  input  logic [31:0] rs1_val,
  input  logic [31:0] rs2_val,
  // privilege (S-mode required in RISC-V for SFENCE.VMA; M-mode may emulate)
  input  priv_e cur_priv,

  // outputs to MMU
  output logic        sfence_flush_all,
  output logic        sfence_addr_valid,
  output logic [31:0] sfence_vaddr,
  output logic        sfence_asid_valid,
  output logic [15:0]  sfence_asid
);
  // Detect SFENCE.VMA (RV32 privileged spec): opcode=SYSTEM (0x73), funct3=000, funct7=0001001 (0x09).
  wire is_sfence_vma = (opcode == OPC_SYSTEM) &&
                       (funct3 == 3'b000) &&
                       (funct7 == 7'h09);

  // For simplicity we do not gate by privilege here; upstream should ensure only S/M mode executes.
  // Generate one-cycle pulse when SFENCE is seen.
  logic seen_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) seen_q <= 1'b0;
    else        seen_q <= is_sfence_vma;
  end
  wire pulse = is_sfence_vma & ~seen_q;

  // Address and ASID selection per spec:
  // rs1=x0 -> apply to all addresses; otherwise rs1_val is VA.
  // rs2=x0 -> apply to all ASIDs; otherwise lower 9 bits of rs2_val is ASID.
  assign sfence_addr_valid = pulse & (rs1 != 5'd0);
  assign sfence_vaddr      = rs1_val;
  assign sfence_asid_valid = pulse & (rs2 != 5'd0);
  assign sfence_asid       = rs2_val[15:0];
  assign sfence_flush_all  = pulse & (rs1 == 5'd0) & (rs2 == 5'd0);

endmodule
