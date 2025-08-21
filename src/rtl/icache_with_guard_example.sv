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
// Example: wrapping an existing icache with ifetch_guard.
// Replace connections to your real icache and trap unit as needed.
module icache_with_guard_example (
  input  logic        clk, rst_n,

  // Core fetch interface
  input  logic        if_req_i,
  input  logic [31:0] if_paddr_i,          // assume MMU already translated to physical
  output logic        if_ready_o,
  output logic [31:0] if_rdata_o,
  output logic        if_rvalid_o,

  // Trap reporting
  output logic        trap_valid_o,
  output logic [31:0] trap_cause_o,
  output logic [31:0] trap_tval_o,

  // MPU permission for execute at if_paddr_i
  input  logic        mpu_exec_allow_i
);

  // Guard
  logic g_if_req, block_refill, fetch_fault;
  logic [31:0] fetch_cause, fetch_tval;

  ifetch_guard u_guard (
    .clk(clk), .rst_n(rst_n),
    .if_req_i(if_req_i),
    .if_addr_i(if_paddr_i),
    .if_req_o(g_if_req),
    .ic_miss_i(1'b0),              // drive from real I$ miss in your icache
    .block_refill_o(block_refill), // connect to your refill issue gating
    .mpu_exec_allow_i(mpu_exec_allow_i),
    .fetch_fault_o(fetch_fault),
    .fetch_fault_cause_o(fetch_cause),
    .fetch_fault_tval_o(fetch_tval)
  );

  // Dummy I$ for example purposes: responds one cycle later if allowed
  logic req_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) req_q <= 1'b0;
    else       req_q <= g_if_req;
  end

  assign if_ready_o  = 1'b1;
  assign if_rvalid_o = req_q;
  assign if_rdata_o  = 32'h0000_0000; // stub

  // trap when guard flags a fault
  assign trap_valid_o = fetch_fault;
  assign trap_cause_o = fetch_cause;
  assign trap_tval_o  = fetch_tval;

endmodule
