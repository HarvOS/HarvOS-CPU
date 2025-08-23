`timescale 1ns/1ps
`include "rtl/harvos_pkg_flat.svh"
module tb_mpu_lock;
  localparam int NREG = 8;

  logic clk=0, rst_n=0;
  always #5 clk = ~clk;

  // DUT
  logic [31:0] smpuctl_q;
  logic        prog_en;
  logic [2:0]  prog_idx;
  logic [31:0] prog_base, prog_limit;
  logic [2:0]  prog_perm; // {X,W,R}
  logic        prog_user_ok, prog_is_ispace;

  // Access check wires (unused in this simple test)
  typedef enum logic [1:0] { ACC_FETCH=2'b00, ACC_LOAD=2'b01, ACC_STORE=2'b10 } acc_e;
  typedef enum logic [0:0] { PRIV_U=1'b0, PRIV_S=1'b1 } priv_e;
  logic allow, is_ispace_region;

  // Pack region
  typedef struct packed {
    logic        valid;
    logic [31:0] base;
    logic [31:0] limit;
    logic        allow_r;
    logic        allow_w;
    logic        allow_x;
    logic        user_ok;
    logic        is_ispace;
  } mpu_region_s;
  mpu_region_s region;

  function void drive_region(input [2:0] idx, input [31:0] base, input [31:0] limit, input [2:0] xwr, input user_ok, input is_ispace);
    begin
      prog_idx        = idx;
      prog_base       = base;
      prog_limit      = limit;
      prog_perm       = xwr;
      prog_user_ok    = user_ok;
      prog_is_ispace  = is_ispace;
      region.valid     = 1'b1;
      region.base      = base;
      region.limit     = limit;
      region.allow_r   = xwr[0];
      region.allow_w   = xwr[1];
      region.allow_x   = xwr[2];
      region.user_ok   = user_ok;
      region.is_ispace = is_ispace;
      prog_en = 1'b1; @(posedge clk); prog_en = 1'b0;
    end
  endfunction

  // Instantiate DUT
  mpu #(.NREG(NREG)) DUT (
    .clk(clk), .rst_n(rst_n),
    .smpuctl_q(smpuctl_q),
    .prog_en(prog_en), .prog_idx(prog_idx), .prog_region(region),
    .acc_type(ACC_LOAD), .cur_priv(PRIV_S),
    .phys_addr(32'h0), .allow(allow), .is_ispace_region(is_ispace_region)
  );

  // Test sequence
  initial begin
    // Reset
    smpuctl_q = 32'h0;
    prog_en = 1'b0; prog_idx='0; prog_base='0; prog_limit='0; prog_perm='0; prog_user_ok=1'b0; prog_is_ispace=1'b0;
    rst_n = 1'b0; repeat(3) @(posedge clk); rst_n = 1'b1; repeat(2) @(posedge clk);

    // Program three regions
    drive_region(3'd0, 32'h0000_0000, 32'h0000_FFFF, 3'b101, 1'b1, 1'b1); // ROM RX
    drive_region(3'd1, 32'h2000_0000, 32'h2001_FFFF, 3'b011, 1'b1, 1'b0); // RAM RW NX
    drive_region(3'd2, 32'h1000_0000, 32'h1000_FFFF, 3'b011, 1'b0, 1'b0); // MMIO RW NX, supervisor-only

    // Lock
    smpuctl_q[0] = 1'b1; @(posedge clk);

    // Try to overwrite RAM perms to X=1 (should be ignored)
    drive_region(3'd1, 32'h2000_0000, 32'h2001_FFFF, 3'b111, 1'b1, 1'b0);

    // Read back via hierarchical reference (for simple RTL test)
    if (^DUT.regs_allow_x[1] === 1'bX) $display("WARNING: visibility of regs_* depends on synthesis tool");
    if (DUT.regs_allow_x[1] !== 1'b0) begin
      $display("FAIL: LOCK failed—X bit changed after lock");
      $fatal;
    end else begin
      $display("OK: LOCK held—RAM remained NX after lock");
    end
    $finish;
  end
endmodule
