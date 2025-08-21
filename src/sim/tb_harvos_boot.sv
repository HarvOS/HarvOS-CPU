`timescale 1ns/1ps
`include "harvos_pkg_flat.svh"
`include "bus_if.sv"

module tb_harvos_boot;
  logic clk=0, rst_n=0;
  always #5 clk = ~clk;

  // Harvard buses
  harvos_imem_if imem(clk);
  harvos_dmem_if dmem(clk);

  // Simple DMEM: 1-cycle latency R/W
  logic [31:0] RAM[0:16383]; // 64 KiB
  always_ff @(posedge clk) begin
    dmem.rvalid <= dmem.req;
    dmem.fault  <= 1'b0;
    if (dmem.req) begin
      if (dmem.we) begin
        if (dmem.be[0]) RAM[dmem.addr[31:2]][7:0]   <= dmem.wdata[7:0];
        if (dmem.be[1]) RAM[dmem.addr[31:2]][15:8]  <= dmem.wdata[15:8];
        if (dmem.be[2]) RAM[dmem.addr[31:2]][23:16] <= dmem.wdata[23:16];
        if (dmem.be[3]) RAM[dmem.addr[31:2]][31:24] <= dmem.wdata[31:24];
      end else begin
        dmem.rdata <= RAM[dmem.addr[31:2]];
      end
    end
  end

  // ROM on I-port
  imem_rom #(.WORDS(4096), .HEXFILE("hello.hex")) ROM(.clk(clk), .rst_n(rst_n), .imem(imem));

  // DUT
  harvos_core DUT(.clk(clk), .rst_n(rst_n), .imem(imem), .dmem(dmem), .entropy_valid(1'b0), .entropy_data('0));

  // Reset & run
  initial begin
    rst_n = 0; repeat(5) @(posedge clk); rst_n = 1;
    // run for some cycles, then check that counter incremented
    repeat(500) @(posedge clk);
    if (RAM['h20000000>>2] == 32'd0) begin
      $display("FAIL: counter was not incremented"); $fatal;
    end else begin
      $display("OK: counter value = %0d", RAM['h20000000>>2]);
    end
    $finish;
  end

endmodule
