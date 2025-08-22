// dma_dummy_master.sv — simplistic DMA traffic generator for smoke-testing
`include "harvos_dmem_if.sv"
module dma_dummy_master (
  input  logic clk, input logic rst_n,
  input  logic enable,
  input  logic write_not_read,
  input  logic [31:0] base_addr,
  input  logic [31:0] len_words,
  harvos_dmem_if dma
);
  reg [31:0] cnt_q, cnt_n;
  reg        active_q, active_n;

  always @* begin
    cnt_n = cnt_q;
    active_n = active_q;
    dma.req   = 1'b0;
    dma.we    = write_not_read;
    dma.be    = 4'hF;
    dma.addr  = base_addr + (cnt_q<<2);
    dma.wdata = 32'hA5A5_0000 | cnt_q;

    if (!active_q) begin
      if (enable) begin
        active_n = 1'b1;
        cnt_n = 32'h0;
      end
    end else begin
      dma.req = 1'b1;
      if (dma.done) begin
        cnt_n = cnt_q + 1;
        if (cnt_q + 1 == len_words) active_n = 1'b0;
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_q <= 32'h0;
      active_q <= 1'b0;
    end else begin
      cnt_q <= cnt_n;
      active_q <= active_n;
    end
  end

  // default returns for read path to avoid X
  initial begin
    dma.rdata = '0;
    dma.done  = 1'b0;
    dma.fault = 1'b0;
  end
endmodule
