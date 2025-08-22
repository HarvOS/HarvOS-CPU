// SPDX-License-Identifier: MIT
// dma_gateway.sv — Central DMA arbiter + funnel into single harvos_dmem_if
// Verilog-2005 friendly (no arrays/typedefs).
// Priority: m0 > m1 > m2 > m3. Grant holds until transaction 'done'.
//
// Ports:
//   - dma_m[0..3] : harvos_dmem_if master modports
//   - dma_out     : harvos_dmem_if master modport toward firewall
//
`include "harvos_dmem_if.sv"

module dma_gateway (
  input  logic clk,
  input  logic rst_n,
  // masters
  harvos_dmem_if dma_m0,
  harvos_dmem_if dma_m1,
  harvos_dmem_if dma_m2,
  harvos_dmem_if dma_m3,
  // consolidated output to firewall
  harvos_dmem_if dma_out
);
  // Grant FSM
  localparam [2:0] G_IDLE=3'd0, G_M0=3'd1, G_M1=3'd2, G_M2=3'd3, G_M3=3'd4;
  reg [2:0] g_q, g_n;

  // latch request info? Not necessary; hold grant until done.
  always @* begin
    g_n = g_q;
    case (g_q)
      G_IDLE: begin
        if (dma_m0.req) g_n = G_M0;
        else if (dma_m1.req) g_n = G_M1;
        else if (dma_m2.req) g_n = G_M2;
        else if (dma_m3.req) g_n = G_M3;
      end
      G_M0: if (dma_out.done) g_n = G_IDLE;
      G_M1: if (dma_out.done) g_n = G_IDLE;
      G_M2: if (dma_out.done) g_n = G_IDLE;
      G_M3: if (dma_out.done) g_n = G_IDLE;
      default: g_n = G_IDLE;
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) g_q <= G_IDLE;
    else g_q <= g_n;
  end

  // Drive consolidated output based on grant
  always @* begin
    // defaults
    dma_out.req   = 1'b0;
    dma_out.we    = 1'b0;
    dma_out.be    = 4'h0;
    dma_out.addr  = 32'h0;
    dma_out.wdata = 32'h0;
    // defaults for masters
    dma_m0.rdata  = 32'h0; dma_m0.done = 1'b0; dma_m0.fault = 1'b0;
    dma_m1.rdata  = 32'h0; dma_m1.done = 1'b0; dma_m1.fault = 1'b0;
    dma_m2.rdata  = 32'h0; dma_m2.done = 1'b0; dma_m2.fault = 1'b0;
    dma_m3.rdata  = 32'h0; dma_m3.done = 1'b0; dma_m3.fault = 1'b0;

    case (g_q)
      G_M0: begin
        dma_out.req   = dma_m0.req;
        dma_out.we    = dma_m0.we;
        dma_out.be    = dma_m0.be;
        dma_out.addr  = dma_m0.addr;
        dma_out.wdata = dma_m0.wdata;
        dma_m0.rdata  = dma_out.rdata;
        dma_m0.done   = dma_out.done;
        dma_m0.fault  = dma_out.fault;
      end
      G_M1: begin
        dma_out.req   = dma_m1.req;
        dma_out.we    = dma_m1.we;
        dma_out.be    = dma_m1.be;
        dma_out.addr  = dma_m1.addr;
        dma_out.wdata = dma_m1.wdata;
        dma_m1.rdata  = dma_out.rdata;
        dma_m1.done   = dma_out.done;
        dma_m1.fault  = dma_out.fault;
      end
      G_M2: begin
        dma_out.req   = dma_m2.req;
        dma_out.we    = dma_m2.we;
        dma_out.be    = dma_m2.be;
        dma_out.addr  = dma_m2.addr;
        dma_out.wdata = dma_m2.wdata;
        dma_m2.rdata  = dma_out.rdata;
        dma_m2.done   = dma_out.done;
        dma_m2.fault  = dma_out.fault;
      end
      G_M3: begin
        dma_out.req   = dma_m3.req;
        dma_out.we    = dma_m3.we;
        dma_out.be    = dma_m3.be;
        dma_out.addr  = dma_m3.addr;
        dma_out.wdata = dma_m3.wdata;
        dma_m3.rdata  = dma_out.rdata;
        dma_m3.done   = dma_out.done;
        dma_m3.fault  = dma_out.fault;
      end
      default: begin end
    endcase
  end

endmodule
