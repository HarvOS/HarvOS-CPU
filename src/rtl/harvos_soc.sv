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
`include "harvos_imem_if.sv"
`include "harvos_dmem_if.sv"

module harvos_soc (
  input  logic clk,
  input  logic rst_n
);
  // Boot ROM window
  localparam integer ROM_BYTES = 16*1024; // 16 KiB @ 0x0000_0000

  // Harvard IFs
  harvos_imem_if imem();
  harvos_dmem_if dmem();


  // Core
  logic icache_flush_all;
  harvos_core u_core (
    .clk(clk),
    .rst_n(rst_n),
    .imem(imem),
    .dmem(dmem),
    .entropy_valid(1'b0),
    .entropy_data(32'h0),
    .ext_irq(1'b0),
    .mpu_prog_en(1'b0),
    .mpu_prog_idx(3'd0),
    .mpu_prog_base(32'h0),
    .mpu_prog_limit(32'h0),
    .mpu_prog_perm(3'b000),
    .mpu_prog_user_ok(1'b0),
    .mpu_prog_is_ispace(1'b0)
  );

  // I-Cache
  logic        ic_m_req;
  logic [31:0] ic_m_addr;
  logic [31:0] ic_m_rdata;
  logic        ic_m_rvalid;
  logic        ic_m_fault;
  // Bridge icache mem interface to legacy wires
  assign ic_m_req  = imem.req;
  assign ic_m_addr = imem.addr;
  // rdata/rvalid/fault now driven into imem above
  // Boot ROM (read-only)
  logic        rom_req;
  logic [31:0] rom_addr;
  logic [31:0] rom_rdata;
  logic        rom_rvalid;
  logic        rom_fault;

  simple_bootrom #(.WORDS(ROM_BYTES/4)) u_bootrom (
    .clk(clk), .rst_n(rst_n),
    .req(rom_req), .addr(rom_addr),
    .rdata(rom_rdata), .rvalid(rom_rvalid), .fault(rom_fault)
  );

  // D-Cache
  logic        dc_m_req, dc_m_we;
  logic [3:0]  dc_m_be;
  logic [31:0] dc_m_addr, dc_m_wdata;
  logic [31:0] dc_m_rdata;
  logic        dc_m_rvalid, dc_m_fault;

  dcache u_dcache (
    .clk(clk), .rst_n(rst_n),
    // CPU side
    .cpu_req   (dmem.req),
    .cpu_we    (dmem.we),
    .cpu_be    (dmem.be),
    .cpu_addr  (dmem.addr),
    .cpu_wdata (dmem.wdata),
    .cpu_rdata (dmem.rdata),
    .cpu_done  (dmem.done),
    .cpu_fault (dmem.fault),
    // MEM side
    .mem_req   (dc_m_req),
    .mem_we    (dc_m_we),
    .mem_be    (dc_m_be),
    .mem_addr  (dc_m_addr),
    .mem_wdata (dc_m_wdata),
    .mem_rdata (dc_m_rdata),
    .mem_rvalid(dc_m_rvalid),
    .mem_fault (dc_m_fault)
  );

  // Arbiter -> RAM
  logic        m_req, m_we;
  logic [3:0]  m_be;
  logic [31:0] m_addr, m_wdata, m_rdata;
  logic        m_rvalid, m_fault;

  // I$ path to ROM or RAM
  wire         rom_sel   = (ic_m_addr < ROM_BYTES);
  assign rom_req  = ic_m_req & rom_sel;
  assign rom_addr = ic_m_addr;

  // Arbiter inputs: I$ drives only when not selecting ROM
  wire         i_req_arb   = ic_m_req & ~rom_sel;
  wire [31:0]  i_addr_arb  = ic_m_addr;

  // Arbiter outputs for I$ (before mux)
  wire [31:0]  i_rdata_arb;
  wire         i_rvalid_arb;
  wire         i_fault_arb;

  mem_arbiter2 u_arb (
    .clk(clk), .rst_n(rst_n),
    // D$ master
    .d_req(dc_m_req), .d_we(dc_m_we), .d_be(dc_m_be),
    .d_addr(dc_m_addr), .d_wdata(dc_m_wdata),
    .d_rdata(dc_m_rdata), .d_rvalid(dc_m_rvalid), .d_fault(dc_m_fault),
    // I$ master (gated)
    .i_req(i_req_arb), .i_addr(i_addr_arb),
    .i_rdata(i_rdata_arb), .i_rvalid(i_rvalid_arb), .i_fault(i_fault_arb),
    // To RAM
    .m_req(m_req), .m_we(m_we), .m_be(m_be), .m_addr(m_addr), .m_wdata(m_wdata),
    .m_rdata(m_rdata), .m_rvalid(m_rvalid), .m_fault(m_fault)
  );

  // I$ return mux (ROM vs RAM)
  assign imem.rdata  = rom_sel ? rom_rdata  : i_rdata_arb;
  assign imem.rvalid = rom_sel ? rom_rvalid : i_rvalid_arb;
  assign imem.fault  = rom_sel ? rom_fault  : i_fault_arb;

  // RAM
  simple_ram #(.WORDS(16384)) u_ram (
    .clk(clk), .rst_n(rst_n),
    .req(m_req), .we(m_we), .be(m_be),
    .addr(m_addr), .wdata(m_wdata),
    .rdata(m_rdata), .rvalid(m_rvalid), .fault(m_fault)
  );
endmodule
