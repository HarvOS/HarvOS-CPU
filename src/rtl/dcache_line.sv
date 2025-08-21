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


`include "harvos_pkg_flat.svh"
module dcache_line #(
  parameter integer LINE_BYTES = 16,   // 4 words per line
  parameter integer LINES      = 64    // total size = LINE_BYTES * LINES
) (
  input  logic        clk,
  input  logic        rst_n,

  // CPU side
  input  logic        cpu_req,       // pulse to start an access
  input  logic        cpu_we,
  input  logic [3:0]  cpu_be,
  input  logic [31:0] cpu_addr,
  input  logic [31:0] cpu_wdata,
  output logic [31:0] cpu_rdata,
  output logic        cpu_done,      // 1 when the access (load/store) has completed
  output logic        cpu_fault,     // propagated from memory on refill/forward

  // Memory side (to arbiter m0)
  output logic        mem_req,
  output logic        mem_we,
  output logic [3:0]  mem_be,
  output logic [31:0] mem_addr,
  output logic [31:0] mem_wdata,
  input  logic [31:0] mem_rdata,
  input  logic        mem_rvalid,
  input  logic        mem_fault
);
  
  // ----- Hoisted declarations for Yosys SV parser -----
  integer i;  // hoisted loop var from for(...) header
  integer j;  // hoisted loop var from for(...) header

localparam integer WORDS_PER_LINE = LINE_BYTES/4;
  localparam integer OFFSET_BITS    = $clog2(LINE_BYTES);
  localparam integer INDEX_BITS     = $clog2(LINES);
  localparam integer TAG_BITS       = 32 - INDEX_BITS - OFFSET_BITS;

  typedef struct packed {
    logic               valid;
  logic [TAG_BITS-1:0] tag;
  } tag_s;
  logic tagv_valid[LINES];  // flattened from tag_s tagv_valid[LINES]

  logic tagv_locked[LINES];  // flattened from tag_s tagv_locked[LINES]

  logic [TAG_BITS-1:0] tagv_tag[LINES];

    logic [31:0] data[LINES][WORDS_PER_LINE];
// address breakdown
  wire [INDEX_BITS-1:0] index = cpu_addr[OFFSET_BITS +: INDEX_BITS];
  wire [TAG_BITS-1:0]   tag   = cpu_addr[OFFSET_BITS+INDEX_BITS +: TAG_BITS];
  wire [OFFSET_BITS-1:2] word_off = cpu_addr[OFFSET_BITS-1:2];

  // registers for transaction
  logic        we_q;
  logic [3:0]  be_q;
  logic [31:0] addr_q, wdata_q;
  logic [INDEX_BITS-1:0] idx_q;
  logic [TAG_BITS-1:0]   tag_q;
  logic [$clog2(WORDS_PER_LINE)-1:0] fill_cnt_q, fill_cnt_n;

  // FSM
  typedef enum logic [2:0] {IDLE, LOOK, HIT_LOAD, HIT_STORE_FWD, MISS_REFILL_REQ, MISS_REFILL_WAIT, MISS_STORE_FWD} state_e;
  state_e st_q, st_n;

  // outputs default
  always_comb begin
    cpu_rdata = 32'h0;
    cpu_done  = 1'b0;
    cpu_fault = 1'b0;

    mem_req   = 1'b0;
    mem_we    = 1'b0;
    mem_be    = 4'h0;
    mem_addr  = 32'h0;
    mem_wdata = 32'h0;

    fill_cnt_n = fill_cnt_q;
    st_n = st_q;

    case (st_q)
      IDLE: begin
        if (cpu_req) st_n = LOOK;
      end
      LOOK: begin
        if (tagv_valid[index] && tagv_tag[index] == tag) begin
          // hit
          if (cpu_we) begin
            // write-through, update cache line, forward to memory
            mem_req  = 1'b1; mem_we = 1'b1; mem_be = cpu_be; mem_addr = {addr_q[31:2], 2'b00}; mem_wdata = wdata_q;
            st_n = HIT_STORE_FWD;
          end else begin
            st_n = HIT_LOAD;
          end
        end else begin
          // miss
          if (cpu_we) begin
            // store miss: no-allocate, just forward write
            mem_req  = 1'b1; mem_we = 1'b1; mem_be = cpu_be; mem_addr = {addr_q[31:2], 2'b00}; mem_wdata = wdata_q;
            st_n = MISS_STORE_FWD;
          end else begin
            // load miss: line refill
            mem_req = 1'b1;
            mem_addr= {addr_q[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}}; // aligned line base
            st_n    = MISS_REFILL_WAIT;
          end
        end
      end
      HIT_LOAD: begin
        cpu_rdata = data[index][word_off];
        cpu_done  = 1'b1;
        st_n      = IDLE;
      end
      HIT_STORE_FWD: begin
        if (mem_rvalid) begin
          // update cached word on store hit
          cpu_done = 1'b1;
          st_n     = IDLE;
        end
        cpu_fault = mem_fault;
      end
      MISS_REFILL_REQ: begin
        // (unused; we go directly to WAIT after issuing req)
        st_n = MISS_REFILL_WAIT;
      end
      MISS_REFILL_WAIT: begin
        if (mem_rvalid) begin
          // write fetched word to line
          if (fill_cnt_q == WORDS_PER_LINE-1) begin
            st_n = LOOK; // line ready, re-evaluate as hit
          end else begin
            // request next word
            mem_req  = 1'b1;
            mem_addr = {addr_q[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}} + { {(32-$clog2(LINE_BYTES)-2){1'b0}}, (fill_cnt_q+1), 2'b00 };
            st_n = MISS_REFILL_WAIT;
          end
        end
        cpu_fault = mem_fault;
      end
      MISS_STORE_FWD: begin
        if (mem_rvalid) begin
          cpu_done = 1'b1;
          st_n     = IDLE;
        end
        cpu_fault = mem_fault;
      end
    endcase
  end

  // sequential
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st_q <= IDLE;
      we_q <= 1'b0; be_q <= 4'h0; addr_q <= 32'h0; wdata_q <= 32'h0;
      idx_q <= '0; tag_q <= '0; fill_cnt_q <= '0;
      for (i = 0;i<LINES;i++) begin
        tagv_valid[i] <= 1'b0;
        tagv_tag[i]   <= '0;
        for (j = 0; j < WORDS_PER_LINE; j++) data[i][j] <= 32'h0;
      end
    end else begin
      st_q <= st_n;
      fill_cnt_q <= fill_cnt_n;

      if (cpu_req && st_q == IDLE) begin
        we_q   <= cpu_we;
        be_q   <= cpu_be;
        addr_q <= cpu_addr;
        wdata_q<= cpu_wdata;
        idx_q  <= index;
        tag_q  <= tag;
        fill_cnt_q <= '0;
      end

      // store hit update
      if (st_q == LOOK && tagv_valid[index] && tagv_tag[index] == tag && cpu_we) begin
        data[index][word_off] <= ((data[index][word_off]) & ~{ {8{cpu_be[3]}}, {8{cpu_be[2]}}, {8{cpu_be[1]}}, {8{cpu_be[0]}} }) | (({ cpu_wdata[31:24], cpu_wdata[23:16], cpu_wdata[15:8], cpu_wdata[7:0] }) & { {8{cpu_be[3]}}, {8{cpu_be[2]}}, {8{cpu_be[1]}}, {8{cpu_be[0]}} });
      end

      // refill writes
      if (st_q == MISS_REFILL_WAIT && mem_rvalid && !mem_fault) begin
        data[idx_q][fill_cnt_q] <= mem_rdata;
        if (fill_cnt_q == WORDS_PER_LINE-1) begin
          tagv_valid[idx_q] <= 1'b1;
          tagv_tag[idx_q]   <= tag_q;
        end else begin
          fill_cnt_q <= fill_cnt_q + 1;
        end
      end
    end
  end
endmodule
