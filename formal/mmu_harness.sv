// mmu_harness.sv - formal harness for mmu_sv32 invariants
`define FORMAL
module mmu_harness;
  // clock & reset
  reg clk = 0;
  always #1 clk = ~clk;
  reg rst_n = 0;
  initial begin
    #2 rst_n = 1;
  end

  // DUT I/O (keep most unconstrained, add basic assumptions)
  reg  [31:0] if_vaddr;
  reg         if_req;
  wire [31:0] if_paddr;
  wire        if_ready;
  wire        if_fault;
  wire        if_perm_x;

  reg  [31:0] d_vaddr;
  reg         d_req;
  reg  [1:0]  d_acc;
  wire [31:0] d_paddr;
  wire        d_ready;
  wire        d_fault;
  wire        d_perm_r, d_perm_w, d_perm_x;

  reg  [31:0] csr_satp_q;
  reg  [31:0] csr_sstatus_q;
  reg  [1:0]  cur_priv;

  // sfence/ptw (unused by stub, tie off or leave free)
  reg         sfence_flush_all;
  reg  [31:0] sfence_vaddr;
  reg         sfence_addr_valid;
  reg  [15:0] sfence_asid;
  reg         sfence_asid_valid;
  wire        ptw_req;
  wire [31:0] ptw_addr;
  reg  [31:0] ptw_rdata;
  reg         ptw_rvalid;
  reg         ptw_fault;

  // simple driving
  always @(posedge clk) begin
    if (!rst_n) begin
      if_vaddr <= 0; if_req <= 0;
      d_vaddr <= 0; d_req <= 0; d_acc <= 0;
      csr_satp_q <= 32'h8000_0000; // MODE!=0 (not bare)
      csr_sstatus_q <= 0;
      cur_priv <= 2'b01; // S mode
      sfence_flush_all <= 0; sfence_vaddr <= 0; sfence_addr_valid <= 0;
      sfence_asid <= 0; sfence_asid_valid <= 0;
      ptw_rdata <= 0; ptw_rvalid <= 0; ptw_fault <= 0;
    end else begin
      // unconstrained-ish changes
      if_vaddr <= $anyseq; if_req <= $anyseq;
      d_vaddr  <= $anyseq; d_req <= $anyseq; d_acc <= $anyseq;
      // keep paging enabled for invariants
      csr_satp_q[31:30] <= 2'b10;
      // keep MXR/SUM arbitrary
      csr_sstatus_q[19] <= $anyseq; // MXR
      csr_sstatus_q[18] <= $anyseq; // SUM
      cur_priv <= $anyseq;
      // tie off PTW, sfence
      sfence_flush_all <= 0; sfence_vaddr <= 0; sfence_addr_valid <= 0;
      sfence_asid <= 0; sfence_asid_valid <= 0;
      ptw_rdata <= 0; ptw_rvalid <= 0; ptw_fault <= 0;
    end
  end

  // Under formal, assume clocking & reset are sane
  // (SymbiYosys will interpret $anyseq)
  mmu_sv32 dut (
    .clk(clk),
    .rst(1'b0),
    .rst_n(rst_n),
    .if_vaddr(if_vaddr),
    .if_req(if_req),
    .if_paddr(if_paddr),
    .if_ready(if_ready),
    .if_fault(if_fault),
    .if_perm_x(if_perm_x),
    .d_vaddr(d_vaddr),
    .d_req(d_req),
    .d_acc(d_acc),
    .d_paddr(d_paddr),
    .d_ready(d_ready),
    .d_fault(d_fault),
    .d_perm_r(d_perm_r),
    .d_perm_w(d_perm_w),
    .d_perm_x(d_perm_x),
    .csr_satp_q(csr_satp_q),
    .csr_sstatus_q(csr_sstatus_q),
    .cur_priv(cur_priv),
    .sfence_flush_all(sfence_flush_all),
    .sfence_vaddr(sfence_vaddr),
    .sfence_addr_valid(sfence_addr_valid),
    .sfence_asid(sfence_asid),
    .sfence_asid_valid(sfence_asid_valid),
    .ptw_req(ptw_req),
    .ptw_addr(ptw_addr),
    .ptw_rdata(ptw_rdata),
    .ptw_rvalid(ptw_rvalid),
    .ptw_fault(ptw_fault)
  );

  // Inline the same I-space window used by the DUT for cross-checks
  localparam [31:0] I_SPACE_BASE = 32'h0000_0000;
  localparam [31:0] I_SPACE_END  = 32'h000F_FFFF;

  // Assertions equivalent to tmp/mmu_invariants but without bind
  // D-path NX
  always @(posedge clk) if (rst_n) assume (csr_satp_q[31] == 1'b1); // paging enabled
  always @(posedge clk) if (rst_n) assert (d_perm_x == 1'b0);
  // No W^X
  always @(posedge clk) if (rst_n) assert (!(d_perm_w && d_perm_x));
  // Harvard D: access into I-space must fault
  function [0:0] is_in_ispace; input [31:0] paddr; begin
    is_in_ispace = (paddr >= I_SPACE_BASE) && (paddr <= I_SPACE_END);
  end endfunction
  always @(posedge clk) if (rst_n)
    assert (!(d_req && is_in_ispace(d_paddr)) || d_fault);

endmodule
