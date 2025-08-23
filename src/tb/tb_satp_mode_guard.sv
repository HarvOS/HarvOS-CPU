`timescale 1ns/1ps
module tb_satp_mode_guard;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0;

  // DUT
  reg        satp_wr_en;
  reg [31:0] satp_wr_wdata;
  reg [31:0] satp_q;
  wire [31:0] satp_wr_wdata_masked;
  wire        satp_wr_reject;
  wire        tlb_global_flush;

  satp_mode_guard u_guard (
    .clk(clk), .rst_n(rst_n),
    .satp_wr_en(satp_wr_en), .satp_wr_wdata(satp_wr_wdata),
    .satp_q(satp_q),
    .satp_wr_wdata_masked(satp_wr_wdata_masked),
    .satp_wr_reject(satp_wr_reject),
    .tlb_global_flush(tlb_global_flush)
  );

  // simple TLB valid model for asserts
  wire tlb_i_valid = 1'b1;
  wire tlb_d_valid = 1'b1;
  satp_mode_asserts u_asserts (
    .clk(clk), .rst_n(rst_n),
    .satp_q(satp_q),
    .tlb_i_valid(tlb_i_valid),
    .tlb_d_valid(tlb_d_valid)
  );

  task write_satp(input [3:0] mode, input [5:0] asid, input [21:0] ppn);
    begin
      satp_wr_wdata = {mode, asid, ppn};
      satp_wr_en    = 1'b1; @(posedge clk);
      satp_wr_en    = 1'b0; @(posedge clk);
      // latch masked value as CSR would do
      satp_q <= satp_wr_wdata_masked;
    end
  endtask

  initial begin
    // reset
    satp_wr_en=0; satp_wr_wdata=0; satp_q=32'h1000_0000; // MODE=1 default
    repeat(3) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

    // 1) Attempt to write MODE=0 must be rejected, but masked to MODE=1
    write_satp(4'd0, 6'h12, 22'h2ABCD);
    if (!satp_wr_reject) begin
      $display("FAIL: expected reject on MODE=0 write"); $fatal;
    end
    if (satp_q[31:28] !== 4'd1) begin
      $display("FAIL: masked write didn't force MODE=1"); $fatal;
    end

    // 2) Write with MODE=1 is fine; ASID change should cause flush
    write_satp(4'd1, 6'h33, 22'h2ABCD);
    if (!tlb_global_flush) begin
      $display("FAIL: expected tlb_global_flush on ASID change"); $fatal;
    end

    // 3) Same ASID/PPN -> no flush
    write_satp(4'd1, 6'h33, 22'h2ABCD);
    if (tlb_global_flush) begin
      $display("FAIL: unexpected flush on unchanged SATP"); $fatal;
    end

    $display("All satp_mode_guard tests passed.");
    $finish;
  end
endmodule
