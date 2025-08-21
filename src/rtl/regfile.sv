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


module regfile (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        we,
  input  logic [4:0]  waddr,
  input  logic [31:0] wdata,
  input  logic [4:0]  raddr1,
  input  logic [4:0]  raddr2,
  output logic [31:0] rdata1,
  output logic [31:0] rdata2
);
  
  // ----- Hoisted declarations for Yosys SV parser -----
  integer i;  // hoisted from procedural decl

logic [31:0] rf[31:1]; // x0 hardwired to 0

  // read
  assign rdata1 = (raddr1 == 5'd0) ? 32'h0 : rf[raddr1];
  assign rdata2 = (raddr2 == 5'd0) ? 32'h0 : rf[raddr2];

  // write
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin



      for (i = 1; i < 32; i++) rf[i] <= 32'h0;
    end else if (we && waddr != 5'd0) begin
      rf[waddr] <= wdata;
    end
  end
endmodule
