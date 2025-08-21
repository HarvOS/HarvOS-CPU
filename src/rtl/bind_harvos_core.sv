//
// bind_harvos_core.sv
// Example bind of harvos_sva to harvos_core. Adjust macro mappings for trap signals.
// Include this file in your simulation/formal compile to activate the checks.

`ifndef BIND_HARVOS_CORE_SV
`define BIND_HARVOS_CORE_SV

// Map core-internal trap signals via macros if available.
// Example (uncomment and adjust signal paths):
// `define HARVOS_TRAP_TAKEN  (trap_taken)         // e.g., top-level signal in core
// `define HARVOS_PC_Q        (if_pc_q)            // IF stage current PC
// `define HARVOS_NEXT_PC     (if_next_pc)         // next PC after IF
// `define HARVOS_STVEC_Q     (u_csr.stvec_q)      // CSR instance path
// `define HARVOS_SEPC_Q      (u_csr.sepc_q)       // CSR instance path

bind harvos_core harvos_sva #(.PC_W(32)) u_harvos_sva (
  .clk        (clk),
  .rst_n      (rst_n),
  // IMEM (read-only)
  .imem_req   (imem.req),
  .imem_addr  (imem.addr),
  .imem_rvalid(imem.rvalid),
  .imem_fault (imem.fault),
  // DMEM (read/write)
  .dmem_req   (dmem.req),
  .dmem_we    (dmem.we),
  .dmem_be    (dmem.be),
  .dmem_addr  (dmem.addr),
  .dmem_rvalid(dmem.rvalid),
  .dmem_fault (dmem.fault)
);

`endif // BIND_HARVOS_CORE_SV
