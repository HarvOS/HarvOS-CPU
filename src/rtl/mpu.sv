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

`ifndef __YOSYS_ASSERT_STUBS__
`define __YOSYS_ASSERT_STUBS__ 1
`ifndef ASSERT_IMP
`define ASSERT_IMP(name, expr)
`endif
`ifndef ASSERT_NEVER
`define ASSERT_NEVER(name, expr)
`endif
`endif


`include "harvos_pkg_flat.svh"
module mpu #(
  parameter integer NREG = 8
) (
  input  logic                          clk,
  input  logic                          rst_n,
  input  logic [31:0]                   smpuctl_q, // bit0 = LOCK
  // region programming interface (simple CSR-like wires for MVP)
  input  logic                          prog_en,
  input  logic [$clog2(NREG)-1:0]       prog_idx,
  input  mpu_region_s       prog_region,

  // check inputs
  input  acc_e              acc_type,   // fetch/load/store
  input  priv_e             cur_priv,
  input  logic [31:0]                   phys_addr,
  output logic                          allow,
  output logic                          is_ispace_region
);
  
  // ----- Hoisted declarations for Yosys SV parser -----
  integer i;  // hoisted loop var from for(...) header
  integer i;  // hoisted from procedural decl

  logic regs_valid[NREG];  // flattened from mpu_region_s regs_valid[NREG]

  logic [31:0] regs_base[NREG];  // flattened from mpu_region_s regs_base[NREG]

  logic [31:0] regs_limit[NREG];  // flattened from mpu_region_s regs_limit[NREG]

  logic regs_allow_r[NREG];  // flattened from mpu_region_s regs_allow_r[NREG]

  logic regs_allow_w[NREG];  // flattened from mpu_region_s regs_allow_w[NREG]

  logic regs_allow_x[NREG];  // flattened from mpu_region_s regs_allow_x[NREG]

  logic regs_user_ok[NREG];  // flattened from mpu_region_s regs_user_ok[NREG]

  logic regs_is_ispace[NREG];  // flattened from mpu_region_s regs_is_ispacelogic[NREG] lock;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin



      for (i = 0; i < NREG; i++) regs_valid[i] <= '0; regs_base[i] <= '0; regs_limit[i] <= '0; regs_allow_r[i] <= '0; regs_allow_w[i] <= '0; regs_allow_x[i] <= '0; regs_user_ok[i] <= '0; regs_is_ispace[i] <= '0;
    end else begin
      // lock is sticky via lock_q; gate programming on lock_q
      if (prog_en && !lock_q) begin
        regs_valid[prog_idx] <= prog_region.valid; regs_base[prog_idx] <= prog_region.base; regs_limit[prog_idx] <= prog_region.limit; regs_allow_r[prog_idx] <= prog_region.allow_r; regs_allow_w[prog_idx] <= prog_region.allow_w; regs_allow_x[prog_idx] <= prog_region.allow_x; regs_user_ok[prog_idx] <= prog_region.user_ok; regs_is_ispace[prog_idx] <= prog_region.is_ispace;
      end
    end
  end

  // comb check
  logic hit;
  // LOCK latch: once smpuctl_q[0] observed high, lock_q stays high until reset
  logic lock_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) lock_q <= 1'b0; else lock_q <= lock_q | smpuctl_q[0];
  end

  logic allow_r, allow_w, allow_x, user_ok;
  logic region_is_ispace;
  always_comb begin
    hit = 1'b0;
    allow_r = 1'b0; allow_w = 1'b0; allow_x = 1'b0; user_ok = 1'b0;
    region_is_ispace = 1'b0;
    for (i = 0; i < NREG; i++) begin
      if (regs_valid[i] && phys_addr >= regs_base[i] && phys_addr <= regs_limit[i]) begin
        hit = 1'b1;
        allow_r = regs_allow_r[i];
        allow_w = regs_allow_w[i];
        allow_x = regs_allow_x[i];
        user_ok = regs_user_ok[i];
        region_is_ispace = regs_is_ispace[i];
      end
    end

    // default deny if not in any region
    allow = 1'b0;
    is_ispace_region = region_is_ispace;

    if (hit) begin
      case (acc_type)
        ACC_FETCH: allow = allow_x;
        ACC_LOAD:  allow = allow_r;
        ACC_STORE: allow = allow_w;
        default:   allow = 1'b0;
      endcase
      if (cur_priv == PRIV_U && !user_ok) allow = 1'b0;
    end
  end


  // MPU lock property (informal):
  // Once lock_q is 1, region registers must not change.
  // This can be formalized with SVA in a separate bind file.

`ifdef FORMAL
`include "formal/mpu_lock_sva.inc"
`endif

endmodule


