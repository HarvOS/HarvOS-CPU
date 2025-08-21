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

// SPDX-License-Identifier: MIT
// Minimal MPU execute-permission model for simulation
module mpu_exec_model #(
  parameter logic [31:0] NX_BASE = 32'h2000_0000,
  parameter logic [31:0] NX_END  = 32'h2FFF_FFFF
)(
  input  logic        addr_valid_i,
  input  logic [31:0] paddr_i,
  output logic        exec_allow_o
);
  always_comb begin
    exec_allow_o = 1'b1;
    if (addr_valid_i) begin
      if (paddr_i >= NX_BASE && paddr_i <= NX_END) exec_allow_o = 1'b0;
    end
  end
endmodule
