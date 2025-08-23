// mpu_programmer.sv — Simple MPU region programmer for HarvOS core
// Programs three regions at reset, then goes idle. Intended to be instantiated in top_soc
// and wired to harvos_core's mpu_prog_* ports.
// Regions (default):
//   0: I-space ROM/XIP  [RX]
//   1: D-space RAM      [RW, NX]
//   2: MMIO window      [RW, NX, U=0]
//
// After programming, software (Boot ROM) must set CSR smpuctl (0x130) bit0=LOCK=1, as per whitepaper.
// See Appendix "Security Amendments (2025 Review)" for code immutability and LOCK invariants.
//
// Parameters let you adapt addresses/sizes to your SoC map.
`timescale 1ns/1ps

module mpu_programmer #(
  parameter integer NREG = 8,
  parameter [31:0] ROM_BASE      = 32'h0000_0000,
  parameter [31:0] ROM_LIMIT     = 32'h0000_FFFF, // inclusive
  parameter [2:0]  ROM_PERM_XWR  = 3'b101,        // {X,W,R} = RX
  parameter        ROM_USER_OK   = 1'b1,
  parameter        ROM_IS_ISPACE = 1'b1,

  parameter [31:0] RAM_BASE      = 32'h2000_0000,
  parameter [31:0] RAM_LIMIT     = 32'h2001_FFFF,
  parameter [2:0]  RAM_PERM_XWR  = 3'b011,        // RW, NX
  parameter        RAM_USER_OK   = 1'b1,
  parameter        RAM_IS_ISPACE = 1'b0,

  parameter [31:0] MMIO_BASE      = 32'h1000_0000,
  parameter [31:0] MMIO_LIMIT     = 32'h1000_FFFF,
  parameter [2:0]  MMIO_PERM_XWR  = 3'b011,       // RW, NX
  parameter        MMIO_USER_OK   = 1'b0,         // supervisor-only
  parameter        MMIO_IS_ISPACE = 1'b0
) (
  input  wire clk,
  input  wire rst_n,

  // Drive these to the harvos_core ports
  output reg              mpu_prog_en,
  output reg  [2:0]       mpu_prog_idx,
  output reg  [31:0]      mpu_prog_base,
  output reg  [31:0]      mpu_prog_limit,
  output reg  [2:0]       mpu_prog_perm,    // {X,W,R}
  output reg              mpu_prog_user_ok,
  output reg              mpu_prog_is_ispace,

  // Optional: status for firmware/tests
  output reg              mpu_prog_done
);

  typedef enum logic [1:0] { S_IDLE, S_ROM, S_RAM, S_MMIO } state_e;
  state_e st_q, st_d;

  // default outputs
  always @(*) begin
    mpu_prog_en        = 1'b0;
    mpu_prog_idx       = 3'd0;
    mpu_prog_base      = 32'h0;
    mpu_prog_limit     = 32'h0;
    mpu_prog_perm      = 3'b000;
    mpu_prog_user_ok   = 1'b0;
    mpu_prog_is_ispace = 1'b0;
    mpu_prog_done      = 1'b0;
    st_d               = st_q;

    case (st_q)
      S_IDLE: begin
        // On reset release we immediately program ROM
        st_d = S_ROM;
      end
      S_ROM: begin
        mpu_prog_idx       = 3'd0;
        mpu_prog_base      = ROM_BASE;
        mpu_prog_limit     = ROM_LIMIT;
        mpu_prog_perm      = ROM_PERM_XWR;
        mpu_prog_user_ok   = ROM_USER_OK;
        mpu_prog_is_ispace = ROM_IS_ISPACE;
        mpu_prog_en        = 1'b1;
        st_d               = S_RAM;
      end
      S_RAM: begin
        mpu_prog_idx       = 3'd1;
        mpu_prog_base      = RAM_BASE;
        mpu_prog_limit     = RAM_LIMIT;
        mpu_prog_perm      = RAM_PERM_XWR;
        mpu_prog_user_ok   = RAM_USER_OK;
        mpu_prog_is_ispace = RAM_IS_ISPACE;
        mpu_prog_en        = 1'b1;
        st_d               = S_MMIO;
      end
      S_MMIO: begin
        mpu_prog_idx       = 3'd2;
        mpu_prog_base      = MMIO_BASE;
        mpu_prog_limit     = MMIO_LIMIT;
        mpu_prog_perm      = MMIO_PERM_XWR;
        mpu_prog_user_ok   = MMIO_USER_OK;
        mpu_prog_is_ispace = MMIO_IS_ISPACE;
        mpu_prog_en        = 1'b1;
        st_d               = S_IDLE;
        mpu_prog_done      = 1'b1;
      end
      default: begin
        st_d = S_IDLE;
      end
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) st_q <= S_IDLE;
    else        st_q <= st_d;
  end

endmodule
