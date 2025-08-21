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

// Very small free-running timer
module timer_simple #(parameter integer PERIOD=1000)(input logic clk,rst_n, output logic irq_o);
  logic [$clog2(PERIOD):0] cnt_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin cnt_q <= '0; irq_o <= 1'b0; end
    else begin
      if(cnt_q==PERIOD-1) begin cnt_q<='0; irq_o<=1'b1; end
      else begin cnt_q<=cnt_q+1'b1; irq_o<=1'b0; end
    end
  end
endmodule
