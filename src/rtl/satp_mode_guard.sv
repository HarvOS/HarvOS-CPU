// satp_mode_guard.sv — Enforce "paging always on" (satp.MODE != 0)
// SystemVerilog 2005
// Use this as a drop-in around your CSR write path for SATP. It rejects MODE=0 writes
// by raising an illegal-instruction write error pulse, and forces MODE to the enforced value.
// Also emits a one-cycle 'tlb_global_flush' on any satp write that changes ASID or PPN.
`timescale 1ns/1ps

module satp_mode_guard #(
  parameter [3:0] ENFORCED_MODE = 4'd1  // SV32=1
)(
  input  wire        clk,
  input  wire        rst_n,

  // satp write request from core/CSR file
  input  wire        satp_wr_en,     // 1-cycle pulse when software writes SATP
  input  wire [31:0] satp_wr_wdata,  // {MODE[31:28], ASID[27:22], PPN[21:0]} for SV32

  // current latched satp (from CSR file)
  input  wire [31:0] satp_q,

  // outputs to CSR file / MMU
  output wire [31:0] satp_wr_wdata_masked, // corrected/forced value to actually latch
  output wire        satp_wr_reject,       // pulse: attempted write with MODE=0 (illegal per HarvOS)
  output reg         tlb_global_flush      // pulse: when ASID or PPN changes
);
  wire [3:0] mode_in  = satp_wr_wdata[31:28];
  wire [5:0] asid_in  = satp_wr_wdata[27:22];
  wire [21:0]ppn_in   = satp_wr_wdata[21:0];

  wire [3:0] mode_q   = satp_q[31:28];
  wire [5:0] asid_q   = satp_q[27:22];
  wire [21:0]ppn_q    = satp_q[21:0];

  // reject if MODE=0 was attempted; but still enforce nonzero MODE on the latched value
  assign satp_wr_reject       = satp_wr_en && (mode_in == 4'd0);
  assign satp_wr_wdata_masked = { ENFORCED_MODE, asid_in, ppn_in }; // force MODE

  // global flush if ASID or PPN changes (MODE is constant)
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) tlb_global_flush <= 1'b0;
    else begin
      tlb_global_flush <= 1'b0;
      if (satp_wr_en && ((asid_in != asid_q) || (ppn_in != ppn_q))) begin
        tlb_global_flush <= 1'b1;
      end
    end
  end
endmodule
