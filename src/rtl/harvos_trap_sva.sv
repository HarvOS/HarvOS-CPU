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

`ifndef __YOSYS_ASSERT_STUBS__
`define __YOSYS_ASSERT_STUBS__ 1
`ifndef ASSERT_IMP
`define ASSERT_IMP(name, expr)
`endif
`ifndef ASSERT_NEVER
`define ASSERT_NEVER(name, expr)
`endif
`endif


`ifdef FORMAL
module harvos_trap_sva #(
  parameter logic [31:0] RESET_PC = 32'h0000_0000
) (
  input logic        clk,
  input logic        rst_n,
  input logic        sret_pulse,
  input logic        mret_pulse,
  input logic [31:0] pc_q,
  input logic [31:0] csr_sepc_q,
  input logic [31:0] csr_mepc_q,
  input logic [31:0] csr_stvec_q,
  input logic [31:0] csr_sstatus_q,
  input logic [31:0] csr_mstatus_q
);
  // 1) PC after reset should be RESET_PC until first advance
  property p_reset_pc;
    !rst_n |-> (pc_q == RESET_PC);
  endproperty
  assert property (@(posedge clk) p_reset_pc)
    else $error("PC not RESET_PC during reset");

  // 2) STVEC/SEPC alignment invariant (low 2 bits zero)
  assert property (@(posedge clk) csr_stvec_q[1:0] == 2'b00)
    else $error("STVEC not aligned");
  assert property (@(posedge clk) csr_sepc_q[1:0] == 2'b00)
    else $error("SEPC not aligned");

  // 3) SRET: next PC = SEPC
  property p_sret_pc;
    sret_pulse |=> (pc_q == csr_sepc_q);
  endproperty
  assert property (@(posedge clk) disable iff(!rst_n) p_sret_pc)
    else $error("SRET did not jump to SEPC");

  // 4) SRET side-effects on SSTATUS: SIE<=SPIE; SPIE<=1; SPP<=0 (check one cycle later)
  property p_sret_sstatus;
    sret_pulse |=> (csr_sstatus_q[1] == $past(csr_sstatus_q[5])) &&
                   (csr_sstatus_q[5] == 1'b1) &&
                   (csr_sstatus_q[8] == 1'b0);
  endproperty
  assert property (@(posedge clk) disable iff(!rst_n) p_sret_sstatus)
    else $error("SRET did not update SSTATUS as expected");


  // ---- moved from file tail (SVA) ----
// 5) MRET: next PC = MEPC
property p_mret_pc;
  mret_pulse |=> (pc_q == csr_mepc_q);
endproperty
assert property (@(posedge clk) disable iff(!rst_n) p_mret_pc)
  else $error("MRET did not jump to MEPC");

// 6) MRET side-effects on MSTATUS: MIE<=MPIE; MPIE<=1; MPP<=0
property p_mret_mstatus;
  mret_pulse |=> (csr_mstatus_q[3] == $past(csr_mstatus_q[7])) &&
                 (csr_mstatus_q[7] == 1'b1) &&
                 (csr_mstatus_q[12:11] == 2'b00);
endproperty
assert property (@(posedge clk) disable iff(!rst_n) p_mret_mstatus)
  else $error("MRET did not update MSTATUS as expected");
endmodule
`endif
