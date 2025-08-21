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
`include "bus_if.sv"
// Drop-in replacement for dmem_arbiter with fair round-robin + backpressure-friendly handshakes.
// Two masters: 
//   M0 = D$ (core data path), M1 = PTW (page table walker) or DMA.
// Guarantees: no starvation; long write bursts yield to other master when it is requesting.
module dmem_arbiter (
  input  logic clk,
  input  logic rst_n,

  // Master 0: core data access (RW)
  input  logic        m0_req,
  input  logic        m0_we,
  input  logic [3:0]  m0_be,
  input  logic [31:0] m0_addr,
  input  logic [31:0] m0_wdata,
  output logic [31:0] m0_rdata,
  output logic        m0_rvalid,
  output logic        m0_fault,

  // Master 1: PTW (R-only typical)
  input  logic        m1_req,
  input  logic [31:0] m1_addr,
  output logic [31:0] m1_rdata,
  output logic        m1_rvalid,
  output logic        m1_fault,

  // Shared memory
  harvos_dmem_if.master dmem
);
  // ----------------
  // Requests & simple ready/valid
  // ----------------
  typedef enum logic [1:0] {G_IDLE, G_M0, G_M1} grant_e;
  grant_e g_q, g_n;

  // Round-robin token toggles whenever the granted transaction completes
  logic rr_token_q, rr_token_n; // 0 prefers M0, 1 prefers M1
  localparam integer MAX_BEATS_BEFORE_YIELD = 8; // backpressure-friendly yield
  logic [$clog2(MAX_BEATS_BEFORE_YIELD):0] beat_cnt_q, beat_cnt_n;

  // Default outputs
  always_comb begin
    m0_rdata  = dmem.rdata;
    m1_rdata  = dmem.rdata;
    m0_rvalid = 1'b0;
    m1_rvalid = 1'b0;
    m0_fault  = 1'b0;
    m1_fault  = 1'b0;

    dmem.req  = 1'b0;
    dmem.we   = 1'b0;
    dmem.be   = 4'h0;
    dmem.addr = 32'h0;
    dmem.wdata= 32'h0;

    g_n       = g_q;
    rr_token_n= rr_token_q;
    beat_cnt_n= beat_cnt_q;

    case (g_q)
      G_IDLE: begin
        // choose based on rr token and presence of requests
        if (m0_req || m1_req) begin
          if (m0_req && m1_req) begin
            g_n = (rr_token_q == 1'b0) ? G_M0 : G_M1;
          end else begin
            g_n = m0_req ? G_M0 : G_M1;
          end
          beat_cnt_n = '0;
        end
      end

      G_M0: begin
        dmem.req   = 1'b1;
        dmem.we    = m0_we;
        dmem.be    = m0_be;
        dmem.addr  = m0_addr;
        dmem.wdata = m0_wdata;
        // complete on read data or write ack
        if (dmem.rvalid) begin
          m0_rvalid = 1'b1;
          m0_fault  = dmem.fault;
          g_n       = G_IDLE;
          rr_token_n= 1'b1; // next time prefer M1
        end else begin
          // prevent hogging: if other master is waiting and we've consumed many beats, yield
          beat_cnt_n = beat_cnt_q + 1'b1;
          if (m1_req && (beat_cnt_q >= MAX_BEATS_BEFORE_YIELD-1)) begin
            g_n       = G_IDLE;
            rr_token_n= 1'b1;
          end
        end
      end

      G_M1: begin
        dmem.req   = 1'b1;
        dmem.we    = 1'b0;
        dmem.be    = 4'hF;
        dmem.addr  = m1_addr;
        if (dmem.rvalid) begin
          m1_rvalid = 1'b1;
          m1_fault  = dmem.fault;
          g_n       = G_IDLE;
          rr_token_n= 1'b0; // next time prefer M0
        end else begin
          beat_cnt_n = beat_cnt_q + 1'b1;
          if (m0_req && (beat_cnt_q >= MAX_BEATS_BEFORE_YIELD-1)) begin
            g_n       = G_IDLE;
            rr_token_n= 1'b0;
          end
        end
      end
    endcase
  end

  // Seq
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      g_q <= G_IDLE;
      rr_token_q <= 1'b0;
      beat_cnt_q <= '0;
    end else begin
      g_q <= g_n;
      rr_token_q <= rr_token_n;
      beat_cnt_q <= (g_n==G_IDLE) ? '0 : beat_cnt_n;
    end
  end

endmodule
