// Bind SVA to harvos_core to check trap/return invariants
bind harvos_core harvos_trap_sva #(.RESET_PC(RESET_PC)) SVA (
  .clk(clk),
  .rst_n(rst_n),
  .sret_pulse(sret_pulse),
  .mret_pulse(mret_pulse),
  .pc_q(pc_q),
  .csr_sepc_q(csr_sepc_q),
  .csr_mepc_q(csr_mepc_q),
  .csr_stvec_q(csr_stvec_q),
  .csr_sstatus_q(csr_sstatus_q),
  .csr_mstatus_q(csr_mstatus_q)
);
