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
`include "bus_if.sv"
module icache #(
  parameter integer LINE_BYTES = 16,    // 4 words
  parameter integer LINES      = 64     // 1 KiB total
) (
  input  logic                  clk,
  input  logic                  rst_n,

  // CPU side (fetch)
  input  logic                  cpu_req,
  input  logic                  mpu_exec_allow,  // NEW: MPU execute-allow for cpu_addr
  input  logic [31:0]           cpu_addr,   // physical
  output logic [31:0]           cpu_rdata,
  output logic                  cpu_rvalid,
  output logic                  cpu_fault,
  input  logic                  inv_all,
  // Security: cache control
  input  logic          inv_all,


  // Memory side (to external imem bus)
  harvos_imem_if.master         mem
);
  
    logic [31:0] data[LINES][WORDS_PER_LINE];
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
  wire [INDEX_BITS-1:0]  index = cpu_addr[OFFSET_BITS +: INDEX_BITS];
  wire [TAG_BITS-1:0]    tag   = cpu_addr[OFFSET_BITS+INDEX_BITS +: TAG_BITS];
  wire [OFFSET_BITS-1:2] word_off = cpu_addr[OFFSET_BITS-1:2];

  // Simple FSM
  typedef enum logic [1:0] {IDLE, LOOKUP, REFILL_REQ, REFILL_WAIT} state_e;
  state_e st_q, st_n;
  logic miss_q;
  logic [31:0] miss_addr_q;
  logic [INDEX_BITS-1:0] miss_index_q;
  logic [TAG_BITS-1:0]   miss_tag_q;
  logic [$clog2(WORDS_PER_LINE)-1:0] fill_cnt_q, fill_cnt_n;

  // outputs default
  always_comb begin
    cpu_rdata  = 32'h0;
    cpu_rvalid = 1'b0;
    cpu_fault  = 1'b0;
    mem.req    = 1'b0;
    mem.addr   = 32'h0;
    st_n       = st_q;
    fill_cnt_n = fill_cnt_q;
    // Guard: block fetch and raise fault BEFORE any lookup/refill if NX
    if (cpu_req && !mpu_exec_allow) begin
      cpu_fault = 1'b1;
      // remain in current state; no mem.req asserted
    end

    case (st_q)
      IDLE: begin
        if (cpu_req) st_n = LOOKUP;
      end
      LOOKUP: begin
        if (tagv_valid[index] && tagv_tag[index] == tag) begin
          cpu_rdata  = data[index][word_off];
          cpu_rvalid = 1'b1;
          st_n       = IDLE;
        end else begin
          // miss → start refill at aligned line address
          st_n        = REFILL_REQ;
        end
      end
      REFILL_REQ: begin
        mem.req  = 1'b1;
        mem.addr = {miss_addr_q[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}} + { {(32-$clog2(LINE_BYTES)-2){1'b0}}, fill_cnt_q, 2'b00 };
        st_n     = REFILL_WAIT;
      end
      REFILL_WAIT: begin
        if (mem.rvalid) begin
          // store word
          // compute index from miss_index_q
          // compute word index = fill_cnt_q
        end
        if (mem.rvalid) begin
          // write the fetched word
          // Note: relying on non-blocking writes in sequential block below
          if (fill_cnt_q == WORDS_PER_LINE-1) begin
            st_n = IDLE;
          end else begin
            fill_cnt_n = fill_cnt_q + 1;
            st_n = REFILL_REQ;
          end
        end
        cpu_fault = mem.fault;
      end
    endcase
  end

  // sequential
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st_q <= IDLE;
      miss_q <= 1'b0;
      miss_addr_q <= 32'h0;
      miss_index_q <= '0;
      miss_tag_q   <= '0;
      fill_cnt_q   <= '0;
      for (i = 0;i<LINES;i++) begin
        tagv_valid[i] <= 1'b0;
        tagv_tag[i]   <= '0;
        for (j = 0; j < WORDS_PER_LINE; j++) data[i][j] <= 32'h0;
      end
    end else begin
      // Invalidate-all on inv_all
      if (inv_all) begin
        integer k;
        for (k=0;k<LINES;k=k+1) begin
          tagv_valid[k] <= 1'b0;
        end
      end

      st_q <= st_n;
      fill_cnt_q <= fill_cnt_n;

      if (st_q == LOOKUP && !(tagv_valid[index] && tagv_tag[index] == tag)) begin
        miss_q       <= 1'b1;
        miss_addr_q  <= cpu_addr;
        miss_index_q <= index;
        miss_tag_q   <= tag;
        fill_cnt_q   <= '0;
      end

      if (st_q == REFILL_WAIT && mem.rvalid) begin
        data[miss_index_q][fill_cnt_q] <= mem.rdata;
        if (fill_cnt_q == WORDS_PER_LINE-1) begin
          tagv_valid[miss_index_q] <= 1'b1;
          tagv_tag[miss_index_q]   <= miss_tag_q;
          miss_q <= 1'b0;
        end
      end
    end
  end

endmodule
