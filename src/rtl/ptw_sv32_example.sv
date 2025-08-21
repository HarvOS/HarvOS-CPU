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
// Example PTW fragment showing optional HW setting of A/D bits when required.
// In a real PTW, you would perform a memory write-back of the updated PTE.
module ptw_sv32_example #(
  parameter bit USE_HW_SET_AD = 1'b0
)(
  input  logic        clk, rst_n,
  input  logic        set_A_i,     // from permission check for the access
  input  logic        set_D_i,     // only for stores
  input  logic [31:0] pte_in_i,    // original PTE value (bits include A at [6], D at [7] if using RV order)
  output logic [31:0] pte_out_o,  // modified PTE
  output logic        pte_write_o // pulse: writeback to memory required
);
  // NOTE: Bit positions of A/D depend on your PTE layout. Adjust as needed.
  localparam integer BIT_A = 6;
  localparam integer BIT_D = 7;

  always_comb begin
    pte_out_o  = pte_in_i;
    pte_write_o= 1'b0;
    if (USE_HW_SET_AD) begin
      if (set_A_i && !pte_in_i[BIT_A]) begin
        pte_out_o[BIT_A] = 1'b1;
        pte_write_o      = 1'b1;
      end
      if (set_D_i && !pte_in_i[BIT_D]) begin
        pte_out_o[BIT_D] = 1'b1;
        pte_write_o      = 1'b1;
      end
    end
  end
endmodule
