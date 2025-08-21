// SPDX-License-Identifier: MIT
// harvos_dma_firewall.sv — Minimal DMA bus firewall for HarvOS dmem fabric
// Verilog-2005 friendly: no array parameters, no SV aggregates.
//
// Policy:
//  - Block DMA writes to I-space (addresses < ROM_BYTES).
//  - Optional single protected region (base/mask), block reads+writes or writes-only.
//
// Notes:
//  - On a blocked access, request is NOT forwarded and DMA sees done=1, fault=1.
//  - On allowed access, request is forwarded for one cycle; response is proxied back.

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

`include "harvos_dmem_if.sv"

module harvos_dma_firewall #(
  parameter integer ROM_BYTES      = 4096*4,   // I-space window size
  // Optional single privileged region
  parameter [31:0]  PBASE0         = 32'h0000_0000,
  parameter [31:0]  PMASK0         = 32'hFFFF_FFFF, // all 1s -> disabled
  parameter         PWRITE_ONLY0   = 1'b0      // 0: block R/W, 1: block writes only
) (
  input  logic clk,
  input  logic rst_n,

  // Incoming DMA master
  harvos_dmem_if.slave  dma,

  // Outgoing request onto SoC memory bus
  output logic        fw_req,
  output logic        fw_we,
  output logic [3:0]  fw_be,
  output logic [31:0] fw_addr,
  output logic [31:0] fw_wdata,

  // Return path from SoC memory bus
  input  logic [31:0]  m_rdata,
  input  logic         m_rvalid,
  input  logic         m_fault
);

  // Address classification
  wire is_i_space     = (dma.addr < ROM_BYTES);
  wire is_priv0_hit   = ((dma.addr & ~PMASK0) == PBASE0);

  // Privileged region block conditions
  wire priv_block_read  = is_priv0_hit & (~PWRITE_ONLY0);
  wire priv_block_write = is_priv0_hit & (PWRITE_ONLY0 | (~PWRITE_ONLY0));

  // Final block decision
  wire block_now = (dma.we & is_i_space) |
                   (dma.we ? priv_block_write : priv_block_read);

  // FSM (simple 2-bit encoded)
  localparam [1:0] G_IDLE=2'd0, G_FWD=2'd1, G_WAIT=2'd2, G_FAULT=2'd3;
  reg [1:0] g_q, g_n;

  // Latched fields for forwarded transaction
  reg [31:0] addr_q, wdata_q;
  reg [3:0]  be_q;
  reg        we_q;

  // Defaults
  always_comb begin
    fw_req   = 1'b0;
    fw_we    = we_q;
    fw_be    = be_q;
    fw_addr  = addr_q;
    fw_wdata = wdata_q;

    dma.done  = 1'b0;
    dma.fault = 1'b0;
    dma.rdata = 32'h0;

    g_n = g_q;

    case (g_q)
      G_IDLE: begin
        if (dma.req) begin
          if (block_now) begin
            g_n = G_FAULT;
          end else begin
            fw_req = 1'b1;
            g_n    = G_FWD;
          end
        end
      end

      G_FWD: begin
        fw_req = 1'b1; // drive one more cycle
        g_n    = G_WAIT;
      end

      G_WAIT: begin
        if (m_rvalid) begin
          dma.done  = 1'b1;
          dma.fault = m_fault;
          if (!we_q) dma.rdata = m_rdata;
          g_n = G_IDLE;
        end
      end

      G_FAULT: begin
        dma.done  = 1'b1;
        dma.fault = 1'b1;
        g_n = G_IDLE;
      end
      default: g_n = G_IDLE;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      g_q     <= G_IDLE;
      addr_q  <= 32'h0;
      wdata_q <= 32'h0;
      be_q    <= 4'h0;
      we_q    <= 1'b0;
    end else begin
      g_q <= g_n;
      if (g_q==G_IDLE && dma.req && !block_now) begin
        addr_q  <= dma.addr;
        wdata_q <= dma.wdata;
        be_q    <= dma.be;
        we_q    <= dma.we;
      end
    end
  end

endmodule
