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
// Tiny store write buffer (1-2 entries). Hides store-miss latency, lets loads make progress.
module dcache_wbuf #(
  parameter integer DEPTH = 2
)(
  input  logic        clk, rst_n,
  // Enqueue from D$ (store datapath)
  input  logic        enq_valid_i,
  input  logic [31:0] enq_addr_i,
  input  logic [31:0] enq_wdata_i,
  input  logic [3:0]  enq_wstrb_i,
  output logic        enq_ready_o,

  // Drain to memory (write-through)
  output logic        mem_valid_o,
  output logic [31:0] mem_addr_o,
  output logic [31:0] mem_wdata_o,
  output logic [3:0]  mem_wstrb_o,
  input  logic        mem_ready_i,

  // Forward to loads (RAW bypass)
  input  logic        fwd_req_i,
  input  logic [31:0] fwd_addr_i,
  output logic        fwd_hit_o,
  output logic [31:0] fwd_data_o
);
  // ----- Hoisted declarations for Yosys SV parser -----
  integer i;  // hoisted loop var from for(...) header


  typedef struct packed {
    logic        v;
    logic [31:0] addr;
    logic [31:0] data;
    logic [3:0]  strb;
  } entry_t;

  logic q_v[DEPTH];  // flattened from entry_t q_v[DEPTH]
logic [31:0] q_addr[DEPTH];  // flattened from entry_t q_addr[DEPTH]
logic [31:0] q_data[DEPTH];  // flattened from entry_t q_data[DEPTH]
logic [3:0]  q_strb[DEPTH];  // flattened from entry_t q_strb[DEPTH]
  logic [$clog2(DEPTH):0] head, tail;

  // replaced function full_w for Yosys
wire full_w = ((tail+1'b1)==head);
  // replaced function empty_w for Yosys
wire empty_w = (tail==head);

  assign enq_ready_o = !full_w;

  // enqueue logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      head <= '0; tail <= '0;
      for (i = 0;i<DEPTH;i++) q_v[i] <= 1'b0;
    end else begin
      if (enq_valid_i && enq_ready_o) begin
        q_v[tail]    <= 1'b1;
        q_addr[tail] <= enq_addr_i;
        q_data[tail] <= enq_wdata_i;
        q_strb[tail] <= enq_wstrb_i;
        tail <= tail + 1'b1;
      end
      if (mem_valid_o && mem_ready_i) begin
        q_v[head] <= 1'b0;
        head <= head + 1'b1;
      end
    end
  end

  // drain interface
  assign mem_valid_o = !empty_w && q_v[head];
  assign mem_addr_o  = q_addr[head];
  assign mem_wdata_o = q_data[head];
  assign mem_wstrb_o = q_strb[head];

  // simple word-level forward (match by word address)
  assign fwd_hit_o  = (!empty_w && q_v[head] && (q_addr[head][31:2]==fwd_addr_i[31:2]));
  assign fwd_data_o = q_data[head];
endmodule
