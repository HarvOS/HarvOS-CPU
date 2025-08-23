// exec_ppn_tracker.sv — Tracks physical pages (PPN) that are executable
// SV32-oriented (PPN = PA[31:12]), but parameterized.
// On ITLB fill (or PTE accept) with X=1, insert PPN into a small CAM.
// On SFENCE.VMA (global) or SATP write, clear the CAM.
// Query: given PA, tells if its PPN is marked executable.
`timescale 1ns/1ps

module exec_ppn_tracker #(
  parameter int unsigned PPN_W = 20,  // SV32: 32-12
  parameter int unsigned N     = 16   // number of tracked PPNs
)(
  input  wire                 clk,
  input  wire                 rst_n,

  // Control
  input  wire                 clear_i,      // pulse: sfence.vma (global) or satp change
  input  wire                 insert_i,     // pulse: new ITLB entry with X=1 accepted
  input  wire [PPN_W-1:0]     insert_ppn,

  // Query
  input  wire [31:0]          query_pa,     // physical address
  output wire                 hit_exec_ppn
);
  localparam int unsigned IDX_W = $clog2(N);

  reg [PPN_W-1:0] cam_ppn [N-1:0];
  reg             cam_vld [N-1:0];
  reg [IDX_W-1:0] wr_ptr;

  integer i;

  // write pointer advances on each insert
  wire [PPN_W-1:0] query_ppn = query_pa[31:12];

  // combinational CAM lookup
  reg hit_r;
  always @(*) begin
    hit_r = 1'b0;
    for (i=0;i<N;i=i+1) begin
      if (cam_vld[i] && cam_ppn[i] == query_ppn) hit_r = 1'b1;
    end
  end
  assign hit_exec_ppn = hit_r;

  // state
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i=0;i<N;i=i+1) begin
        cam_vld[i] <= 1'b0;
        cam_ppn[i] <= '0;
      end
      wr_ptr <= '0;
    end else begin
      if (clear_i) begin
        for (i=0;i<N;i=i+1) cam_vld[i] <= 1'b0;
      end
      if (insert_i) begin
        cam_ppn[wr_ptr] <= insert_ppn;
        cam_vld[wr_ptr] <= 1'b1;
        wr_ptr          <= wr_ptr + {{(IDX_W-1){1'b0}},1'b1};
      end
    end
  end
endmodule
