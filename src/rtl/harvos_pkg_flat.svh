`ifndef HARVOS_PKG_FLAT_SVH
`define HARVOS_PKG_FLAT_SVH 1

// --- Security opcode macros (custom-0) ---
`define OPCODE_SEC    7'b0001011
`define FUNCT3_CLRREG 3'b000
`define FUNCT3_CLRMEM 3'b001

// Flattened from harvos_pkg.sv for Yosys (-sv, no UHDM)
// -----------------------------
  // Privilege modes
  // -----------------------------
  typedef enum logic [1:0] {
    PRIV_U = 2'b00,
    PRIV_S = 2'b01,
    PRIV_M = 2'b11   // machine for boot/ROM only
  } priv_e;

  // -----------------------------
  // Trap causes (scause codes) — from whitepaper §5.5
  // Interrupt causes (when scause[31]==1)
  localparam logic [4:0] SCAUSE_INT_SUPERVISOR_SOFT  = 5'd1;
  localparam logic [4:0] SCAUSE_INT_SUPERVISOR_TIMER = 5'd5;
  localparam logic [4:0] SCAUSE_INT_SUPERVISOR_EXT   = 5'd9;
  // -----------------------------
  typedef enum logic [4:0] {
    SCAUSE_INST_ADDR_MISALIGNED = 5'h00,
    SCAUSE_INST_ACCESS_FAULT    = 5'h01, // MPU/MMU
    SCAUSE_ILLEGAL_INSTR        = 5'h02,
    SCAUSE_BREAKPOINT           = 5'h03, // EBREAK
    SCAUSE_LOAD_ADDR_MISALIGNED = 5'h04,
    SCAUSE_LOAD_ACCESS_FAULT    = 5'h05,
    SCAUSE_STORE_ADDR_MISALIGNED= 5'h06,
    SCAUSE_STORE_ACCESS_FAULT   = 5'h07,
    SCAUSE_ECALL_FROM_U         = 5'h08,
    SCAUSE_ECALL_FROM_S         = 5'h09,
    SCAUSE_HARVARD_VIOLATION    = 5'h0A
  } scause_e;

  // -----------------------------
  // CSR addresses — from whitepaper §5.4
  // -----------------------------
  localparam CSR_SSTATUS = 12'h100;
  localparam CSR_STVEC   = 12'h101;
  localparam CSR_SEPC    = 12'h102;
  localparam CSR_SCAUSE  = 12'h103;
  localparam CSR_STVAL   = 12'h104;
  localparam CSR_MSTATUS   = 12'h300;
  localparam CSR_MISA      = 12'h301;
  localparam CSR_MEDELEG   = 12'h302;
  localparam CSR_MIDELEG   = 12'h303;
  localparam CSR_MIE       = 12'h304;
  localparam CSR_MTVEC     = 12'h305;
  localparam CSR_MSCRATCH  = 12'h340;
  localparam CSR_MEPC      = 12'h341;
  localparam CSR_MCAUSE    = 12'h342;
  localparam CSR_MTVAL     = 12'h343;
  localparam CSR_MIP       = 12'h344;
  localparam CSR_SATP    = 12'h105;
  localparam CSR_SIE     = 12'h106;
  localparam CSR_SIP     = 12'h107;
  localparam CSR_STIME   = 12'h180; // custom: 32-bit time
  localparam CSR_STIMECMP= 12'h181; // custom: 32-bit compare
  localparam CSR_SRANDOM = 12'h120;
  localparam CSR_SMPUCTL = 12'h130;
  localparam CSR_SCAPS   = 12'h140;

  // sstatus bits (subset)
  localparam int SSTATUS_SIE = 1;
  localparam int SSTATUS_SUM = 18;
  localparam int SSTATUS_MXR = 19;
  localparam SSTATUS_UIE = 0;
  localparam SSTATUS_SIE = 1;

  // -----------------------------
  // Minimal RV32I-like encodings (placeholder until official Harv32 enc is frozen)
  // -----------------------------
  typedef enum logic [6:0] {
    OPC_LOAD     = 7'b0000011,
    OPC_STORE    = 7'b0100011,
    OPC_OPIMM    = 7'b0010011,
    OPC_OP       = 7'b0110011,
    OPC_BRANCH   = 7'b1100011,
    OPC_JALR     = 7'b1100111,
    OPC_JAL      = 7'b1101111,
    OPC_LUI      = 7'b0110111, // (unused MVP)
    OPC_AUIPC    = 7'b0010111, // (unused MVP)
    OPC_SYSTEM   = 7'b1110011,
    OPC_MISC_MEM = 7'b0001111
  } opcode_e;

  // funct3
  localparam [2:0] F3_BEQ=3'b000, F3_BNE=3'b001, F3_BLT=3'b100, F3_BGE=3'b101;
  localparam [2:0] F3_ADD_SUB=3'b000, F3_SLT=3'b010, F3_XOR=3'b100, F3_OR=3'b110, F3_AND=3'b111;
  localparam [2:0] F3_LW=3'b010, F3_SW=3'b010;
  localparam [2:0] F3_CSRRW=3'b001, F3_CSRRS=3'b010, F3_CSRRC=3'b011;

  // -----------------------------
  // Access types for MPU/MMU checks
  // -----------------------------
  typedef enum logic [1:0] {
    ACC_FETCH = 2'b00,
    ACC_LOAD  = 2'b01,
    ACC_STORE = 2'b10
  } acc_e;

  // -----------------------------
  // Simple PTE bits (sv32-like)
  // -----------------------------
  typedef struct packed {
    logic V, R, W, X, U;  // valid, read, write, exec, user
    logic [26:0] PPN;     // physical page number (27 bits → 4KB pages, 32-bit PA)
  } pte_s;

  // -----------------------------
  // MPU region permission structure
  // -----------------------------
  typedef struct packed {
    logic        valid;
  logic [31:0] base;
  logic [31:0] limit;     // inclusive upper bound
    logic        allow_r;
  logic        allow_w;
  logic        allow_x;
  logic        user_ok;    // if 0 → supervisor only
    logic        is_ispace;  // instruction space (ROM/XIP)
  } mpu_region_s;

`endif // HARVOS_PKG_FLAT_SVH
