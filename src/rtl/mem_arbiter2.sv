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


module mem_arbiter2 (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        d_req,
  input  logic        d_we,
  input  logic [3:0]  d_be,
  input  logic [31:0] d_addr,
  input  logic [31:0] d_wdata,
  output logic [31:0] d_rdata,
  output logic        d_rvalid,
  output logic        d_fault,
  input  logic        i_req,
  input  logic [31:0] i_addr,
  output logic [31:0] i_rdata,
  output logic        i_rvalid,
  output logic        i_fault,
  output logic        m_req,
  output logic        m_we,
  output logic [3:0]  m_be,
  output logic [31:0] m_addr,
  output logic [31:0] m_wdata,
  input  logic [31:0] m_rdata,
  input  logic        m_rvalid,
  input  logic        m_fault
);
  typedef enum logic [0:0] {GNT_D=1'b0, GNT_I=1'b1} gnt_e;
  gnt_e gnt_q, gnt_n;
  always_comb begin
    if (d_req) gnt_n = GNT_D;
    else if (i_req) gnt_n = GNT_I;
    else gnt_n = gnt_q;
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) gnt_q <= GNT_D;
    else        gnt_q <= gnt_n;
  end

  assign m_req   = (gnt_q==GNT_D) ? d_req : i_req;
  assign m_we    = (gnt_q==GNT_D) ? d_we  : 1'b0;
  assign m_be    = (gnt_q==GNT_D) ? d_be  : 4'hF;
  assign m_addr  = (gnt_q==GNT_D) ? d_addr: i_addr;
  assign m_wdata = (gnt_q==GNT_D) ? d_wdata : 32'h0;

  assign d_rvalid = (gnt_q==GNT_D) ? m_rvalid : 1'b0;
  assign d_rdata  = (gnt_q==GNT_D) ? m_rdata  : 32'h0;
  assign d_fault  = (gnt_q==GNT_D) ? m_fault  : 1'b0;

  assign i_rvalid = (gnt_q==GNT_I) ? m_rvalid : 1'b0;
  assign i_rdata  = (gnt_q==GNT_I) ? m_rdata  : 32'h0;
  assign i_fault  = (gnt_q==GNT_I) ? m_fault  : 1'b0;
endmodule

