// harvos_mmu_baremode_sva.sv — assert that satp.MODE is never Bare (0) on RV32
`ifndef SYNTHESIS
module harvos_mmu_baremode_sva (
  input logic clk, input logic rst_n,
  input logic [31:0] csr_satp_q
);
  // MODE bit is [31] for RV32: must always be 1
  always @(posedge clk) if (rst_n) begin
    if (csr_satp_q[31] == 1'b0) $error("MMU: satp.MODE observed Bare (0) — forbidden");
  end
endmodule
`endif
