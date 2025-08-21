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

`ifndef SYNTHESIS
// SPDX-License-Identifier: MIT
// Example integration of mmu_perm_pkg into an SV32-like MMU datapath.
// NOTE: This is a reference snippet;
  // wire it into your real mmu_sv32.sv.
`include "mmu_perm_pkg.sv"

module mmu_sv32_example #(
  parameter bit USE_HW_SET_AD = 1'b0 // 0: SW-managed A/D (fault on A/D=0), 1: HW-set A/D
)(
  input  logic         clk, rst_n,
  input  logic         priv_is_user_i,
  input  logic  [31:0] vaddr_i,
  input  logic  [1:0]  acc_i,        // mmu_perm_pkg.mmu_acc_e
  // CSR views
  input  logic         csr_mxr_i,
  input  logic         csr_sum_i,
  // PTE flags from PTW/TLB (example port)
  input  logic         pte_V_i, pte_R_i, pte_W_i, pte_X_i, pte_U_i, pte_G_i, pte_A_i, pte_D_i,
  output logic         allow_o,
  output logic         need_set_A_o,
  output logic         need_set_D_o,
  output logic  [3:0]  fault_o
);

  import mmu_perm_pkg::*;

  pte_flags_t flags;
  always_comb begin
    flags = '{V:pte_V_i, R:pte_R_i, W:pte_W_i, X:pte_X_i, U:pte_U_i, G:pte_G_i, A:pte_A_i, D:pte_D_i};
    automatic mmu_perm_res_t r = mmu_check_perms(priv_is_user_i, acc_i, flags, csr_mxr_i, csr_sum_i, USE_HW_SET_AD);
    allow_o     = r.allow;
    need_set_A_o= r.need_set_A;
    need_set_D_o= r.need_set_D;
    fault_o     = r.fault;
  end

endmodule

`endif
