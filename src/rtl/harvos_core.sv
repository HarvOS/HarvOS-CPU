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
`include "bus_if.sv"

module harvos_core (
  input  logic clk,
  input  logic rst_n,

  // Harvard buses
  harvos_imem_if.master imem,
  harvos_dmem_if.master dmem,

  // entropy source (optional)
  input  logic        entropy_valid,
  input  logic [31:0] entropy_data,

  // external interrupt (SEIP)
  input  logic        ext_irq,

  // simple MPU programming port (tie off or drive during boot before lock)
  input  logic           mpu_prog_en,
  input  logic [2:0]     mpu_prog_idx,
  input  logic [31:0]    mpu_prog_base,
  input  logic [31:0]    mpu_prog_limit,
  input  logic [2:0]     mpu_prog_perm,  // {x,w,r}
  input  logic           mpu_prog_user_ok,
  input  logic           mpu_prog_is_ispace
);

  // FENCE.I flush signal
  logic icache_flush;
// removed invalid import *;
  // -----------------
  
  // -----------------
  // Minimal trap path (added)
  // -----------------
  // Latches for a pending synchronous trap and its metadata
  logic        trap_pending_q, trap_pending_d;
  logic [4:0]  trap_scause_q,  trap_scause_d;
  logic [31:0] trap_stval_q,   trap_stval_d;

  // Compute when a trap is actually taken (when IF finishes fetching an instruction and we update PC)
  logic trap_take_now;

  // Default vector (until CSR file is wired)
  localparam logic [31:0] CSR_STVEC_RESET = 32'h00000100;

  // Target PC and SEPC bookkeeping (SEPC exported here if CSR gets wired later)
  logic [31:0] trap_target_pc, sepc_to_write;

  
  // Privilege state (U/S/M) — updated via CSR next_priv and traps
  priv_e priv_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) priv_q <= PRIV_S;
    else if (trap_take_now) priv_q <= PRIV_S;
    else                    priv_q <= next_priv;
  end
// Fire-and-latch a trap request from anywhere in the core
  task automatic trap_request(input logic [4:0] scause, input logic [31:0] stval);
    trap_pending_d = 1'b1;
    trap_scause_d  = scause;
    trap_stval_d   = stval;
  endtask


  // Trap target computation (simple: vector to stvec)
  trap_unit u_trap_unit (
    .clk            (clk),
    .rst_n          (rst_n),
    .trap_req       (trap_pending_q),
    .trap_scause    (trap_scause_q),
    .trap_stval     (trap_stval_q),
    .cur_pc         (pc_q),
    .csr_stvec_q(csr_stvec_q),
    .trap_target_pc (trap_target_pc),
    .sepc_to_write  (sepc_to_write)
  );

  // Trap state registers
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      trap_pending_q <= 1'b0;
      trap_scause_q  <= '0;
      trap_stval_q   <= '0;
    end else begin
      // Clear when we redirect PC to trap_target_pc; otherwise capture new pending requests
      if (trap_take_now) begin
        trap_pending_q <= 1'b0;
      end else if (trap_pending_d) begin
        trap_pending_q <= 1'b1;
      end
      if (trap_pending_d) begin
        trap_scause_q <= trap_scause_d;
        trap_stval_q  <= trap_stval_d;
      end
    end
  end

  // Defaults for the single-cycle "set" inputs to the trap flops (+ ECALL/EBREAK)
  always_comb begin
    trap_pending_d = 1'b0;
    trap_scause_d  = trap_scause_q;
    trap_stval_d   = trap_stval_q;
    // ECALL/EBREAK inject synchronous trap
    if (ecall_pulse) begin
      trap_pending_d = 1'b1;
      trap_scause_d  = (priv_q == PRIV_U) ? SCAUSE_ECALL_FROM_U : SCAUSE_ECALL_FROM_S;
      trap_stval_d   = 32'h0;
    end else if (ebreak_pulse) begin
      trap_pending_d = 1'b1;
      trap_scause_d  = SCAUSE_BREAKPOINT;
      trap_stval_d   = 32'h0;
    end
  

    else if (do_entropy_ex && !entropy_valid) begin
      trap_pending_d = 1'b1;
      trap_scause_d  = SCAUSE_ILLEGAL_INSTR;
      trap_stval_d   = if_instr; // per RISC-V, stval holds faulting instruction on illegal instr
    end
  end
// IF/ID/EX/MEM/WB pipeline regs (minimal)
  // -----------------
  logic [31:0] pc_q;
  logic [31:0] if_instr;

  // Register file
  logic        rf_we_wb;
  logic [4:0]  rf_waddr_wb;
  logic [31:0] rf_wdata_wb;
  logic [31:0] rf_rdata1_id, rf_rdata2_id;
  logic [4:0]  rs1_id, rs2_id;

  regfile RF (
    .clk(clk), .rst_n(rst_n),
    .we(rf_we_wb), .waddr(rf_waddr_wb), .wdata(rf_wdata_wb),
    .raddr1(rs1_id), .raddr2(rs2_id), .rdata1(rf_rdata1_id), .rdata2(rf_rdata2_id)
  );

  // Decoder
  logic [31:0] imm_i, imm_s, imm_b, imm_j;
  opcode_e opcode_id;
  logic [2:0] funct3_id;
  logic [6:0] funct7_id;
  logic [4:0] rd_id;
  decoder DEC (
    .instr(if_instr),
    .valid(),
    .opcode(opcode_id),
    .funct3(funct3_id),
    .funct7(funct7_id),
    .rd(rd_id),
    .rs1(rs1_id),
    .rs2(rs2_id),
    .imm_i(imm_i),
    .imm_s(imm_s),
    .imm_b(imm_b),
    .imm_j(imm_j), .imm_u(imm_u),
    .is_clrreg(dec_is_clrreg),
    .is_clrmem(dec_is_clrmem)
  );

  // Security decodes from decoder
  logic dec_is_clrreg;
  logic dec_is_clrmem;


  // Misalignment detection for loads/stores (byte ok, halfword align 2, word align 4)
  logic lsu_misalign;
  always_comb begin
    lsu_misalign = 1'b0;
    unique case (funct3_id)
      3'b000, 3'b100: lsu_misalign = 1'b0;                    // LB/LBU/SB always okay
      3'b001, 3'b101: lsu_misalign = alu_y_ex[0];             // LH/LHU/SH -> addr[0]==0
      3'b010, 3'b110: lsu_misalign = |alu_y_ex[1:0];          // LW/SW -> addr[1:0]==0
      default:        lsu_misalign = 1'b0;
    endcase
  end


  
  // FENCE.I decode -> I$ flush pulse
  wire fencei_flush_pulse;
  fence_i_decode FENCEI (
    .clk(clk), .rst_n(rst_n),
    .opcode(opcode_id),
    .funct3(funct3_id),
    .cur_priv(priv_q),
    .fencei_flush_pulse(fencei_flush_pulse)
  );
  
  // SFENCE.VMA decode -> MMU/TLB flush controls
  wire        sfence_flush_all_w, sfence_addr_valid_w, sfence_asid_valid_w;
  wire [31:0] sfence_vaddr_w;
  wire [8:0]  sfence_asid_w;
  sfence_vma_decode SFENCEVMA (
    .clk(clk), .rst_n(rst_n),
    .opcode(opcode_id), .funct3(funct3_id), .funct7(funct7_id),
    .rs1(rs1_id), .rs2(rs2_id),
    .rs1_val(rf_rdata1_id), .rs2_val(rf_rdata2_id),
    .cur_priv(priv_q),
    .sfence_flush_all(sfence_flush_all_w),
    .sfence_addr_valid(sfence_addr_valid_w),
    .sfence_vaddr(sfence_vaddr_w),
    .sfence_asid_valid(sfence_asid_valid_w),
    .sfence_asid(sfence_asid_w)
  );

  // --- CSR decode & file (whitepaper compliance) ---
  // CSR op detection (register variants only)
  wire csr_en_w = (opcode_id == OPC_SYSTEM) &&
                  ((funct3_id == F3_CSRRW) || (funct3_id == F3_CSRRS) || (funct3_id == F3_CSRRC));
  wire [11:0] csr_addr_w = imm_i[11:0];
  wire [31:0] csr_wval_w = rf_rdata1_id;
  // ENTROPY read = CSR read of SRANDOM; trap if source unavailable
  wire do_entropy_ex = csr_en_w && (csr_addr_w == CSR_SRANDOM);


  // SRET/MRET decodes
  wire sret_pulse, mret_pulse;
  sret_decode SRET_D (.clk(clk), .rst_n(rst_n), .opcode(opcode_id), .funct3(funct3_id), .imm_i(imm_i), .cur_priv(priv_q), .sret_pulse(sret_pulse));
  mret_decode MRET_D (.clk(clk), .rst_n(rst_n), .opcode(opcode_id), .funct3(funct3_id), .imm_i(imm_i), .cur_priv(priv_q), .mret_pulse(mret_pulse));


  // ECALL/EBREAK decode (priv traps)
  wire ecall_pulse  = (opcode_id == OPC_SYSTEM) && (funct3_id == 3'b000) && (imm_i[11:0] == 12'h000);
  wire ebreak_pulse = (opcode_id == OPC_SYSTEM) && (funct3_id == 3'b000) && (imm_i[11:0] == 12'h001);
  // CSR instance, hooked to satp/sstatus/smpuctl and trap CSRs
  logic [31:0] csr_sstatus_q, csr_stvec_q, csr_sepc_q, csr_scause_q, csr_stval_q;
  logic [31:0] csr_satp_q, csr_sie_q, csr_sip_q, csr_smpuctl_q, csr_mepc_q, csr_mstatus_q;
  priv_e       next_priv;

  logic [31:0] csr_rval_dummy; logic csr_illegal_dummy;
  csr_file u_csr (
    .clk(clk), .rst_n(rst_n),
    .cur_priv      (priv_q),
    .do_sret       (sret_pulse),
    .do_mret       (mret_pulse),
    .next_priv     (next_priv),
    .csr_en        (csr_en_w),
    .csr_funct3    (funct3_id),
    .csr_addr      (csr_addr_w),
    .csr_wval      (csr_wval_w),
    .csr_rval      (csr_rval_dummy),
    .csr_illegal   (csr_illegal_dummy),
    .entropy_valid (entropy_valid),
    .entropy_data  (entropy_data),
    // trap hookup
    .trap_set      (trap_take_now),
    .trap_is_irq   (1'b0),
    .trap_scause   (trap_scause_q),
    .trap_sepc     (sepc_to_write),
    .trap_stval    (trap_stval_q),
    // timer
    .time_value    (32'h0),
    // outputs
    .csr_sstatus_q (csr_sstatus_q),
    .csr_stvec_q   (csr_stvec_q),
    .csr_sepc_q    (csr_sepc_q),
    .csr_scause_q  (csr_scause_q),
    .csr_stval_q   (csr_stval_q),
    .csr_satp_q    (csr_satp_q),
    .csr_sie_q     (csr_sie_q),
    .csr_sip_q     (csr_sip_q),
    .csr_smpuctl_q (csr_smpuctl_q),
    .csr_mepc_q    (csr_mepc_q),
    .csr_mstatus_q (csr_mstatus_q)
  );
assign icache_flush = fencei_flush_pulse;
// Privilege & core init
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      priv_q <= 2'd3;
      core_dmem_req   <= 1'b0; // deprecated
      core_dmem_we    <= 1'b0;
      core_dmem_be    <= 4'b0000;
      core_dmem_addr  <= 32'h0;
      core_dmem_wdata <= 32'h0;
      // initialize LSU
      lsu_q <= LSU_IDLE;
      clr_addr_q <= 32'h0;
      clr_len_q  <= 32'h0;
      ld_pending_q    <= 1'b0;
      ld_pending_rd_q <= 5'd0;
      // defaults
      dc_cpu_req   <= 1'b0;
      dc_cpu_we    <= 1'b0;
      dc_cpu_be    <= 4'h0;
      dc_cpu_addr  <= 32'h0;
      dc_cpu_wdata <= 32'h0;
  end
  end

// Simple 1-entry ALU->store bypass (previous cycle writeback)
  logic last_wb_valid;
  logic [4:0] last_wb_rd;
  logic [31:0] last_wb_data;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      last_wb_valid <= 1'b0;
      last_wb_rd    <= 5'd0;
      last_wb_data  <= 32'h0;
    end else begin
      last_wb_valid <= rf_we_wb;
      last_wb_rd    <= rf_waddr_wb;
      last_wb_data  <= rf_wdata_wb;
    end
  end

  // WB path

  // FENCE.I pulse generation
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) icache_flush <= 1'b0;
    else begin
      icache_flush <= (opcode_id == OPC_FENCE) && (funct3_id == 3'b001);
    end
  end

  assign rf_we_wb = (dec_is_clrreg) || (rd_id != 5'd0) &&
                        (opcode_id == OPC_OP || opcode_id == OPC_OPIMM ||
                         opcode_id == OPC_JAL || opcode_id == OPC_JALR || opcode_id == OPC_LOAD ||
                         (opcode_id == OPC_SYSTEM && (funct3_id != 3'b000)) ||
                         do_entropy_ex);
  assign rf_waddr_wb  = rd_id;
  assign rf_wdata_wb  = (dec_is_clrreg ? 32'h0 : ((opcode_id == OPC_JAL)  ? pc_q :
                        (opcode_id == OPC_JALR) ? pc_q :
                        (opcode_id == OPC_LOAD) ? (dc_cpu_done ? (
                          (ls_size_ex==LS_W) ? dc_cpu_rdata :
                          (ls_size_ex==LS_H) ? (ls_unsigned_ex ?
                            {16'h0, (dtr_paddr[1] ? dc_cpu_rdata[31:16] : dc_cpu_rdata[15:0])} :
                            {{16{(dtr_paddr[1] ? dc_cpu_rdata[31] : dc_cpu_rdata[15])}},
                              (dtr_paddr[1] ? dc_cpu_rdata[31:16] : dc_cpu_rdata[15:0])}) :
                          /* LS_B */ (ls_unsigned_ex ?
                            {24'h0, (dtr_paddr[1:0]==2'd3 ? dc_cpu_rdata[31:24] :
                                     dtr_paddr[1:0]==2'd2 ? dc_cpu_rdata[23:16] :
                                     dtr_paddr[1:0]==2'd1 ? dc_cpu_rdata[15:8]  :
                                                            dc_cpu_rdata[7:0])} :
                            {{24{(dtr_paddr[1:0]==2'd3 ? dc_cpu_rdata[31] :
                                  dtr_paddr[1:0]==2'd2 ? dc_cpu_rdata[23] :
                                  dtr_paddr[1:0]==2'd1 ? dc_cpu_rdata[15] :
                                                         dc_cpu_rdata[7])}},
                              (dtr_paddr[1:0]==2'd3 ? dc_cpu_rdata[31:24] :
                               dtr_paddr[1:0]==2'd2 ? dc_cpu_rdata[23:16] :
                               dtr_paddr[1:0]==2'd1 ? dc_cpu_rdata[15:8]  :
                                                      dc_cpu_rdata[7:0])})
                        ) : rf_wdata_wb) :
                        (opcode_id == OPC_SYSTEM && (funct3_id != 3'b000)) ? csr_rval_ex :
                        (do_entropy_ex ? (entropy_valid ? entropy_data : 32'h0) : alu_y_ex)));
// Branch/jump targets
  logic [31:0] branch_target = pc_q + imm_b;
  logic [31:0] jal_target    = pc_q + imm_j;
  logic [31:0] jalr_target   = (rf_rdata1_id + imm_i) & 32'hFFFF_FFFE;

  
  // ---- CLRMEM support: drive MMU D-side vaddr from CLR FSM when active ----
logic        clr_active;
logic [31:0] dtr_vaddr;
assign dtr_vaddr = clr_active ? clr_addr_q : alu_y_ex;
// --- MMU: sv32 instance (auto-wired) ---
  // CSR wires
  logic [31:0] csr_satp_q, csr_sstatus_q, csr_smpuctl_q;
  // SFENCE.VMA flush (no decode wired yet: default 0)
  logic        sfence_flush_all, sfence_addr_valid, sfence_asid_valid;
  logic [31:0] sfence_vaddr;
  logic [8:0]  sfence_asid;
  // If not present, declare translation handshake wires
  // (Note: many of these likely already exist in this file. If so, synthesis will ignore duplicate logic where unconnected)
  // logic if_req, if_ready, if_fault, if_perm_x;
  // logic [31:0] if_paddr;
  // logic dtr_req; acc_e dtr_acc; logic dtr_ready, dtr_fault, dtr_perm_r, dtr_perm_w, dtr_perm_x; logic [31:0] dtr_paddr;

  
  // --- MMU: sv32 instance (auto-wired) ---
  // CSR wires
  logic [31:0] csr_satp_q, csr_sstatus_q, csr_smpuctl_q;
  // SFENCE.VMA flush (no decode wired yet: default 0)
  logic        sfence_flush_all, sfence_addr_valid, sfence_asid_valid;
  logic [31:0] sfence_vaddr;
  logic [8:0]  sfence_asid;
  assign sfence_flush_all = sfence_flush_all_w;
  assign sfence_addr_valid = sfence_addr_valid_w;
  assign sfence_asid_valid = sfence_asid_valid_w;
  assign sfence_vaddr = sfence_vaddr_w;
  assign sfence_asid = sfence_asid_w;

  // --- MPU instances: fetch and data ---
  mpu_region_s mpu_prog_region;
  always_comb begin
    mpu_prog_region.valid     = mpu_prog_en;
    mpu_prog_region.base      = mpu_prog_base;
    mpu_prog_region.limit     = mpu_prog_limit;
    mpu_prog_region.allow_r   = mpu_prog_perm[0];
    mpu_prog_region.allow_w   = mpu_prog_perm[1];
    mpu_prog_region.allow_x   = mpu_prog_perm[2];
    mpu_prog_region.user_ok   = mpu_prog_user_ok;
    mpu_prog_region.is_ispace = mpu_prog_is_ispace;
  end

  logic mpu_allow_if, mpu_is_ispace_if;
  mpu #(.NREG(8)) u_mpu_if (
    .clk(clk), .rst_n(rst_n),
    .smpuctl_q    (csr_smpuctl_q),
    .prog_en      (mpu_prog_en),
    .prog_idx     (mpu_prog_idx),
    .prog_region  (mpu_prog_region),
    .acc_type     (ACC_FETCH),
    .phys_addr    (if_paddr),
    .cur_priv     (priv_q),
    .allow        (mpu_allow_if),
    .is_ispace_region(mpu_is_ispace_if)
  );

  logic mpu_allow_d;
  mpu #(.NREG(8)) u_mpu_d (
    .clk(clk), .rst_n(rst_n),
    .smpuctl_q    (csr_smpuctl_q),
    .prog_en      (mpu_prog_en),
    .prog_idx     (mpu_prog_idx),
    .prog_region  (mpu_prog_region),
    .acc_type     (dtr_acc == ACC_STORE ? ACC_STORE : ACC_LOAD),
    .phys_addr    (dtr_paddr),
    .cur_priv     (priv_q),
    .allow        (mpu_allow_d),
    .is_ispace_region(mpu_is_ispace_if)
  );

  // --- MMU instance (Sv32) ---
  // PTW bus to share with dmem arbiter (declared elsewhere or synth tools will create)
  logic        ptw_req, ptw_rvalid, ptw_fault;
  logic [31:0] ptw_addr, ptw_rdata;

  mmu_sv32 u_mmu (
    .clk(clk), .rst_n(rst_n),
    .csr_satp_q     (csr_satp_q),
    .csr_sstatus_q  (csr_sstatus_q),
    .sfence_flush_all(sfence_flush_all_w),
    .sfence_addr_valid(sfence_addr_valid_w),
    .sfence_vaddr   (sfence_vaddr_w),
    .sfence_asid_valid(sfence_asid_valid_w),
    .sfence_asid    (sfence_asid_w),
    .cur_priv       (priv_q),
    // IF channel
    .if_req         (if_req),
    .if_vaddr       (pc_q),
    .if_ready       (if_ready),
    .if_paddr       (if_paddr),
    .if_perm_x      (if_perm_x),
    .if_fault       (if_fault),
    // D channel
    .d_req          (dtr_req),
    .d_acc          (dtr_acc),
    .d_vaddr        (dtr_vaddr),
    .d_ready        (dtr_ready),
    .d_paddr        (dtr_paddr),
    .d_perm_r       (dtr_perm_r),
    .d_perm_w       (dtr_perm_w),
    .d_perm_x       (dtr_perm_x),
    .d_fault        (dtr_fault),
    // PTW memory
    .ptw_req        (ptw_req),
    .ptw_addr       (ptw_addr),
    .ptw_rdata      (ptw_rdata),
    .ptw_rvalid     (ptw_rvalid),
    .ptw_fault      (ptw_fault)
  );

  // --- MPU (fetch + data) ---
  mpu_region_s mpu_prog_region;
  always_comb begin
    mpu_prog_region.valid     = mpu_prog_en;
    mpu_prog_region.base      = mpu_prog_base;
    mpu_prog_region.limit     = mpu_prog_limit;
    mpu_prog_region.allow_r   = mpu_prog_perm[0];
    mpu_prog_region.allow_w   = mpu_prog_perm[1];
    mpu_prog_region.allow_x   = mpu_prog_perm[2];
    mpu_prog_region.user_ok   = mpu_prog_user_ok;
    mpu_prog_region.is_ispace = mpu_prog_is_ispace;
  end

  logic mpu_allow_if, mpu_allow_d;
  
// Removed duplicate MPU instance

// Removed duplicate MPU instance
// IF FSM with MMU + I$
  // I$ cpu-side handshake
  logic ic_cpu_req, ic_cpu_rvalid, ic_cpu_fault;
  logic [31:0] ic_cpu_rdata;
  // I$ instance (physical addressing)
  icache_lock IC (
    .clk, .rst_n,
    .cpu_req(ic_cpu_req), .cpu_addr(if_paddr), .mpu_exec_allow(mpu_allow_if), .cpu_rdata(ic_cpu_rdata), .cpu_rvalid(ic_cpu_rvalid), .cpu_fault(ic_cpu_fault),
    .mem(imem),
    .lock_we(1'b0), .lock_index('0), .lock_set(1'b0),
    .flush_all(icache_flush),
    .stat_hits(), .stat_misses()
  );
// IF FSM with MMU
  typedef enum logic [1:0] {IF_IDLE, IF_TLB, IF_REQ, IF_WAIT} if_state_e;
  if_state_e if_state_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      core_dmem_req   <= 1'b0; // deprecated
      core_dmem_we    <= 1'b0;
      core_dmem_be    <= 4'b0000;
      core_dmem_addr  <= 32'h0;
      core_dmem_wdata <= 32'h0;
      // initialize lsu
      lsu_q <= LSU_IDLE;
      ld_pending_q <= 1'b0;
      ld_pending_rd_q <= 5'd0;
      dc_cpu_req <= 1'b0; dc_cpu_we <= 1'b0; dc_cpu_be <= 4'h0; dc_cpu_addr <= 32'h0; dc_cpu_wdata <= 32'h0;
    end else begin
      // default
      clr_addr_n <= clr_addr_q;
      clr_len_n  <= clr_len_q;
      dc_cpu_req <= 1'b0;
      lsu_q <= lsu_n;
      clr_addr_q <= clr_addr_n;
      clr_len_q  <= clr_len_n;

      case (lsu_q)
LSU_IDLE: begin
  // --- Start CLRMEM if decoded ---
  if (dec_is_clrmem) begin
    if (priv_q == PRIV_U) begin
      trap_request(SCAUSE_ILLEGAL_INSTR, 32'h0);
      lsu_n = LSU_IDLE;
    end else if (rf_rdata1_id[1:0] != 2'b00) begin
      // addr must be word-aligned
      trap_request(SCAUSE_STORE_ADDR_MISALIGNED, rf_rdata1_id);
      lsu_n = LSU_IDLE;
    end else if (rf_rdata2_id == 32'h0) begin
      // len==0: NOP
      lsu_n = LSU_IDLE;
    end else begin
      clr_addr_n = rf_rdata1_id;
      clr_len_n  = rf_rdata2_id;
      lsu_n = LSU_CLR_TLB;
    end
  end else 

          if (do_load_ex || do_store_ex) begin
            if (lsu_misalign) begin
              trap_request((do_load_ex)?SCAUSE_LOAD_ADDR_MISALIGNED:SCAUSE_STORE_ADDR_MISALIGNED, alu_y_ex);
              lsu_n = LSU_IDLE;
            end else
            if (!dtr_ready) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else lsu_n = LSU_IDLE; // wait for translation
            end else if (dtr_fault) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex);
              lsu_n = LSU_IDLE;
            end else if ((!mpu_allow_d) || ((do_load_ex && !dtr_perm_r) || (do_store_ex && !dtr_perm_w))) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex);
              lsu_n = LSU_IDLE;
            end else if ((do_load_ex && mpu_is_ispace_ld) || (do_store_ex && mpu_is_ispace_st)) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else trap_request(SCAUSE_HARVARD_VIOLATION, dtr_paddr);
              lsu_n = LSU_IDLE;
            end else if ((do_load_ex && !mpu_allow_ld) || (do_store_ex && !mpu_allow_st)) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, dtr_paddr);
              lsu_n = LSU_IDLE;
            end else begin
              // issue to D$
              dc_cpu_req   <= 1'b1;
              dc_cpu_we    <= do_store_ex;
              dc_cpu_be    <= (ls_size_ex==LS_W) ? 4'b1111 : (ls_size_ex==LS_H ? (4'b0011 << dtr_paddr[1]) : (4'b0001 << dtr_paddr[1:0]));
              dc_cpu_addr  <= dtr_paddr & 32'hFFFF_FFFC;
              dc_cpu_wdata <= (last_wb_valid && (last_wb_rd == rs2_id) && (last_wb_rd != 5'd0)) ? last_wb_data : rf_rdata2_id;
              // scoreboard if load
              if (do_load_ex && (rd_id != 5'd0)) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else   ld_pending_q    <= 1'b1;
                ld_pending_rd_q <= rd_id;
              end
              lsu_n = LSU_WAIT;
            end
          end
        end
        LSU_WAIT: begin
          if (dc_cpu_done) begin
            lsu_n = LSU_IDLE;
          end
        end

// --- CLRMEM states ---
LSU_CLR_TLB: begin
  // Request translation for clr_addr_q; reuse dtr_req in comb block by virtue of lsu_q state.
  if (!dtr_ready) begin
    lsu_n = LSU_CLR_TLB; // wait
  end else if (dtr_fault) begin
    trap_request(SCAUSE_STORE_ACCESS_FAULT, clr_addr_q);
    lsu_n = LSU_IDLE;
  end else if (!mpu_allow_d) begin
    trap_request(SCAUSE_STORE_ACCESS_FAULT, clr_addr_q);
    lsu_n = LSU_IDLE;
  end else if (mpu_is_ispace_st || !mpu_allow_st || !dtr_perm_w) begin
    // Enforce Harvard separation and W permission
    if (mpu_is_ispace_st) trap_request(SCAUSE_HARVARD_VIOLATION, dtr_paddr);
    else                  trap_request(SCAUSE_STORE_ACCESS_FAULT, dtr_paddr);
    lsu_n = LSU_IDLE;
  end else begin
    // Issue a 32-bit zero store to current physical address
    dc_cpu_req   <= 1'b1;
    dc_cpu_we    <= 1'b1;
    dc_cpu_be    <= 4'b1111;
    dc_cpu_addr  <= dtr_paddr;
    dc_cpu_wdata <= 32'h0;
    lsu_n = LSU_CLR_WAIT;
  end
end

LSU_CLR_WAIT: begin
  if (dc_cpu_done) begin
    if (dc_cpu_fault) begin
      trap_request(SCAUSE_STORE_ACCESS_FAULT, dtr_paddr);
      lsu_n = LSU_IDLE;
    end else begin
      // advance
      clr_addr_n = clr_addr_q + 32'd4;
      clr_len_n  = clr_len_q  - 32'd1;
      lsu_n = (clr_len_q == 32'd1) ? LSU_IDLE : LSU_CLR_TLB;
    end
  end
end
        default: lsu_n = LSU_IDLE;
      endcase
    end
  end
  // IF FSM (wrapped in its own always_ff)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ic_cpu_req <= 1'b0;
      if_req     <= 1'b0;
      if_state_q <= IF_IDLE;
    end else begin
      case (if_state_q)
        IF_TLB: begin
          if (if_ready) begin
            if_req <= 1'b0;
            if (if_fault || !if_perm_x || !mpu_allow_if) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else if (!mpu_is_ispace_if) trap_request(SCAUSE_HARVARD_VIOLATION, pc_q); else trap_request(SCAUSE_INST_ACCESS_FAULT, pc_q);
              if_state_q <= IF_IDLE;
            end else begin
              ic_cpu_req <= 1'b1; // via I$
              // address to I$ is if_paddr (wired into icache_lock)
              if_state_q <= IF_REQ;
            end
          end
        end
        IF_REQ: begin
          ic_cpu_req <= 1'b0; // one-cycle pulse
          if_state_q <= IF_WAIT;
        end
        IF_WAIT: begin
          if (ic_cpu_rvalid) begin
            if (ic_cpu_fault) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else trap_request(SCAUSE_INST_ACCESS_FAULT, pc_q);
            end else begin
              if_instr <= ic_cpu_rdata;
              if (trap_pending_q) begin pc_q <= trap_target_pc; end else begin pc_q     <= pc_q + 32'd4; end // default advance
            end
            if_state_q <= IF_IDLE;
          end
        end
        default: ; // IF_IDLE and others do nothing here
      endcase
    end
  end


  
  // trap_take_now is true exactly when IF updates PC to the trap vector
  always_comb begin
    trap_take_now = (if_state_q == IF_WAIT) && ic_cpu_rvalid && !ic_cpu_fault && trap_pending_q;
  end
// Data translation request signals
  always_comb begin
    dtr_req = 1'b0;
    dtr_acc = ACC_LOAD;
    if (do_load_ex)  begin dtr_req = 1'b1; dtr_acc = ACC_LOAD; end
    if (do_store_ex) begin dtr_req = 1'b1; dtr_acc = ACC_STORE; end
    if (lsu_q==LSU_CLR_TLB) begin dtr_req = 1'b1; dtr_acc = ACC_STORE; end
  end

  // Core's own D-mem master port (to arbiter)
  logic        dc_cpu_req, dc_cpu_we;
  logic [3:0]  dc_cpu_be;
  logic [31:0] dc_cpu_addr, dc_cpu_wdata, dc_cpu_rdata;
  logic        dc_cpu_rvalid, dc_cpu_fault;

  // --- CLRMEM micro-FSM registers ---
logic [31:0] clr_addr_q, clr_addr_n;
logic [31:0] clr_len_q,  clr_len_n;   // words remaining

// D$ cpu-side wires (line-based, multi-cycle)
  typedef enum logic [2:0] {LSU_IDLE, LSU_ISSUE, LSU_WAIT, LSU_CLR_TLB, LSU_CLR_ISSUE, LSU_CLR_WAIT} lsu_e;
  lsu_e lsu_q, lsu_n;
  assign clr_active = (lsu_q==LSU_CLR_TLB) || (lsu_q==LSU_CLR_ISSUE) || (lsu_q==LSU_CLR_WAIT);
  logic        dc_cpu_req, dc_cpu_we;
  logic [3:0] dc_cpu_be;
  logic [31:0] dc_cpu_addr, dc_cpu_wdata, dc_cpu_rdata;
  logic        dc_cpu_done, dc_cpu_fault;

  // Register scoreboard for pending LOAD (simple 1-entry)
  logic        ld_pending_q;
  logic [4:0]  ld_pending_rd_q;

  // D$ memory-side wires to arbiter m0
  logic        m0_req, m0_we;
  logic [3:0] m0_be;
  logic [31:0] m0_addr, m0_wdata, m0_rdata;
  logic m0_rvalid, m0_fault;

  dcache_2way DC (
    .clk, .rst_n,
    .cpu_req(dc_cpu_req), .cpu_we(dc_cpu_we), .cpu_be(dc_cpu_be), .cpu_addr(dc_cpu_addr), .cpu_wdata(dc_cpu_wdata),
    .cpu_rdata(dc_cpu_rdata), .cpu_done(dc_cpu_done), .cpu_fault(dc_cpu_fault),
    .mem_req(m0_req), .mem_we(m0_we), .mem_be(m0_be), .mem_addr(m0_addr), .mem_wdata(m0_wdata),
    .mem_rdata(m0_rdata), .mem_rvalid(m0_rvalid), .mem_fault(m0_fault),
    .stat_hits(), .stat_misses()
  );

  // Global stall when LSU is busy or when load-use hazard exists
  logic ld_use_hazard = ld_pending_q && ((rs1_id == ld_pending_rd_q) || (rs2_id == ld_pending_rd_q)) && (ld_pending_rd_q != 5'd0);
  logic stall_global  = (lsu_q != LSU_IDLE) || ld_use_hazard;
  
  
  // PTW (Page Table Walker) bus wires (MMU -> Arbiter M1)
  logic        ptw_req;
  logic [31:0] ptw_addr;
  logic [31:0] ptw_rdata;
  logic        ptw_rvalid;
  logic        ptw_fault;
// Arbiter instance
  
  dmem_arbiter DMEM_ARB (
    .clk, .rst_n,
    // m0: core
    .m0_req(m0_req), .m0_we(m0_we), .m0_be(m0_be),
    .m0_addr(m0_addr), .m0_wdata(m0_wdata),
    .m0_rdata(m0_rdata), .m0_rvalid(m0_rvalid), .m0_fault(m0_fault),
    // m1: PTW
    .m1_req(ptw_req), .m1_addr(ptw_addr), .m1_rdata(ptw_rdata), .m1_rvalid(ptw_rvalid), .m1_fault(ptw_fault),
    // external
    .dmem(dmem)
  );

  // MEM stage with MMU/MPU checks
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      core_dmem_req   <= 1'b0; // deprecated
      core_dmem_we    <= 1'b0;
      core_dmem_be    <= 4'b0000;
      core_dmem_addr  <= 32'h0;
      core_dmem_wdata <= 32'h0;
      // initialize lsu
      lsu_q <= LSU_IDLE;
      ld_pending_q <= 1'b0;
      ld_pending_rd_q <= 5'd0;
      dc_cpu_req <= 1'b0; dc_cpu_we <= 1'b0; dc_cpu_be <= 4'h0; dc_cpu_addr <= 32'h0; dc_cpu_wdata <= 32'h0;
    end else begin
      // default
      dc_cpu_req <= 1'b0;
      lsu_q <= lsu_n;

      case (lsu_q)
        LSU_IDLE: begin
          if (do_load_ex || do_store_ex) begin
            if (lsu_misalign) begin
              trap_request((do_load_ex)?SCAUSE_LOAD_ADDR_MISALIGNED:SCAUSE_STORE_ADDR_MISALIGNED, alu_y_ex);
              lsu_n = LSU_IDLE;
            end else
            if (!dtr_ready) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else lsu_n = LSU_IDLE; // wait for translation
            end else if (dtr_fault) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex);
              lsu_n = LSU_IDLE;
            end else if ((!mpu_allow_d) || ((do_load_ex && !dtr_perm_r) || (do_store_ex && !dtr_perm_w))) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex);
              lsu_n = LSU_IDLE;
            end else if ((do_load_ex && mpu_is_ispace_ld) || (do_store_ex && mpu_is_ispace_st)) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else trap_request(SCAUSE_HARVARD_VIOLATION, dtr_paddr);
              lsu_n = LSU_IDLE;
            end else if ((do_load_ex && !mpu_allow_ld) || (do_store_ex && !mpu_allow_st)) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, dtr_paddr);
              lsu_n = LSU_IDLE;
            end else begin
              // issue to D$
              dc_cpu_req   <= 1'b1;
              dc_cpu_we    <= do_store_ex;
              dc_cpu_be    <= (ls_size_ex==LS_W) ? 4'b1111 : (ls_size_ex==LS_H ? (4'b0011 << dtr_paddr[1]) : (4'b0001 << dtr_paddr[1:0]));
              dc_cpu_addr  <= dtr_paddr & 32'hFFFF_FFFC;
              dc_cpu_wdata <= (last_wb_valid && (last_wb_rd == rs2_id) && (last_wb_rd != 5'd0)) ? last_wb_data : rf_rdata2_id;
              // scoreboard if load
              if (do_load_ex && (rd_id != 5'd0)) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else   ld_pending_q    <= 1'b1;
                ld_pending_rd_q <= rd_id;
              end
              lsu_n = LSU_WAIT;
            end
          end
        end
        LSU_WAIT: begin
          if (dc_cpu_done) begin
            lsu_n = LSU_IDLE;
          end
        end
        default: lsu_n = LSU_IDLE;
      endcase
  end
end
  // Control flow & traps
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      core_dmem_req   <= 1'b0; // deprecated
      core_dmem_we    <= 1'b0;
      core_dmem_be    <= 4'b0000;
      core_dmem_addr  <= 32'h0;
      core_dmem_wdata <= 32'h0;
      // initialize lsu
      lsu_q <= LSU_IDLE;
      ld_pending_q <= 1'b0;
      ld_pending_rd_q <= 5'd0;
      dc_cpu_req <= 1'b0; dc_cpu_we <= 1'b0; dc_cpu_be <= 4'h0; dc_cpu_addr <= 32'h0; dc_cpu_wdata <= 32'h0;
    end else begin
      // default
      dc_cpu_req <= 1'b0;
      lsu_q <= lsu_n;

      case (lsu_q)
        LSU_IDLE: begin
          if (do_load_ex || do_store_ex) begin
            if (lsu_misalign) begin
              trap_request((do_load_ex)?SCAUSE_LOAD_ADDR_MISALIGNED:SCAUSE_STORE_ADDR_MISALIGNED, alu_y_ex);
              lsu_n = LSU_IDLE;
            end else
            if (!dtr_ready) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else lsu_n = LSU_IDLE; // wait for translation
            end else if (dtr_fault) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex);
              lsu_n = LSU_IDLE;
            end else if ((!mpu_allow_d) || ((do_load_ex && !dtr_perm_r) || (do_store_ex && !dtr_perm_w))) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex);
              lsu_n = LSU_IDLE;
            end else if ((do_load_ex && mpu_is_ispace_ld) || (do_store_ex && mpu_is_ispace_st)) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else trap_request(SCAUSE_HARVARD_VIOLATION, dtr_paddr);
              lsu_n = LSU_IDLE;
            end else if ((do_load_ex && !mpu_allow_ld) || (do_store_ex && !mpu_allow_st)) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, dtr_paddr);
              lsu_n = LSU_IDLE;
            end else begin
              // issue to D$
              dc_cpu_req   <= 1'b1;
              dc_cpu_we    <= do_store_ex;
              dc_cpu_be    <= (ls_size_ex==LS_W) ? 4'b1111 : (ls_size_ex==LS_H ? (4'b0011 << dtr_paddr[1]) : (4'b0001 << dtr_paddr[1:0]));
              dc_cpu_addr  <= dtr_paddr & 32'hFFFF_FFFC;
              dc_cpu_wdata <= (last_wb_valid && (last_wb_rd == rs2_id) && (last_wb_rd != 5'd0)) ? last_wb_data : rf_rdata2_id;
              // scoreboard if load
              if (do_load_ex && (rd_id != 5'd0)) begin
              if (!mpu_allow_d) begin trap_request((do_load_ex)?SCAUSE_LOAD_ACCESS_FAULT:SCAUSE_STORE_ACCESS_FAULT, alu_y_ex); lsu_n = LSU_IDLE; end else   ld_pending_q    <= 1'b1;
                ld_pending_rd_q <= rd_id;
              end
              lsu_n = LSU_WAIT;
            end
          end
        end
        LSU_WAIT: begin
          if (dc_cpu_done) begin
            lsu_n = LSU_IDLE;
          end
        end
        default: lsu_n = LSU_IDLE;
      endcase
    end
  end


  
endmodule
