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

`ifndef MMU_PERM_PKG_SV
`define MMU_PERM_PKG_SV
// SPDX-License-Identifier: MIT
// HarvOS SV32 MMU permission helpers

// For synthesis with Yosys (no package support), emit plain defs in global scope.
`ifdef SYNTHESIS
  // --- TYPEDEFS (global) ---
  typedef enum logic [1:0] { MMU_ACC_LOAD=2'b00, MMU_ACC_STORE=2'b01, MMU_ACC_EXEC=2'b10 } mmu_acc_e;
  typedef struct packed {
    logic V; logic R; logic W; logic X; logic U; logic G; logic A; logic D;
  } pte_flags_t;
  typedef struct packed {
    logic allow;
    logic need_set_A;
    logic need_set_D;
    logic [3:0] fault;
  } mmu_perm_res_t;

  parameter integer MSTATUS_BIT_MXR = 19;
  parameter integer SSTATUS_BIT_SUM = 18;

  function automatic mmu_perm_res_t mmu_check_perms(
      input logic               priv_is_user,
      input mmu_acc_e           acc,
      input pte_flags_t         p,
      input logic               csr_mxr,
      input logic               csr_sum,
      input logic               use_hw_set_ad
  );
  begin : mmu_check_body_clean
    mmu_perm_res_t r;
    logic perm_ok;

    // default reset
    r.allow      = 1'b0;
    r.need_set_A = 1'b0;
    r.need_set_D = 1'b0;
    r.fault      = 4'h0;

    // 1) Basic validity
    if (!p.V) begin
      r.fault = 4'h1;
    end else if (p.W && p.X) begin
      // 2) W^X invariant
      r.fault = 4'h2;
    end else begin
      // 3) Privilege vs U-bit
      if (priv_is_user) begin
        if (!p.U) r.fault = 4'h3;
      end else begin
        if (p.U && !csr_sum) r.fault = 4'h4;
      end

      // 4) Permission- and A/D-policy only if still no fault
      if (r.fault == 4'h0) begin
        case (acc)
          MMU_ACC_EXEC: begin
            perm_ok = p.X;
            if (!perm_ok) begin
              r.fault = 4'h5;
            end else begin
              if (!p.A) begin
                if (use_hw_set_ad) r.need_set_A = 1'b1;
                else r.fault = 4'h6;
              end
              if (r.fault == 4'h0) r.allow = 1'b1;
            end
          end

          MMU_ACC_LOAD: begin
            perm_ok = p.R || (csr_mxr && p.X);
            if (!perm_ok) begin
              r.fault = 4'h7;
            end else begin
              if (!p.A) begin
                if (use_hw_set_ad) r.need_set_A = 1'b1;
                else r.fault = 4'h6;
              end
              if (r.fault == 4'h0) r.allow = 1'b1;
            end
          end

          MMU_ACC_STORE: begin
            perm_ok = p.W;
            if (!perm_ok) begin
              r.fault = 4'h8;
            end else begin
              if (!p.A) begin
                if (use_hw_set_ad) r.need_set_A = 1'b1;
                else r.fault = 4'h6;
              end
              if (r.fault == 4'h0 && !p.D) begin
                if (use_hw_set_ad) r.need_set_D = 1'b1;
                else r.fault = 4'h9;
              end
              if (r.fault == 4'h0) r.allow = 1'b1;
            end
          end

          default: begin
            r.fault = 4'hF;
          end
        endcase
      end
    end

    mmu_check_perms = r;
  end
  endfunction

// For simulation/formal, keep the original package version.
`else
`ifndef MMU_PERM_PKG_SV
`define MMU_PERM_PKG_SV
// SPDX-License-Identifier: MIT
// HarvOS SV32 MMU permission package: A/D policy + MXR + SUM handling
package mmu_perm_pkg;
  // Access type
  typedef enum logic [1:0] { MMU_ACC_LOAD=2'b00, MMU_ACC_STORE=2'b01, MMU_ACC_EXEC=2'b10 } mmu_acc_e;

  // PTE flag bits (SV32-like): V, R, W, X, U, G, A, D  (others reserved)
  typedef struct packed {
    logic V;  // valid
    logic R;
  logic W;
  logic X;
  logic U;
  logic G;
  logic A;  // accessed
    logic D;  // dirty
  } pte_flags_t;

  typedef struct packed {
    logic allow;         // final allow decision
    logic need_set_A;    // needs A set (if HW-set mode is enabled)
    logic need_set_D;    // needs D set (if HW-set mode is enabled, only for stores)
    logic [3:0] fault;   // 0 = none, otherwise implementation-defined fault code
  } mmu_perm_res_t;

  // Parameterizable CSR bit positions (adjust to your CSR map if needed)
  parameter integer MSTATUS_BIT_MXR = 19; // MXR: Make eXecutable Readable (RISC-V compatible default)
  parameter integer SSTATUS_BIT_SUM = 18; // SUM: permit S to access U pages

  // Permission check core
  // SPDX-License-Identifier: MIT
// HarvOS SV32 MMU permission package: A/D policy + MXR + SUM handling
package mmu_perm_pkg;
  // Access type
  typedef enum logic [1:0] { MMU_ACC_LOAD=2'b00, MMU_ACC_STORE=2'b01, MMU_ACC_EXEC=2'b10 } mmu_acc_e;

  // PTE flag bits (SV32-like): V, R, W, X, U, G, A, D  (others reserved)
  typedef struct packed {
    logic V;  // valid
    logic R;
  logic W;
  logic X;
  logic U;
  logic G;
  logic A;  // accessed
    logic D;  // dirty
  } pte_flags_t;

  typedef struct packed {
    logic allow;         // final allow decision
    logic need_set_A;    // needs A set (if HW-set mode is enabled)
    logic need_set_D;    // needs D set (if HW-set mode is enabled, only for stores)
    logic [3:0] fault;   // 0 = none, otherwise implementation-defined fault code
  } mmu_perm_res_t;

  // Parameterizable CSR bit positions (adjust to your CSR map if needed)
  parameter integer MSTATUS_BIT_MXR = 19; // MXR: Make eXecutable Readable (RISC-V compatible default)
  parameter integer SSTATUS_BIT_SUM = 18; // SUM: permit S to access U pages

  // Permission check core
  function automatic mmu_perm_res_t mmu_check_perms(
      input logic               priv_is_user,   // 1: U-mode, 0: S-mode
      input mmu_acc_e           acc,
      input pte_flags_t         p,              // PTE flags
      input logic               csr_mxr,        // 1: MXR enabled
      input logic               csr_sum,        // 1: SUM enabled
      input logic               use_hw_set_ad   // 1: HW will set A/D, 0: fault when A/D==0
  );
  begin : mmu_check_body_clean
    mmu_perm_res_t r;
    logic perm_ok;

    // default reset
    r.allow      = 1'b0;
    r.need_set_A = 1'b0;
    r.need_set_D = 1'b0;
    r.fault      = 4'h0;

    // 1) Basic validity
    if (!p.V) begin
      r.fault = 4'h1;
    end else if (p.W && p.X) begin
      // 2) W^X invariant
      r.fault = 4'h2;
    end else begin
      // 3) Privilege vs U-bit
      if (priv_is_user) begin
        if (!p.U) r.fault = 4'h3;
      end else begin
        if (p.U && !csr_sum) r.fault = 4'h4;
      end

      // 4) Permission- and A/D-policy only if still no fault
      if (r.fault == 4'h0) begin
        case (acc)
          MMU_ACC_EXEC: begin
            perm_ok = p.X;
            if (!perm_ok) begin
              r.fault = 4'h5;
            end else begin
              if (!p.A) begin
                if (use_hw_set_ad) r.need_set_A = 1'b1;
                else r.fault = 4'h6;
              end
              if (r.fault == 4'h0) r.allow = 1'b1;
            end
          end

          MMU_ACC_LOAD: begin
            perm_ok = p.R || (csr_mxr && p.X);
            if (!perm_ok) begin
              r.fault = 4'h7;
            end else begin
              if (!p.A) begin
                if (use_hw_set_ad) r.need_set_A = 1'b1;
                else r.fault = 4'h6;
              end
              if (r.fault == 4'h0) r.allow = 1'b1;
            end
          end

          MMU_ACC_STORE: begin
            perm_ok = p.W;
            if (!perm_ok) begin
              r.fault = 4'h8;
            end else begin
              if (!p.A) begin
                if (use_hw_set_ad) r.need_set_A = 1'b1;
                else r.fault = 4'h6;
              end
              if (r.fault == 4'h0 && !p.D) begin
                if (use_hw_set_ad) r.need_set_D = 1'b1;
                else r.fault = 4'h9;
              end
              if (r.fault == 4'h0) r.allow = 1'b1;
            end
          end

          default: begin
            r.fault = 4'hF;
          end
        endcase
      end
    end

    mmu_check_perms = r;
  end
endfunction

endpackage : mmu_perm_pkg
`endif

`endif
`endif
