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
// Direct-mapped D$ with per-word-valid lines, early-restart on loads, and a tiny store write buffer.
// This is a reference skeleton you can adapt to your existing dcache.sv.
`include "dcache_params_pkg.sv"
module dcache_simple_wb #(
  parameter integer LINE_BYTES     = 16,
  parameter integer WORD_BYTES     = 4,
  parameter integer WORDS_PER_LINE = 4,
  parameter integer SETS           = 64
) (

  input  logic        clk, rst_n,
  // Core request
  input  logic        req_valid_i,
  input  logic        req_we_i,            // 0: load, 1: store
  input  logic [31:0] req_addr_i,
  input  logic [31:0] req_wdata_i,
  input  logic [3:0]  req_wstrb_i,
  output logic        req_ready_o,
  // Core response
  output logic        resp_valid_o,
  output logic [31:0] resp_rdata_o,

  // Memory interface (line-based fills, word stores)
  output logic        mem_rd_valid_o,
  output logic [31:0] mem_rd_addr_o,  // aligned line address
  input  logic        mem_rd_ready_i,
  input  logic        mem_rd_data_valid_i,
  input  logic [31:0] mem_rd_data_i,  // one word at a time
  input  logic [1:0]  mem_rd_last_i,  // assert on last word of line

  output logic        mem_wr_valid_o,
  output logic [31:0] mem_wr_addr_o,
  output logic [31:0] mem_wr_data_o,
  output logic [3:0]  mem_wr_strb_o,
  input  logic        mem_wr_ready_i
);
// Tag & data arrays (single-ported for simplicity)
  // Derived bit widths
  localparam integer WORD_BITS = $clog2(WORDS_PER_LINE);
  localparam integer OFF_BITS  = 2 + WORD_BITS;
  // Derived index/tag widths for Yosys (constant expressions)
  localparam integer LINE_BITS     = $clog2(SETS);
  localparam integer IDX_BITS      = LINE_BITS;
  localparam integer WORD_IDX_BITS = WORD_BITS;
  localparam integer TAG_BITS      = 32 - OFF_BITS - IDX_BITS;


  typedef struct packed { logic _unused; } tag_t /* removed for Yosys fix */;
logic                     tag_valid   [SETS];
  logic [TAG_BITS-1:0]      tag_value   [SETS];
  logic [WORDS_PER_LINE-1:0] tag_wvalid [SETS];
  logic [31:0] data_mem [SETS][WORDS_PER_LINE];
  integer s;  // hoisted loop variable for Yosys

  // Address split
  wire [OFF_BITS-1:0]  off  = req_addr_i[OFF_BITS-1:0];
  wire [IDX_BITS-1:0]  idx  = req_addr_i[OFF_BITS+IDX_BITS-1:OFF_BITS];
  wire [TAG_BITS-1:0] tag = req_addr_i[31:OFF_BITS+IDX_BITS];
  wire [WORD_IDX_BITS-1:0] word_idx = off[OFF_BITS-1:2];

  // Write buffer to hide store misses
  logic wbuf_enq_ready, wbuf_fwd_hit;
  logic wbuf_mem_valid; logic [31:0] wbuf_mem_addr, wbuf_mem_wdata; logic [3:0] wbuf_mem_strb;
  logic [31:0] wbuf_fwd_data;

  dcache_wbuf #(.DEPTH(2)) u_wbuf (
    .clk(clk), .rst_n(rst_n),
    .enq_valid_i  (req_valid_i && req_we_i && !req_ready_o), // enqueue when we backpressure stores
    .enq_addr_i   (req_addr_i),
    .enq_wdata_i  (req_wdata_i),
    .enq_wstrb_i  (req_wstrb_i),
    .enq_ready_o  (wbuf_enq_ready),
    .mem_valid_o  (wbuf_mem_valid),
    .mem_addr_o   (wbuf_mem_addr),
    .mem_wdata_o  (wbuf_mem_wdata),
    .mem_wstrb_o  (wbuf_mem_strb),
    .mem_ready_i  (mem_wr_ready_i),
    .fwd_req_i    (req_valid_i && !req_we_i),
    .fwd_addr_i   (req_addr_i),
    .fwd_hit_o    (wbuf_fwd_hit),
    .fwd_data_o   (wbuf_fwd_data)
  );

  // Default: accept core requests unless refilling same set/line
  typedef enum logic [1:0] {IDLE, REFILL} state_e;
  state_e state_q, state_d;
  logic [IDX_BITS-1:0]  refill_idx_q; logic [31:0] refill_tag_q; logic [WORD_IDX_BITS-1:0] refill_wptr_q;

  // Hit detection
  wire hit = tag_valid[idx] && (tag_value[idx] == tag);

  // Core ready logic: loads are stalled only when refilling **same index**; stores can enqueue to wbuf
  assign req_ready_o = (!req_we_i) ? (state_q==IDLE || idx!=refill_idx_q) : wbuf_enq_ready;

  // Load path
  always_comb begin
    resp_valid_o = 1'b0;
    resp_rdata_o = 32'h0;
    if (req_valid_i && !req_we_i && req_ready_o) begin
      if (hit && tag_wvalid[idx][word_idx]) begin
        // Cache hit with valid word
        resp_valid_o = 1'b1;
        resp_rdata_o = data_mem[idx][word_idx];
      end else if (wbuf_fwd_hit) begin
        // Forward from write buffer if matching
        resp_valid_o = 1'b1;
        resp_rdata_o = wbuf_fwd_data;
      end
    end
  end

  // Miss handling + early restart
  assign mem_rd_valid_o = (state_q==IDLE && req_valid_i && !req_we_i && !hit);
  assign mem_rd_addr_o  = {req_addr_i[31:OFF_BITS], {OFF_BITS{1'b0}}}; // line-aligned

  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      state_q <= IDLE; refill_idx_q <= '0; refill_tag_q <= '0; refill_wptr_q <= '0;
      for (s=0;s<SETS;s++) begin
        tag_valid[s] <= 1'b0; tag_value[s] <= '0; tag_wvalid[s] <= '0;
      end
    end else begin
      case (state_q)
        IDLE: begin
          if (mem_rd_valid_o && mem_rd_ready_i) begin
            // start refill
            state_q <= REFILL;
            refill_idx_q <= idx;
            refill_tag_q <= tag;
            tag_valid[idx] <= 1'b1; tag_value[idx] <= tag; tag_wvalid[idx] <= '0; // clear per-word valid
            refill_wptr_q <= '0;
          end
        end
        REFILL: begin
          if (mem_rd_data_valid_i) begin
            data_mem[refill_idx_q][refill_wptr_q] <= mem_rd_data_i;
            tag_wvalid[refill_idx_q][refill_wptr_q] <= 1'b1; // per-word valid enables early restart
            refill_wptr_q <= refill_wptr_q + 1'b1;
            // When the requested word arrives (early restart), the response will be produced by hit path next cycle
          end
          if (mem_rd_data_valid_i && mem_rd_last_i[0]) begin
            state_q <= IDLE;
          end
        end
      endcase

      // Write-through (for simplicity) using write buffer to mem
      // Optional: write-allocate policy. Here we *do not* allocate on store miss to keep it simple.
      if (req_valid_i && req_we_i && req_ready_o) begin
        if (hit) begin
          // update cached word and mark valid
          data_mem[idx][word_idx] <= req_wdata_i;
          tag_wvalid[idx][word_idx] <= 1'b1;
        end
        // drain to memory through wbuf (wired below)
      end
    end
  end

  // Connect write buffer to memory interface
  assign mem_wr_valid_o = wbuf_mem_valid;
  assign mem_wr_addr_o  = wbuf_mem_addr;
  assign mem_wr_data_o  = wbuf_mem_wdata;
  assign mem_wr_strb_o  = wbuf_mem_strb;
endmodule