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
`include "harvos_pkg_flat.svh"
module imem_rom #(
  parameter integer WORDS = 4096,
  parameter [1023:0] HEXFILE = "hello.hex"
)(
  input  logic        clk,
  input  logic        rst_n,
  harvos_imem_if.slave imem
);
  logic [31:0] mem[0:WORDS-1];
  initial begin
    $display("[imem_rom] loading %s ...", HEXFILE);
    $readmemh(HEXFILE, mem);
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      imem.rvalid <= 1'b0;
      imem.fault  <= 1'b0;
      imem.rdata  <= '0;
    end else begin
      imem.rvalid <= imem.req;
      imem.fault  <= 1'b0;
      imem.rdata  <= mem[imem.addr[31:2]];
    end
  end
endmodule
