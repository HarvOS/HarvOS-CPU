// -----------------------------------------------------------------------------
// csr_file.sv — Patched to match harvos_core port map and Whitepaper CSR map
// - Ports aligned with harvos_core u_csr instantiation
// - CSR addresses sourced from harvos_pkg_flat.svh (SSTATUS..SCAPS)
// - Read-as-zero / write-ignored masks for RO/RSV bits (basic)
// NOTE: SystemVerilog-2005 compatible style (no always_ff / interfaces).
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

`include "harvos_pkg_flat.svh"
`include "harvos_pkg.svh"

module csr_file #(
  parameter int unsigned XLEN = 32
) (
  input  logic                   clk,
  input  logic                   rst_n,

  // privilege / return
  input  priv_e                  cur_priv,
  input  logic                   do_sret,
  input  logic                   do_mret,
  input  priv_e                  next_priv,

  // CSR access (decoded in core)
  input  logic                   csr_en,
  input  logic [2:0]             csr_funct3,    // 001=CSRRW, 010=CSRRS, 011=CSRRC, 101..111 immediate (treated same here)
  input  logic [11:0]            csr_addr,
  input  logic [XLEN-1:0]        csr_wval,
  output logic [XLEN-1:0]        csr_rval,
  output logic                   csr_illegal,

  // entropy source (for SRANDOM)
  input  logic                   entropy_valid,
  input  logic [XLEN-1:0]        entropy_data,

  // trap hookup
  input  logic                   trap_set,
  input  logic                   trap_is_irq,
  input  logic [XLEN-1:0]        trap_scause,
  input  logic [XLEN-1:0]        trap_sepc,
  input  logic [XLEN-1:0]        trap_stval,
  input  logic [XLEN-1:0]        cur_pc,          // for sepc_to_write default
  output logic [XLEN-1:0]        trap_target_pc,  // stvec target
  output logic [XLEN-1:0]        sepc_to_write,   // usually cur_pc

  // timer
  input  logic [XLEN-1:0]        time_value,

  // external sticky lock-set (from SoC boot)
  input  logic                   lock_set_i,

  // exposed CSR state (q)
  output logic [XLEN-1:0]        csr_sstatus_q,
  output logic [XLEN-1:0]        csr_stvec_q,
  output logic [XLEN-1:0]        csr_sepc_q,
  output logic [XLEN-1:0]        csr_scause_q,
  output logic [XLEN-1:0]        csr_stval_q,
  output logic [XLEN-1:0]        csr_satp_q,
  output logic [XLEN-1:0]        csr_sie_q,
  output logic [XLEN-1:0]        csr_sip_q,
  output logic [XLEN-1:0]        csr_smpuctl_q,
  output logic [XLEN-1:0]        csr_mepc_q,
  output logic [XLEN-1:0]        csr_mstatus_q
);

  // -----------------------------
  wire [XLEN-1:0] wval = csr_wval;
  // Local constants / masks
// -----------------------------
// CSR privilege and access helpers

  // Simplified privilege/RO helpers (no SV functions for SV-2005 frontends)
  wire csr_is_mclass = (csr_addr[11:8] == 4'h3);
  wire csr_is_sclass = (csr_addr[11:8] == 4'h1) || (csr_addr == CSR_STIME) || (csr_addr == CSR_STIMECMP);
  wire priv_ok_w     = csr_is_mclass ? (cur_priv == PRIV_M)
                        : csr_is_sclass ? ((cur_priv == PRIV_S) || (cur_priv == PRIV_M))
                        : 1'b0;
  wire csr_is_ro     = (csr_addr == CSR_SCAPS) || (csr_addr == CSR_STIME) || (csr_addr == CSR_SRANDOM);
// -----------------------------
// Address class helpers (based on CSR encoding)



// Recognize a write-attempt (CSRRW always writes; CSRRS/CSRRC write when wval!=0)
wire csr_is_write_attempt = csr_en && (csr_funct3[1:0] != 2'b00) &&
                            ( (csr_funct3[1:0]==2'b01) || (wval != {XLEN{1'b0}}) );

wire csr_is_read_attempt  = csr_en && (csr_funct3[1:0] != 2'b00); // reads also occur for RS/RC/RW

// Illegal access flags
wire csr_illegal_priv  = csr_en && !priv_ok_w;
wire csr_illegal_write = csr_is_write_attempt && ( csr_is_ro || csr_illegal_priv );

  // -----------------------------
  // wval defined above
  // sstatus writable bits (subset: SIE, SPIE, SPP, SUM, MXR)
  localparam logic [XLEN-1:0] SSTATUS_WMASK = (32'h1 << 1) | (32'h1 << 5) | (32'h1 << 8) | (32'h1 << 18) | (32'h1 << 19);
  // sip/sie writable masks (supervisor bits only: SSIE=1, STIE=5, SEIE=9 in RISC-V)
  localparam logic [XLEN-1:0] SIE_WMASK  = (32'h1 << 1) | (32'h1 << 5) | (32'h1 << 9);
  localparam logic [XLEN-1:0] SIP_WMASK  = (32'h1 << 1) | (32'h1 << 5) | (32'h1 << 9);

  // -----------------------------
  // CSR attribute helpers (privilege / known / read-only)
  // -----------------------------
  // Classify CSR by top nibble: 0x1?? = Supervisor, 0x3?? = Machine
  wire csr_is_sclass = (csr_addr[11:8] == 4'h1);
  wire csr_is_mclass = (csr_addr[11:8] == 4'h3);

  // Known-CSR and Read-Only flags
  reg csr_is_known;
  reg csr_is_ro;
  always @* begin
    csr_is_known = 1'b0;
    csr_is_ro    = 1'b0;
    case (csr_addr)
      CSR_SSTATUS, CSR_STVEC, CSR_SEPC, CSR_SCAUSE, CSR_STVAL, CSR_SATP,
      CSR_SIE, CSR_SIP, CSR_SMPUCTL, CSR_MEPC, CSR_MSTATUS,
      CSR_STIME, CSR_STIMECMP, CSR_SRANDOM, CSR_SCAPS: csr_is_known = 1'b1;
      default: csr_is_known = 1'b0;
    endcase
    case (csr_addr)
      CSR_STIME, CSR_SRANDOM, CSR_SCAPS: csr_is_ro = 1'b1;
      default: csr_is_ro = 1'b0;
    endcase
  end

  // Privilege: S-class requires S/M (not U); M-class requires M
  wire priv_ok = (csr_is_sclass ? (cur_priv != PRIV_U) : (csr_is_mclass ? (cur_priv == PRIV_M) : 1'b1));

  // Write-effect detection (CSRRW always writes; CSRRS/CSRRC write iff wval!=0)
  wire csr_write_effect = (csr_funct3[1:0]==2'b01) ? 1'b1 :
                          ((csr_funct3[1:0]==2'b10) || (csr_funct3[1:0]==2'b11)) ? (wval != 32'h0) : 1'b0;

  wire priv_violation = csr_en && !priv_ok;
  wire ro_violation   = csr_en && csr_write_effect && csr_is_ro;


  // smpuctl: bit0=LOCK sticky-on; others free for implementation
  localparam logic [XLEN-1:0] SMPUCTL_LOCK_BIT = 32'h1;

  // satp MODE enforcement (RV32: MODE bit is [31], 1 = Sv32, 0 = Bare)
  localparam int SATP_MODE_BIT = 31;
  localparam logic [XLEN-1:0] SATP_MODE_MASK = (32'h1 << SATP_MODE_BIT);

// Flag a write-attempt that tries to set satp.MODE=BARE (forbidden)
wire satp_bare_attempt = csr_is_write_attempt && (csr_addr==CSR_SATP) && (csr_wval[SATP_MODE_BIT]==1'b0);


  // scaps: build from harvos_pkg.svh bit indices if present
  // scaps: build from harvos_pkg.svh bit indices if present
  // expects SCAPS_*_BIT names from harvos_pkg.svh
  localparam logic [XLEN-1:0] SCAPS_CONST =
      (32'h1 << SCAPS_WX_ENFORCED_BIT)
    | (32'h1 << SCAPS_NX_D_BIT)
    | (32'h1 << SCAPS_PAGING_ALWAYS_BIT)
    | (32'h1 << SCAPS_DMA_FW_BIT)
    | (32'h1 << SCAPS_SV32_BIT)
    | (32'h1 << SCAPS_HARVARD_BIT)
    | (32'h1 << SCAPS_FENCEI_BIT);
  wire [XLEN-1:0] scaps_q = SCAPS_CONST;

  // STIMECMP register (optional; RO/RW depending on integration)
  logic [XLEN-1:0] stimecmp_q;

  // -----------------------------
  // Sequential CSRs
  // -----------------------------
  // Reset values: conservative defaults
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      csr_sstatus_q <= '0;
      csr_stvec_q   <= '0;
      csr_sepc_q    <= '0;
      csr_scause_q  <= '0;
      csr_stval_q   <= '0;
      csr_satp_q    <= SATP_MODE_MASK; // MODE=Sv32 on reset
      csr_sie_q     <= '0;
      csr_sip_q     <= '0;
      csr_smpuctl_q <= '0;
      csr_mepc_q    <= '0;
      csr_mstatus_q <= '0;
      stimecmp_q    <= '0;
    end else begin
      // Trap write side-effects
      if (trap_set) begin
        csr_scause_q <= trap_scause;
        csr_sepc_q   <= trap_sepc;
        csr_stval_q  <= trap_stval;
      end

      // CSR write operations
      if (csr_en) begin
        if (csr_illegal_write) ; else begin
        // Immediate variants not differentiated here
        case (csr_funct3[1:0]) // 2 LSBs matter for RW/RS/RC
          2'b01: begin // CSRRW
            case (csr_addr)
              CSR_SSTATUS: csr_sstatus_q <= (wval & SSTATUS_WMASK) | (csr_sstatus_q & ~SSTATUS_WMASK);
              CSR_STVEC  : csr_stvec_q   <= (wval & ~32'h3); // force 4-byte alignment
              CSR_SEPC   : csr_sepc_q    <= wval;
              CSR_STVAL  : csr_stval_q   <= wval;
              // HarvOS: enforce MODE=Sv32 on write
              CSR_SATP   : csr_satp_q    <= (wval | SATP_MODE_MASK);
              CSR_SIE    : csr_sie_q     <= (wval & SIE_WMASK) | (csr_sie_q & ~SIE_WMASK);
              CSR_SIP    : csr_sip_q     <= (wval & SIP_WMASK) | (csr_sip_q & ~SIP_WMASK);
              CSR_SMPUCTL: csr_smpuctl_q <= ((wval & ~SMPUCTL_LOCK_BIT) | ((csr_smpuctl_q | wval | { {XLEN-1{1'b0}}, lock_set_i}) & SMPUCTL_LOCK_BIT)); // LOCK sticky incl. external set
              CSR_MEPC   : csr_mepc_q    <= wval;
              CSR_MSTATUS: csr_mstatus_q <= wval;
              CSR_STIMECMP: stimecmp_q   <= wval;
              default: /* RO or unknown → ignore */ ;
            endcase
          end
          2'b10: begin // CSRRS (set bits)
            case (csr_addr)
              CSR_SSTATUS: csr_sstatus_q <= (((csr_sstatus_q | (wval & SSTATUS_WMASK)) & SSTATUS_WMASK) | (csr_sstatus_q & ~SSTATUS_WMASK));
              CSR_SIE    : csr_sie_q     <= (csr_sie_q | (wval & SIE_WMASK)) | (csr_sie_q & ~SIE_WMASK);
              CSR_SIP    : csr_sip_q     <= (csr_sip_q | (wval & SIP_WMASK)) | (csr_sip_q & ~SIP_WMASK);
              default: ;
            endcase
          end
          2'b11: begin // CSRRC (clear bits)
            case (csr_addr)
              CSR_SSTATUS: csr_sstatus_q <= (((csr_sstatus_q & ~(wval & SSTATUS_WMASK)) & SSTATUS_WMASK) | (csr_sstatus_q & ~SSTATUS_WMASK));
              CSR_SIE    : csr_sie_q     <= (csr_sie_q & ~(wval & SIE_WMASK)) | (csr_sie_q & ~SIE_WMASK);
              CSR_SIP    : csr_sip_q     <= (csr_sip_q & ~(wval & SIP_WMASK)) | (csr_sip_q & ~SIP_WMASK);
              default: ;
            endcase
          end
          default: ; // funct3==000 handled outside (SYSTEM non-CSR ops)
        endcase
      end
    end
  end

  end
// Trap target = stvec; sepc_to_write defaults to cur_pc unless overridden
  assign trap_target_pc = csr_stvec_q;
  assign sepc_to_write  = cur_pc;

  // -----------------------------
  // CSR Read mux
  // -----------------------------
  always @* begin
    csr_rval   = '0;
    csr_illegal= 1'b0;
    case (csr_addr)
      CSR_SSTATUS : csr_rval = csr_sstatus_q;
      CSR_STVEC   : csr_rval = csr_stvec_q;
      CSR_SEPC    : csr_rval = csr_sepc_q;
      CSR_SCAUSE  : csr_rval = csr_scause_q;
      CSR_STVAL   : csr_rval = csr_stval_q;
      CSR_SATP    : csr_rval = csr_satp_q;
      CSR_SIE     : csr_rval = csr_sie_q;
      CSR_SIP     : csr_rval = csr_sip_q;
      CSR_SMPUCTL : csr_rval = csr_smpuctl_q;
      CSR_MEPC    : csr_rval = csr_mepc_q;
      CSR_MSTATUS : csr_rval = csr_mstatus_q;
      CSR_STIME   : csr_rval = time_value; // read-only
      CSR_STIMECMP: csr_rval = stimecmp_q;
      CSR_SRANDOM : csr_rval = entropy_valid ? entropy_data : '0; // core may trap if invalid
      CSR_SCAPS   : csr_rval = scaps_q;    // read-only
      default     : begin
        csr_rval    = '0;
        csr_illegal = csr_en; // unknown CSR
        if (satp_bare_attempt) csr_illegal = 1'b1; // trap on BARE attempt
      end
    endcase
    // Aggregate illegal: unknown CSR, privilege violation, or RO write-attempt
  end


`ifndef SYNTHESIS
  // Ensure MODE stays asserted (Bare mode forbidden)
  always @* begin
    if (csr_satp_q[SATP_MODE_BIT] == 1'b0) begin
      $error("HarvOS: satp.MODE must be Sv32 (1), but observed 0");
    end
  end
`endif

endmodule