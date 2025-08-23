// satp_mode_asserts.sv — SVA-style safety properties for "paging always on"
`timescale 1ns/1ps

module satp_mode_asserts (
  input  wire        clk,
  input  wire        rst_n,
  input  wire [31:0] satp_q,
  input  wire        tlb_i_valid,
  input  wire        tlb_d_valid
);
  // synopsys translate_off

  // A1: MODE is never 0 after reset is deasserted
  property p_mode_never_zero;
    @(posedge clk) disable iff (!rst_n)
      satp_q[31:28] != 4'd0;
  endproperty
  assert property (p_mode_never_zero)
    else $error("SATP.MODE became 0 - paging must always be enabled");

  // A2: If MODE were (hypothetically) 0, TLBs must not hold valid entries (defensive)
  property p_no_tlb_valid_if_mode_zero;
    @(posedge clk) disable iff (!rst_n)
      (satp_q[31:28] == 4'd0) |-> (!tlb_i_valid && !tlb_d_valid);
  endproperty
  assert property (p_no_tlb_valid_if_mode_zero)
    else $error("TLBs valid while SATP.MODE==0 (should not happen)");

  // synopsys translate_on
endmodule
