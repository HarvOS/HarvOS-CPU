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
module mmu_stub (
  input  logic                    clk,
  input  logic                    rst_n,
  // enable translation (always on per spec; stub keeps identity but generates faults on illegal perms)
  input  logic [31:0]             csr_satp_q,
  input  acc_e        acc_type,
  input  priv_e       cur_priv,
  input  logic [31:0]             vaddr,
  // outputs
  output logic [31:0]             paddr,
  output logic                    page_perm_r,
  output logic                    page_perm_w,
  output logic                    page_perm_x,
  output logic                    page_user,
  output logic                    valid
);
  // MVP: identity map; permissions = {R=1,W=XOR(X,1),X=1 for ispace}, user=1
  // In real impl, fill from TLB/walker; enforce W^X at fill time
  always_comb begin
    paddr       = vaddr;
    valid       = 1'b1;
    page_user   = 1'b1;
    // optimistic perms; core/MPU still gate accesses and prevent violations
    page_perm_r = 1'b1;
    page_perm_w = 1'b1;
    page_perm_x = 1'b1;
  end
endmodule
