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
// Minimal interrupt controller for HarvOS core
// ...
module irq_ctrl #(parameter bit USE_MMODE=1'b1, parameter integer CAUSE_TIMER=32'h8000_0007, parameter integer CAUSE_EXTERNAL=32'h8000_000B)
( input logic clk, rst_n, input logic timer_irq_i, ext_irq_i,
  input logic global_ie_i, en_timer_i, en_ext_i, pend_timer_i, pend_ext_i,
  output logic set_mtip_o, set_meip_o, take_irq_o, output logic [31:0] cause_o);
  assign set_mtip_o = timer_irq_i;
  assign set_meip_o = ext_irq_i;
  logic eff_timer = (pend_timer_i|timer_irq_i)&en_timer_i;
  logic eff_ext   = (pend_ext_i|ext_irq_i)&en_ext_i;
  logic any_irq = global_ie_i & (eff_timer|eff_ext);
  always_comb begin take_irq_o=1'b0; cause_o=32'b0;
    if(any_irq) begin take_irq_o=1'b1; cause_o= eff_timer? CAUSE_TIMER:CAUSE_EXTERNAL; end end
endmodule
