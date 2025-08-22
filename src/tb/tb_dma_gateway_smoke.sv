// tb_dma_gateway_smoke.sv — minimal smoke test for dma_gateway + dma_firewall
`timescale 1ns/1ps
`include "src/rtl/harvos_dmem_if.sv"

`include "src/rtl/harvos_dma_firewall.sv"
`include "src/rtl/dma_dummy_master.sv"

module tb_dma_gateway_smoke;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0;

  // IFs
  harvos_dmem_if m0();
  harvos_dmem_if mux();
  // memory return wires
  reg [31:0]  m_rdata;
  reg         m_rvalid;
  reg         m_fault;

  // DUTs
  dma_gateway UGW (.clk(clk), .rst_n(rst_n), .dma_m0(m0), .dma_m1(mux), .dma_m2(mux), .dma_m3(mux), .dma_out(mux));

  harvos_dma_firewall #(.ROM_BYTES(32'd1024)) UFW (
    .clk(clk), .rst_n(rst_n),
    .cfg_en(1'b0), .cfg_we(1'b0), .cfg_addr(4'h0), .cfg_wdata(32'h0), .cfg_be(4'h0), .cfg_rdata(),
    .dma(mux),
    .fw_req(), .fw_we(), .fw_be(), .fw_addr(), .fw_wdata(),
    .m_rdata(m_rdata), .m_rvalid(m_rvalid), .m_fault(m_fault)
  );

  dma_dummy_master UDM (.clk(clk), .rst_n(rst_n), .enable(1'b0), .write_not_read(1'b1),
                        .base_addr(32'h0000_0004), .len_words(32'd4), .dma(m0));

  // Simple return: acknowledge any forwarded req next cycle (allowed transfers only)
  initial begin
    m_rdata  = 32'h0;
    m_rvalid = 1'b0;
    m_fault  = 1'b0;
  end
  always @(posedge clk) begin
    if (!rst_n) begin m_rvalid <= 1'b0; m_fault <= 1'b0; end
    else begin
      // When firewall forwards (not directly observable here), assume done next cycle
      m_rvalid <= 1'b1; // simplistic
      m_fault  <= 1'b0;
    end
  end

  initial begin
    // reset
    rst_n = 0;
    repeat(5) @(posedge clk);
    rst_n = 1;
    repeat(5) @(posedge clk);

    // 1) Write into I-space (0x0000_0004): expect DMA fault
    force UDM.enable = 1'b1;
    repeat(1) @(posedge clk);
    force UDM.enable = 1'b0;

    // Wait a bit
    repeat(20) @(posedge clk);

    if (m0.fault !== 1'b1) $display("FAIL: expected DMA fault for I-space write");
    else $display("PASS: DMA I-space write blocked");

    // 2) Write into RAM (0x0001_0000): change base, expect ok (no fault)
    force UDM.base_addr = 32'h0001_0000;
    force UDM.enable = 1'b1;
    repeat(1) @(posedge clk);
    force UDM.enable = 1'b0;

    repeat(20) @(posedge clk);
    if (m0.fault === 1'b1) $display("FAIL: unexpected fault for RAM write");
    else $display("PASS: DMA RAM write allowed");

    $finish;
  end
endmodule
