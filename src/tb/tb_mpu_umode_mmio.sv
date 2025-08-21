`timescale 1ns/1ps
module tb_mpu_umode_mmio;
  logic clk=0, rst_n=0;
  always #5 clk = ~clk;
  logic [31:0] addr;
  logic        is_fetch;
  logic        is_load;
  logic        is_store;
  priv_e cur_priv;
  logic allow, fault_exec, fault_load, fault_store;

  mpu DUT (
    .clk(clk), .rst_n(rst_n),
    .addr(addr),
    .is_fetch(is_fetch),
    .is_load(is_load),
    .is_store(is_store),
    .cur_priv(cur_priv),
    .allow(allow),
    .fault_exec(fault_exec),
    .fault_load(fault_load),
    .fault_store(fault_store)
  );

  localparam MMIO_ADDR = 32'h1000_0000; // example MMIO base

  initial begin
    rst_n=0; cur_priv = PRIV_U; is_fetch=0; is_load=0; is_store=0; addr=32'h0;
    repeat(3) @(posedge clk);
    rst_n=1; @(posedge clk);

    // Try to store to MMIO in U-mode -> should fault
    addr = MMIO_ADDR; is_store=1; @(posedge clk);
    is_store=0;
    if (!fault_store) $fatal(1, "Expected store fault on U-mode MMIO access");
    else $display("OK: U-mode MMIO store faulted");

    $finish;
  end
endmodule
