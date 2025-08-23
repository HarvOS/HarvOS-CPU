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
// HarvOS I$ fetch guard: ties I$ miss/fill to MPU execute permission.
// If MPU denies execute for the (physical) fetch address, we raise a fetch fault
// BEFORE issuing any I$ lookup/refill, avoiding pointless refills into NX regions.
module ifetch_guard #(
  parameter bit ADDR_IS_PHYS = 1'b1    // 1: addr_i is physical, 0: virtual (then check must happen after PTW)
)(
  input  logic        clk,
  input  logic        rst_n,

  // Incoming fetch query from core frontend
  input  logic        if_req_i,
  input  logic [31:0] if_addr_i,      // PC (phys if ADDR_IS_PHYS=1)
  output logic        if_req_o,       // gated request to I$

  // I$ refill side-band (observe to assert "no-refill" on NX)
  input  logic        ic_miss_i,      // asserted when current if_req_i misses in I$
  output logic        block_refill_o, // use to gate refill issue in icache

  // MPU execute permission (combinational allow for this address)
  input  logic        mpu_exec_allow_i,

  // Fault reporting towards trap unit
  output logic        fetch_fault_o,
  output logic [31:0] fetch_fault_cause_o, // e.g. 0x1 Instruction access fault (or Harvard violation code)
  output logic [31:0] fetch_fault_tval_o   // offending address
);

  // Default: pass-through
  assign if_req_o  = if_req_i & mpu_exec_allow_i;
  assign block_refill_o = ic_miss_i & (~mpu_exec_allow_i);

  // Fault when a request targets NX region
  always_comb begin
    fetch_fault_o         = 1'b0;
    fetch_fault_cause_o   = {27'h0,SCAUSE_HARVARD_VIOLATION}; // 0xA per scause map // Instruction access fault (adjust to scause code map)
    fetch_fault_tval_o    = if_addr_i;
    if (if_req_i && !mpu_exec_allow_i) begin
      fetch_fault_o = 1'b1;
    end
  end

endmodule
