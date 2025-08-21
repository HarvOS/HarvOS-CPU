// top_soc.sv — Synthesis top that exposes SoC buses and datapaths
`include "rtl/harvos_pkg_flat.svh"
`include "rtl/harvos_imem_if.sv"
`include "rtl/harvos_dmem_if.sv"

module top_soc(
  input  logic        clk,
  input  logic        rst_n,
  // I-side debug
  output logic [31:0] dbg_ic_addr,
  output logic        dbg_ic_req,
  output logic [31:0] dbg_i_addr_arb,
  output logic        dbg_i_req_arb,
  output logic [31:0] dbg_imem_rdata,
  output logic        dbg_imem_rvalid,
  output logic        dbg_imem_fault,
  // D-side debug
  output logic [31:0] dbg_dc_addr,
  output logic        dbg_dc_req,
  output logic [31:0] dbg_dmem_rdata,
  output logic        dbg_dmem_done,
  output logic        dbg_dmem_fault,
  // Shared RAM port debug
  output logic [31:0] dbg_m_addr,
  output logic        dbg_m_req,
  output logic [31:0] dbg_m_rdata,
  output logic        dbg_m_rvalid,
  output logic        dbg_m_fault,
  // D-side write channel
  output logic [31:0] dbg_dmem_wdata,
  output logic  [3:0] dbg_dmem_be,
  output logic        dbg_dmem_we
,
  // DMA master port (optional)
  harvos_dmem_if dma
);
  // Harvard IFs
  harvos_imem_if imem();
  harvos_dmem_if dmem();

  // Keep core hierarchy to reduce sweeping of internals (Yosys respects keep_hierarchy)
    
  // --- Revised: simple MPU programming FSM (synth-friendly, no arrays/typedefs) ---
  // Define two constant regions for programming at boot.
  // Adjust these constants to your memory map.
  localparam logic [31:0] MPU0_BASE      = 32'h0000_0000;
  localparam logic [31:0] MPU0_LIMIT     = 32'h0000_FFFF; // ROM size - 1
  localparam logic [2:0]  MPU0_PERM      = 3'b101;        // X=1,W=0,R=1  (R-X)
  localparam logic        MPU0_USER_OK   = 1'b1;
  localparam logic        MPU0_IS_ISPACE = 1'b1;          // instruction space

  localparam logic [31:0] MPU1_BASE      = 32'h2000_0000; // RAM base
  localparam logic [31:0] MPU1_LIMIT     = 32'h2001_FFFF; // RAM end
  localparam logic [2:0]  MPU1_PERM      = 3'b011;        // X=0,W=1,R=1  (RW, NX)
  localparam logic        MPU1_USER_OK   = 1'b1;
  localparam logic        MPU1_IS_ISPACE = 1'b0;

// Region 2 (MMIO): R/W, NX, **No User**
localparam logic [31:0] MPU2_BASE      = 32'h1000_0000; // Example MMIO window
localparam logic [31:0] MPU2_LIMIT     = 32'h1000_FFFF; // 64 KiB MMIO
localparam logic [2:0]  MPU2_PERM      = 3'b011;        // {X,W,R} = 0,1,1  (RW, NX)
localparam logic        MPU2_USER_OK   = 1'b0;          // <== No User MMIO
localparam logic        MPU2_IS_ISPACE = 1'b0;          // D-space

  // Strobes and data to the core's programming port
// --- Synth-friendly MPU programming FSM (array-free, no latches) ---
// Region 0 (ROM / I-space): R-X (execute allowed, read allowed, write disallowed)
localparam logic [31:0] MPU0_BASE      = 32'h0000_0000; // TODO adjust
localparam logic [31:0] MPU0_LIMIT     = 32'h0000_FFFF; // TODO adjust
localparam logic [2:0]  MPU0_PERM      = 3'b101;        // {X,W,R}
localparam logic        MPU0_USER_OK   = 1'b1;
localparam logic        MPU0_IS_ISPACE = 1'b1;

// Region 1 (RAM): R/W, NX
localparam logic [31:0] MPU1_BASE      = 32'h2000_0000; // TODO adjust
localparam logic [31:0] MPU1_LIMIT     = 32'h2001_FFFF; // TODO adjust
localparam logic [2:0]  MPU1_PERM      = 3'b011;        // {X,W,R}
localparam logic        MPU1_USER_OK   = 1'b1;
localparam logic        MPU1_IS_ISPACE = 1'b0;

// Drive core's programming pins
logic        mpu_prog_en_q;
logic  [2:0] mpu_prog_idx_q;
logic [31:0] mpu_prog_base_q, mpu_prog_limit_q;
logic  [2:0] mpu_prog_perm_q;
logic        mpu_prog_user_ok_q, mpu_prog_is_ispace_q;

typedef enum logic [1:0] { MCFG_IDLE, MCFG_BASE, MCFG_LIMIT, MCFG_PERM } mcfg_e;
mcfg_e mcfg_q, mcfg_d;
logic  mcfg_i_q, mcfg_i_d; // 0 => region0, 1 => region1
logic  mcfg_mmio_q, mcfg_mmio_d; // extra pass for region2 (MMIO)

always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    mcfg_q        <= MCFG_BASE;
    mcfg_i_q      <= 1'b0;
    mpu_prog_en_q <= 1'b0;
    mcfg_mmio_q   <= 1'b0;
  end else begin
    mcfg_q        <= mcfg_d;
    mcfg_i_q      <= mcfg_i_d;
    mcfg_mmio_q   <= mcfg_mmio_d;
    // Emit a write pulse while the FSM is active (BASE/LIMIT/PERM)
    mpu_prog_en_q <= (mcfg_d != MCFG_IDLE);
  end
end

always_comb begin
  // Defaults (prevent latches)
  mcfg_d                = mcfg_q;
  mcfg_i_d              = mcfg_i_q;
  mcfg_mmio_d           = mcfg_mmio_q;
  mpu_prog_idx_q        = (mcfg_mmio_q ? 3'd2 : {2'b00, mcfg_i_q});
  mpu_prog_base_q       = 32'h0;
  mpu_prog_limit_q      = 32'h0;
  mpu_prog_perm_q       = 3'b000;
  mpu_prog_user_ok_q    = 1'b0;
  mpu_prog_is_ispace_q  = 1'b0;

  unique case (mcfg_q)
    MCFG_BASE: begin
      mpu_prog_base_q = mcfg_mmio_q ? MPU2_BASE : ((mcfg_i_q == 1'b0) ? MPU0_BASE : MPU1_BASE);
      mcfg_d          = MCFG_LIMIT;
    end
    MCFG_LIMIT: begin
      mpu_prog_limit_q = mcfg_mmio_q ? MPU2_LIMIT : ((mcfg_i_q == 1'b0) ? MPU0_LIMIT : MPU1_LIMIT);
      mcfg_d           = MCFG_PERM;
    end
    MCFG_PERM: begin
      mpu_prog_perm_q      = mcfg_mmio_q ? MPU2_PERM : ((mcfg_i_q == 1'b0) ? MPU0_PERM : MPU1_PERM);
      mpu_prog_user_ok_q   = mcfg_mmio_q ? MPU2_USER_OK : ((mcfg_i_q == 1'b0) ? MPU0_USER_OK : MPU1_USER_OK);
      mpu_prog_is_ispace_q = mcfg_mmio_q ? MPU2_IS_ISPACE : ((mcfg_i_q == 1'b0) ? MPU0_IS_ISPACE : MPU1_IS_ISPACE);
if (mcfg_mmio_q == 1'b1) begin
  // Just finished MMIO (region2) -> go idle
  mcfg_mmio_d = 1'b0;
  mcfg_d      = MCFG_IDLE;
end else if (mcfg_i_q == 1'b0) begin
  // Next: region1 (RAM)
  mcfg_i_d = 1'b1;
  mcfg_d   = MCFG_BASE;
end else begin
  // Next: region2 (MMIO), signal extra pass
  mcfg_mmio_d = 1'b1;
  mcfg_d      = MCFG_BASE;
end
    end
    default: ; // IDLE
  endcase
end

harvos_core u_core (
    .clk(clk),
    .rst_n(rst_n),
    .imem(imem),
    .dmem(dmem),
    .entropy_valid(1'b0),
    .entropy_data(32'h0),
    .ext_irq(1'b0),
    .mpu_prog_en(mpu_prog_en_q),
    .mpu_prog_idx(mpu_prog_idx_q),
    .mpu_prog_base(mpu_prog_base_q),
    .mpu_prog_limit(mpu_prog_limit_q),
    .mpu_prog_perm(mpu_prog_perm_q),
    .mpu_prog_user_ok(mpu_prog_user_ok_q),
    .mpu_prog_is_ispace(mpu_prog_is_ispace_q) //b0)
  );

  // ---------------- I$ side mux: Boot ROM vs RAM/Arb ----------------
  localparam integer ROM_BYTES = 16*1024; // 16 KiB @ 0x0000_0000
  logic        rom_req;
  logic [31:0] rom_addr;
  logic [31:0] rom_rdata;
  logic        rom_rvalid;
  logic        rom_fault;

  // Expose core's I-side
  wire        ic_m_req   = imem.req;
  wire [31:0] ic_m_addr  = imem.addr;

  // ROM window select
  wire        rom_sel    = (ic_m_addr < ROM_BYTES);
  assign rom_req         = ic_m_req & rom_sel;
  assign rom_addr        = ic_m_addr;

  // I-side to RAM arbiter path when not ROM
  wire        i_req_arb  = ic_m_req & ~rom_sel;
  wire [31:0] i_addr_arb = ic_m_addr;
  wire [31:0] i_rdata_arb;
  wire        i_rvalid_arb;
  wire        i_fault_arb;

  // ---------------- D-side signals into shared RAM ------------------
  wire        d_req_arb   = dmem.req;
  wire        d_we_arb    = dmem.we;
  wire [3:0]  d_be_arb    = dmem.be;
  wire [31:0] d_addr_arb  = dmem.addr;
  wire [31:0] d_wdata_arb = dmem.wdata;

  // ---------------- Simple 2:1 arbiter for shared RAM ---------------
  // Priority: I-side when requesting, else D-side
  logic        m_req, m_we;
  logic [3:0]  m_be;
  logic [31:0] m_addr, m_wdata;
  logic [31:0] m_rdata;
  logic        m_rvalid, m_fault;

  always_comb begin
    // default
    m_req   = 1'b0;
    m_we    = 1'b0;
    m_be    = 4'b0000;
    m_addr  = 32'h0;
    m_wdata = 32'h0;
    // I-side takes priority
    if (i_req_arb) begin
      m_req   = 1'b1;
      m_we    = 1'b0;
      m_be    = 4'b0000;
      m_addr  = i_addr_arb;
      m_wdata = 32'h0;
    end else if (d_req_arb) begin
      m_req   = 1'b1;
      m_we    = d_we_arb;
      m_be    = d_be_arb;
      m_addr  = d_addr_arb;
      m_wdata = d_wdata_arb;
    end

  end

// --- DMA firewall ---
// Parameters: ROM window = 16 KiB (boot ROM). No privileged regions by default.
logic        dma_fw_req;
logic        dma_fw_we;
logic [3:0]  dma_fw_be;
logic [31:0] dma_fw_addr;
logic [31:0] dma_fw_wdata;

harvos_dma_firewall u_dma_fw (
  .clk   (clk),
  .rst_n (rst_n),
  .dma   (dma),

  .fw_req   (dma_fw_req),
  .fw_we    (dma_fw_we),
  .fw_be    (dma_fw_be),
  .fw_addr  (dma_fw_addr),
  .fw_wdata (dma_fw_wdata),

  .m_rdata  (m_rdata),
  .m_rvalid (m_rvalid),
  .m_fault  (m_fault)
);

// Extend memory request mux: I > D > DMA (simple priority)
always_comb begin
  m_req   = 1'b0;
  m_we    = 1'b0;
  m_be    = 4'b0000;
  m_addr  = 32'h0;
  m_wdata = 32'h0;

  if (i_req_arb) begin
    m_req   = 1'b1;
    m_we    = 1'b0;
    m_be    = 4'b0000;
    m_addr  = i_addr_arb;
    m_wdata = 32'h0;
  end else if (d_req_arb) begin
    m_req   = 1'b1;
    m_we    = d_we_arb;
    m_be    = d_be_arb;
    m_addr  = d_addr_arb;
    m_wdata = d_wdata_arb;
  end else if (dma_fw_req) begin
    m_req   = 1'b1;
    m_we    = dma_fw_we;
    m_be    = dma_fw_be;
    m_addr  = dma_fw_addr;
    m_wdata = dma_fw_wdata;
  end
end


  // Track current owner of the memory request to route responses correctly
  typedef enum logic [1:0] {OWN_NONE, OWN_I, OWN_D, OWN_DMA} owner_e;
  owner_e owner_q, owner_n;

  always_comb begin
    owner_n = owner_q;
    if (owner_q == OWN_NONE) begin
      if (i_req_arb)      owner_n = OWN_I;
      else if (d_req_arb) owner_n = OWN_D;
      else if (dma_fw_req)owner_n = OWN_DMA;
    end else if (m_rvalid) begin
      owner_n = OWN_NONE;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) owner_q <= OWN_NONE;
    else        owner_q <= owner_n;
  end

  // Return paths to I, D, and DMA

  assign i_rdata_arb  = m_rdata;
  assign i_rvalid_arb = m_rvalid & (owner_q==OWN_I);
  assign i_fault_arb  = m_fault & (owner_q==OWN_I);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dmem.rdata <= 32'h0;
      dmem.done  <= 1'b0;
      dmem.fault <= 1'b0;
    end else begin
      // D-path response
      dmem.done  <= m_rvalid & (owner_q==OWN_D);
      if (m_rvalid & (owner_q==OWN_D) & ~d_we_arb) begin
        dmem.rdata <= m_rdata;
      end
      dmem.fault <= m_fault & (owner_q==OWN_D);

      // DMA response (proxied by firewall)
      if (m_rvalid & dma_fw_req & ~dma_fw_we) begin
        // rdata is driven inside u_dma_fw; nothing to do here
      end
  end
end

  // ------------------- Boot ROM instance ----------------------------
  simple_bootrom u_bootrom (
    .clk(clk), .rst_n(rst_n),
    .req(rom_req), .addr(rom_addr),
    .rdata(rom_rdata), .rvalid(rom_rvalid), .fault(rom_fault)
  );

  // ------------------- Shared RAM instance --------------------------
  simple_ram #(.WORDS(16384)) u_ram (
    .clk(clk), .rst_n(rst_n),
    .req(m_req), .we(m_we), .be(m_be),
    .addr(m_addr), .wdata(m_wdata),
    .rdata(m_rdata), .rvalid(m_rvalid), .fault(m_fault)
  );

  // ------------------- I-side return mux (ROM vs RAM) ---------------
  assign imem.rdata  = rom_sel ? rom_rdata  : i_rdata_arb;
  assign imem.rvalid = rom_sel ? rom_rvalid : i_rvalid_arb;
  assign imem.fault  = rom_sel ? rom_fault  : i_fault_arb;

  // ------------------- Debug/keep outputs ---------------------------
  // Mark with keep so they don't get optimized away even if identical
  (* keep = "true" *) logic [31:0] keep_ic_addr, keep_i_addr_arb, keep_dc_addr, keep_m_addr;
  (* keep = "true" *) logic        keep_ic_req,  keep_i_req_arb,  keep_dc_req,  keep_m_req;
  (* keep = "true" *) logic [31:0] keep_imem_rdata, keep_dmem_rdata, keep_m_rdata;
  (* keep = "true" *) logic        keep_imem_rvalid, keep_imem_fault, keep_dmem_done, keep_dmem_fault, keep_m_rvalid, keep_m_fault;
  (* keep = "true" *) logic [31:0] keep_dmem_wdata;
  (* keep = "true" *) logic  [3:0] keep_dmem_be;
  (* keep = "true" *) logic        keep_dmem_we;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      {dbg_ic_addr, dbg_i_addr_arb, dbg_dc_addr, dbg_m_addr} <= '0;
      {dbg_imem_rdata, dbg_dmem_rdata, dbg_m_rdata} <= '0;
      {dbg_ic_req, dbg_i_req_arb, dbg_dc_req, dbg_m_req} <= '0;
      {dbg_imem_rvalid, dbg_imem_fault, dbg_dmem_done, dbg_dmem_fault, dbg_m_rvalid, dbg_m_fault} <= '0;
      {dbg_dmem_wdata, dbg_dmem_be} <= '0;
      dbg_dmem_we <= 1'b0;

      keep_ic_addr <= '0; keep_i_addr_arb <= '0; keep_dc_addr <= '0; keep_m_addr <= '0;
      keep_imem_rdata <= '0; keep_dmem_rdata <= '0; keep_m_rdata <= '0;
      keep_ic_req <= 1'b0; keep_i_req_arb <= 1'b0; keep_dc_req <= 1'b0; keep_m_req <= 1'b0;
      keep_imem_rvalid <= 1'b0; keep_imem_fault <= 1'b0; keep_dmem_done <= 1'b0; keep_dmem_fault <= 1'b0; keep_m_rvalid <= 1'b0; keep_m_fault <= 1'b0;
      keep_dmem_wdata <= '0; keep_dmem_be <= '0; keep_dmem_we <= 1'b0;
    end else begin
      // live taps
      keep_ic_addr    <= ic_m_addr;    dbg_ic_addr    <= keep_ic_addr;
      keep_ic_req     <= ic_m_req;     dbg_ic_req     <= keep_ic_req;
      keep_i_addr_arb <= i_addr_arb;   dbg_i_addr_arb <= keep_i_addr_arb;
      keep_i_req_arb  <= i_req_arb;    dbg_i_req_arb  <= keep_i_req_arb;

      keep_imem_rdata  <= imem.rdata;   dbg_imem_rdata  <= keep_imem_rdata;
      keep_imem_rvalid <= imem.rvalid;  dbg_imem_rvalid <= keep_imem_rvalid;
      keep_imem_fault  <= imem.fault;   dbg_imem_fault  <= keep_imem_fault;

      keep_dc_addr    <= d_addr_arb;   dbg_dc_addr    <= keep_dc_addr;
      keep_dc_req     <= d_req_arb;    dbg_dc_req     <= keep_dc_req;

      keep_dmem_rdata <= dmem.rdata;   dbg_dmem_rdata <= keep_dmem_rdata;
      keep_dmem_done  <= dmem.done;    dbg_dmem_done  <= keep_dmem_done;
      keep_dmem_fault <= dmem.fault;   dbg_dmem_fault <= keep_dmem_fault;

      keep_m_addr     <= m_addr;       dbg_m_addr     <= keep_m_addr;
      keep_m_req      <= m_req;        dbg_m_req      <= keep_m_req;
      keep_m_rdata    <= m_rdata;      dbg_m_rdata    <= keep_m_rdata;
      keep_m_rvalid   <= m_rvalid;     dbg_m_rvalid   <= keep_m_rvalid;
      keep_m_fault    <= m_fault;      dbg_m_fault    <= keep_m_fault;

      keep_dmem_wdata <= d_wdata_arb;  dbg_dmem_wdata <= keep_dmem_wdata;
      keep_dmem_be    <= d_be_arb;     dbg_dmem_be    <= keep_dmem_be;
      keep_dmem_we    <= d_we_arb;     dbg_dmem_we    <= keep_dmem_we;
    end
  end
endmodule
