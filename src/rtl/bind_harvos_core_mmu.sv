// Bind SVA to harvos_core for satp.MODE enforcement
bind harvos_core harvos_mmu_baremode_sva MMUSVA (
  .clk(clk),
  .rst_n(rst_n),
  .csr_satp_q(csr_satp_q)
);
