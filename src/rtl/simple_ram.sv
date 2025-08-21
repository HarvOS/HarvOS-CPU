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


module simple_ram #(
  parameter integer WORDS = 16384
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        req,
  input  logic        we,
  input  logic [3:0]  be,
  input  logic [31:0] addr,
  input  logic [31:0] wdata,
  output logic [31:0] rdata,
  output logic        rvalid,
  output logic        fault
);
  logic [31:0] mem [0:WORDS-1];
  logic [31:0] waddr_q;
  logic        req_q, we_q;
  logic [3:0]  be_q;
  logic [31:0] wdata_q;
  logic        in_range;

  assign in_range = (addr[31:2] < WORDS);
  assign fault    = req && !in_range;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      req_q   <= 1'b0;
      we_q    <= 1'b0;
      be_q    <= 4'h0;
      waddr_q <= 32'h0;
      wdata_q <= 32'h0;
      rvalid  <= 1'b0;
      rdata   <= 32'h0;
    end else begin
      req_q   <= req && in_range;
      we_q    <= we;
      be_q    <= be;
      waddr_q <= addr;
      wdata_q <= wdata;

      rvalid  <= req_q;
      if (req_q) begin
        if (we_q) begin
          mem[waddr_q[31:2]] <= ((mem[waddr_q[31:2]]) & ~{ {8{be_q[3]}}, {8{be_q[2]}}, {8{be_q[1]}}, {8{be_q[0]}} }) | (({ wdata_q[31:24], wdata_q[23:16], wdata_q[15:8], wdata_q[7:0] }) & { {8{be_q[3]}}, {8{be_q[2]}}, {8{be_q[1]}}, {8{be_q[0]}} });
          rdata <= d;
        end else begin
          rdata <= mem[waddr_q[31:2]];
        end
      end
    end
  end
endmodule

