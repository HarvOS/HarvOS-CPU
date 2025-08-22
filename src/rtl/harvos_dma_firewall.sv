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

  // simple config port (tie off if unused)
  input  logic        cfg_en,
  input  logic        cfg_we,
  input  logic [3:0]  cfg_addr,
  input  logic [31:0] cfg_wdata,
  input  logic [3:0]  cfg_be,
  output logic [31:0] cfg_rdata,

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

// Configuration registers (reset from parameters)
reg [31:0] rom_bytes_q;   // I-space limit
reg [31:0] pbase0_q;
reg [31:0] pmask0_q;
reg        pwrite_only0_q;
reg        lock_q;

// Write enable respecting lock
wire cfg_we_unlocked = cfg_en && cfg_we && !lock_q;

// Register write
always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    rom_bytes_q    <= ROM_BYTES[31:0];
    pbase0_q       <= PBASE0;
    pmask0_q       <= PMASK0;
    pwrite_only0_q <= PWRITE_ONLY0;
    lock_q         <= 1'b0;
  end else begin
    if (cfg_we_unlocked) begin
      case (cfg_addr)
        4'h0: begin // CONTROL
          if (cfg_wdata[0]) lock_q <= 1'b1; // LOCK is sticky
        end
        4'h1: rom_bytes_q    <= cfg_wdata;
        4'h2: pbase0_q       <= cfg_wdata;
        4'h3: pmask0_q       <= cfg_wdata;
        4'h4: pwrite_only0_q <= cfg_wdata[0];
        default: ;
      endcase
    end
  end
end

// Readback
always @* begin
  case (cfg_addr)
    4'h0: cfg_rdata = {31'b0, lock_q};
    4'h1: cfg_rdata = rom_bytes_q;
    4'h2: cfg_rdata = pbase0_q;
    4'h3: cfg_rdata = pmask0_q;
    4'h4: cfg_rdata = {31'b0, pwrite_only0_q};
    default: cfg_rdata = 32'h0;
  endcase
end

  // Address classification
  wire is_i_space     = (dma.addr < rom_bytes_q);
  wire is_priv0_hit   = ((dma.addr & ~pmask0_q) == pbase0_q);

  // Privileged region block conditions
  wire priv_block_read  = is_priv0_hit & (~pwrite_only0_q);
  wire priv_block_write = is_priv0_hit & (pwrite_only0_q | (~pwrite_only0_q));

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
