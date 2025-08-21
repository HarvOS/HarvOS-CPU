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

module simple_bootrom #(
  parameter integer WORDS = 4096  // 16 KiB
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        req,
  input  logic [31:0] addr,     // byte address
  output logic [31:0] rdata,
  output logic        rvalid,
  output logic        fault
);
  logic [31:0] rom [0:WORDS-1];
  logic [31:0] addr_q;
  logic        req_q;
  logic        in_range;

  assign in_range = (addr[31:2] < WORDS);
  assign fault    = req && !in_range;

  initial begin
`ifdef HARVOS_BOOTROM_HEX
    $display("BootROM: loading %s", `HARVOS_BOOTROM_HEX);
    $readmemh(`HARVOS_BOOTROM_HEX, rom);
`endif
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rvalid <= 1'b0;
      rdata  <= 32'h0;
      req_q  <= 1'b0;
      addr_q <= 32'h0;
    end else begin
      req_q  <= req && in_range;
      addr_q <= addr;
      rvalid <= req_q;
      if (req_q) rdata <= rom[addr_q[31:2]];
    end
  end
endmodule
