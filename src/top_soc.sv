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

  
  // Dummy sink for unused DMA Firewall readback (Yosys dislikes tying output to constants)
// Exported from core: sticky LOCK bit
  logic smpuctl_lock;
  logic sfence_global;
  logic asid_change_pulse;

  // Harvard IFs
  harvos_imem_if imem();
  harvos_imem_if imem_cache();
  harvos_dmem_if dmem();

  
// Consolidate all DMA masters via dma_gateway → firewall
harvos_dmem_if dma_mux(); // output of gateway, input to firewall
// Additional internal hookpoints for future DMAs (currently unused)
harvos_dmem_if dma_m1();
harvos_dmem_if dma_m2();
harvos_dmem_if dma_m3();

dma_gateway u_dma_gw (
  .clk(clk), .rst_n(rst_n),
  .dma_m0(dma),     // external DMA port
  .dma_m1(dma_m1),  // future hook
  .dma_m2(dma_m2),  // future hook
  .dma_m3(dma_m3),  // future hook
  .dma_out(dma_mux)
);
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
localparam logic [31:0] MPU0_BASE      = 32'h0000_0000; // NOTE: adjust to your memory map as needed
localparam logic [31:0] MPU0_LIMIT     = 32'h0000_FFFF; // NOTE: adjust to your memory map as needed
localparam logic [2:0]  MPU0_PERM      = 3'b101;        // {X,W,R}
localparam logic        MPU0_USER_OK   = 1'b1;
localparam logic        MPU0_IS_ISPACE = 1'b1;

// Region 1 (RAM): R/W, NX
localparam logic [31:0] MPU1_BASE      = 32'h2000_0000; // NOTE: adjust to your memory map as needed
localparam logic [31:0] MPU1_LIMIT     = 32'h2001_FFFF; // NOTE: adjust to your memory map as needed
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
    .mpu_prog_is_ispace(mpu_prog_is_ispace_q),
    .smpuctl_lock_o(smpuctl_lock),
    .sfence_global_o(sfence_global),
    .asid_change_pulse_o(asid_change_pulse)
  ,
    .lock_set_i(boot_lock_pulse)
  ,
    .smpuctl_lock_o(smpuctl_lock),
    .dc_way_mask_i (dc_way_mask)
  );

  
  // I-Cache between core IMEM and memory/ROM
  icache u_icache (
    .clk(clk), .rst_n(rst_n),
    // CPU side from core
    .cpu_req(imem.req),
    .mpu_exec_allow(ext_icache_exec_allow), // core/MPU enforces execute rights; cache not authoritative
    .cpu_addr(imem.addr),
    .cpu_rdata(ic_cpu_rdata),
    .cpu_rvalid(ic_cpu_rvalid),
    .cpu_fault(ic_cpu_fault),
    // flush
    .inv_all(ic_inv),
    // memory side to ROM/RAM mux
    .mem(imem_cache)
  );

  // Drive core's IMEM return from I-Cache CPU side
  assign imem.rdata  = ic_cpu_rdata;
  assign imem.rvalid = ic_cpu_rvalid;
  assign imem.fault  = ic_cpu_fault;

  // ---------------- I$ side mux: Boot ROM vs RAM/Arb ----------------
  // I-Cache CPU-side wires
  logic [31:0] ic_cpu_rdata;
  logic        ic_cpu_rvalid;
  logic        ic_cpu_fault;
  logic        ic_inv;

  localparam integer ROM_BYTES = 16*1024; // 16 KiB @ 0x0000_0000
  logic        rom_req;
  logic [31:0] rom_addr;
  logic [31:0] rom_rdata;
  logic        rom_rvalid;
  logic        rom_fault;
  wire rom_sel = (ic_m_addr < ROM_BYTES);

  // Expose I-Cache memory side
  wire        ic_m_req   = imem_cache.req;
  wire [31:0] ic_m_addr  = imem_cache.addr;
  wire [31:0] ic_m_rdata;
  wire        ic_m_rvalid;
  wire        ic_m_fault;

  // ---------------- D-side signals into shared RAM ------------------
  wire        d_req_arb   = dmem.req;
  wire        d_we_arb    = dmem.we;
  wire [3:0]  d_be_arb    = dmem.be;
  wire [31:0] d_addr_arb  = dmem.addr;
  wire [31:0] d_wdata_arb = dmem.wdata;

  
  // ---------------- D-Cache (between CPU D-side and RAM) ---------------
  dcache u_dcache (
    .clk(clk), .rst_n(rst_n),
    // CPU side (gate off MMIO accesses so they bypass the cache path)
    .cpu_req   (d_req_arb && !cache_mmio_hit && !code_mmio_hit),
    .cpu_we    (d_we_arb),
    .cpu_be    (d_be_arb),
    .cpu_addr  (d_addr_arb),
    .cpu_wdata (d_wdata_arb),
    .cpu_rdata (dcache_cpu_rdata),
    .cpu_done  (dcache_cpu_done),
    .cpu_fault (dcache_cpu_fault),
    // MEM side
    .mem_req   (dc_m_req),
    .mem_we    (dc_m_we),
    .mem_be    (dc_m_be),
    .mem_addr  (dc_m_addr),
    .mem_wdata (dc_m_wdata),
    .mem_rdata (dc_m_rdata),
    .mem_rvalid(dc_m_rvalid),
    .mem_fault (dc_m_fault),
    // Flush control
    .inv_all   (dc_inv),
    .inv_ack   (dc_inv_ack)
  );
// ---------------- Simple 2:1 arbiter for shared RAM ---------------
  // Priority: I-side when requesting, else D-side
  logic        m_req, m_we;
  logic [3:0]  m_be;
  logic [31:0] m_addr, m_wdata;
  logic [31:0] m_rdata;
  logic        m_rvalid, m_fault;
  // --- HarvOS MMIO blocks: cache control + code immutability ---
  localparam logic [31:0] CACHE_CTRL_ADDR = 32'h1000_0100;
  localparam logic [31:0] CODE_CTRL_ADDR  = 32'h1000_0110;

  localparam logic [31:0] DMAFW_CTRL_ADDR = 32'h1000_0120;
  localparam logic [31:0] SIGCHECK_ADDR   = 32'h1000_0130;

  // MMIO decode/write strobes (D-side)
  logic        cache_mmio_hit, code_mmio_hit;
  logic        dmafw_mmio_hit, sig_mmio_hit;
  logic        mmio_wr;
  logic [3:0]  mmio_be;
  logic [31:0] mmio_wdata;
  logic [31:0] dmafw_mmio_rdata;
  logic [31:0] sig_mmio_rdata;

  // MMIO readbacks
  logic [31:0] cache_mmio_rdata;
  logic [31:0] code_mmio_rdata;

  // D$ invalidate signal (to SoC-internal caches if present)
  logic        dc_inv;

  
  
  // --- Boot signature check (MMIO-triggered). Must pass before WP/LOCK ---
  logic boot_sig_ok;
  boot_sigcheck u_boot_sig (
    .clk(clk), .rst_n(rst_n), .lock_i(smpuctl_lock),
    .wr_en(sig_mmio_hit & mmio_wr),
    .wr_data(mmio_wdata),
    .rd_data(sig_mmio_rdata),
    .sig_ok(boot_sig_ok)
  );

  // --- Boot policy sequencer: set WP, flush caches, then LOCK ---
  typedef enum logic [2:0] { BP_SIGWAIT, BP_WP, BP_FLUSH, BP_LOCK, BP_DONE } boot_e;
  boot_e boot_phase_q;
  logic  boot_wp_pulse, boot_cache_wr, boot_lock_pulse;
  logic [31:0] boot_cache_wdata;
// Code immutability signals
  logic        code_update_en_q;
  logic        code_wp_q;
  logic        code_wp_set_pulse;
  logic        allow_code_write;


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
    end else if (dc_m_req) begin
      m_req   = 1'b1;
      m_we    = dc_m_we & allow_code_write;
      m_be    = dc_m_be;
      m_addr  = dc_m_addr;
      m_wdata = dc_m_wdata;
    end

  end

  // Cache security control (flush via MMIO)
  logic ic_flush_req;
  logic [3:0] ic_way_mask_unused;
  cache_sec_ctrl #(.I_WAYS(1), .D_WAYS(2)) u_cache_ctrl_top (
    .clk(clk), .rst_n(rst_n),
    .asid_change_pulse(asid_change_pulse),
    .sfence_global(sfence_global),
    .lock_i(smpuctl_lock),
    .wr_en((cache_mmio_hit & mmio_wr) | boot_cache_wr),
    .wr_data(boot_cache_wr ? boot_cache_wdata : mmio_wdata),
    .rd_data(cache_mmio_rdata),
    .ic_flush_req(ic_flush_req),
    .dc_flush_req(/*autowire*/),
    .ic_way_mask(ic_way_mask_unused),
    .dc_way_mask(dc_way_mask)
  );
  wire dc_flush_req_w = u_cache_ctrl_top.dc_flush_req;

  // Observe D$ way mask (2-way)
  logic [1:0] dc_way_mask;

  cache_flush_adapter #(.HOLD_CYCLES(8)) u_dc_flush_top (
    .clk(clk), .rst_n(rst_n),
    .flush_req(dc_flush_req_w),
    .flush_ack(dc_inv_ack),
    .flush_do(dc_inv)
  );

  // I$ flush pulse stretcher
  cache_flush_adapter #(.HOLD_CYCLES(8)) u_ic_flush_top (
    .clk(clk), .rst_n(rst_n),
    .flush_req(ic_flush_req),
    .flush_ack(1'b0),
    .flush_do(ic_inv)
  );

  

  // Code immutability control
  code_sec_ctrl u_code_ctrl (
    .clk(clk), .rst_n(rst_n), .lock_i(smpuctl_lock),
    .wr_en((code_mmio_hit & mmio_wr) | boot_wp_pulse), .wr_data(boot_wp_pulse ? 32'h1 : mmio_wdata),
    .update_en_q(code_update_en_q), .wp_set_pulse(code_wp_set_pulse), .rd_data(code_mmio_rdata)
  );
  code_wp_latch u_code_wp (
    .clk(clk), .rst_n(rst_n), .lock_i(smpuctl_lock), .wp_set_i(code_wp_set_pulse | boot_wp_pulse), .manuf_mode_i(1'b0),
    .wp_q(code_wp_q)
  );
  // Define code window as Boot ROM [0 .. ROM_BYTES-1]
  code_guard #(.CODE0_BASE(32'h0000_0000), .CODE0_LIMIT(ROM_BYTES-1)) u_code_guard (
    .req_valid(d_req_arb),
    .req_write(d_we_arb),
    .req_addr (d_addr_arb),
    .lock_i(smpuctl_lock),
    .wp_q(code_wp_q),
    .update_en(code_update_en_q),
    .allow_write(allow_code_write)
  );

  
  // Boot policy FSM
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      boot_phase_q     <= BP_SIGWAIT;
      boot_wp_pulse    <= 1'b0;
      boot_cache_wr    <= 1'b0;
      boot_lock_pulse  <= 1'b0;
      boot_cache_wdata <= 32'h0;
    end else begin
      // defaults
      boot_wp_pulse    <= 1'b0;
      boot_cache_wr    <= 1'b0;
      boot_lock_pulse  <= 1'b0;
      case (boot_phase_q)
      BP_SIGWAIT: begin
        boot_wp_pulse   = 1'b0;
        boot_cache_wr   = 1'b0;
        boot_lock_pulse = 1'b0;
        if (boot_sig_ok) begin
          boot_phase_q <= BP_WP;
        end
      end
        BP_WP: begin
          // set code write-protect latch
          boot_wp_pulse <= 1'b1;
          boot_phase_q  <= BP_FLUSH;
        end
        BP_FLUSH: begin
          // force both I$ and D$ flush once
          boot_cache_wr    <= 1'b1;
          boot_cache_wdata <= (32'h1 << 7) | (32'h1 << 6); // DC_FLUSH | IC_FLUSH
          boot_phase_q     <= BP_LOCK;
        end
        BP_LOCK: begin
          // finally set global LOCK
          boot_lock_pulse <= 1'b1;
          boot_phase_q    <= BP_DONE;
        end
        default: begin end
      endcase
    end
  end
// MMIO decode (D-side)
  assign cache_mmio_hit = d_req_arb && (d_addr_arb == CACHE_CTRL_ADDR);
  assign code_mmio_hit  = d_req_arb && (d_addr_arb == CODE_CTRL_ADDR);
  assign mmio_wr        = d_we_arb;
  assign mmio_wdata     = d_wdata_arb;

  
  assign sig_mmio_hit  = d_req_arb && (d_addr_arb == SIGCHECK_ADDR);
// DMA firewall
// Parameters: ROM window = 16 KiB (boot ROM). No privileged regions by default.
logic        dma_fw_req;
logic        dma_fw_we;
logic [3:0]  dma_fw_be;
logic [31:0] dma_fw_addr;
logic [31:0] dma_fw_wdata;


  // DMA Firewall config via MMIO (write disabled after LOCK)
  wire cfg_access = dmafw_mmio_hit;
  wire cfg_write  = cfg_access & mmio_wr & ~smpuctl_lock;
  wire cfg_read   = cfg_access & ~mmio_wr;

  // Tie firewall cfg ports
  // Note: addr[3:0] used to select simple regs per harvos_dma_firewall spec

harvos_dma_firewall u_dma_fw (
  .clk   (clk),
  .rst_n (rst_n),
  // cfg tied-off (can be MMIO-mapped later)
  .cfg_en(cfg_access), .cfg_we(cfg_write), .cfg_addr(d_addr_arb[3:0]), .cfg_wdata(mmio_wdata), .cfg_be(mmio_be), .cfg_rdata(dmafw_mmio_rdata),
  .dma   (dma_mux),

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
  end else if (dc_m_req) begin
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

  
  // Feed D-Cache MEM-side return
  assign dc_m_rdata  = m_rdata;
  assign dc_m_rvalid = m_rvalid & (owner_q==OWN_D);
  assign dc_m_fault  = m_fault  & (owner_q==OWN_D);
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
      if (cache_mmio_hit) begin
        dmem.done  <= 1'b1;
        dmem.rdata <= cache_mmio_rdata;
        dmem.fault <= 1'b0;
      end else if (code_mmio_hit) begin
        dmem.done  <= 1'b1;
        dmem.rdata <= code_mmio_rdata;
        dmem.fault <= 1'b0;
      end else if (dmafw_mmio_hit) begin
        dmem.done  <= 1'b1;
        dmem.rdata <= dmafw_mmio_rdata;
        dmem.fault <= 1'b0;
      end else if (sig_mmio_hit) begin
        dmem.done  <= 1'b1;
        dmem.rdata <= sig_mmio_rdata;
        dmem.fault <= 1'b0;
      end else begin
        dmem.done  <= dcache_cpu_done;
        if (dcache_cpu_done && !d_we_arb) begin
          dmem.rdata <= dcache_cpu_rdata;
        end
        dmem.fault <= dcache_cpu_fault;
      end
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
  assign imem_cache.rdata  = ic_m_rdata;
  assign imem_cache.rvalid = ic_m_rvalid;
  assign imem_cache.fault  = ic_m_fault;

  assign ic_m_rdata  = rom_sel ? rom_rdata  : i_rdata_arb;
  assign ic_m_rvalid = rom_sel ? rom_rvalid : i_rvalid_arb;
  assign ic_m_fault  = rom_sel ? rom_fault  : i_fault_arb;

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
