`timescale 1ns/1ps
module tb_mpu_nx_ram;
  logic clk=0, rst_n=0;
  always #5 clk = ~clk;

  // Instantiate MPU (assumed interface)
  // You may need to adjust ports to your actual mpu.sv
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

  initial begin
    // reset
    rst_n=0; cur_priv = PRIV_S; is_fetch=0; is_load=0; is_store=0; addr=32'h0;
    repeat(3) @(posedge clk);
    rst_n=1; @(posedge clk);

    // Program: mark RAM region non-executable (assumes default policy in MPU already NX for RAM)
    // Try to fetch from 0x8000_0000 (typical RAM base)
    addr = 32'h8000_0000; is_fetch=1; is_load=0; is_store=0; @(posedge clk);
    is_fetch=0;
    // Check
    if (!fault_exec) $fatal(1, "Expected execute fault on RAM fetch");
    else $display("OK: NX-RAM fetch faulted");

    $finish;
  end
endmodule
