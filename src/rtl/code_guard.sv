// code_guard.sv — Hard write-protect for code/XIP memory windows
// Denies writes to code regions based on sticky WP latch and/or LOCK.
// Allows writes pre-LOCK only if 'update_en' is set (Boot ROM controlled).
// Read accesses are never blocked here (execute path is separate via Harvard/MPU).
`timescale 1ns/1ps

module code_guard #(
  parameter [31:0] CODE0_BASE  = 32'h0000_0000,
  parameter [31:0] CODE0_LIMIT = 32'h000F_FFFF, // inclusive
  parameter [31:0] CODE1_BASE  = 32'h0010_0000, // set CODE1_LIMIT < CODE1_BASE to disable
  parameter [31:0] CODE1_LIMIT = 32'h0000_0000
)(
  input  wire        req_valid,
  input  wire        req_write,      // 1=write, 0=read
  input  wire [31:0] req_addr,

  input  wire        lock_i,         // sticky system LOCK
  input  wire        wp_q,           // code write-protect latched
  input  wire        update_en,      // Boot ROM enables pre-lock update window

  output wire        allow_write     // 1=permit write, 0=block write
);
  function automatic in_code0; input [31:0] a; begin
    in_code0 = ((a >= CODE0_BASE) && (a <= CODE0_LIMIT));
  end
  endfunction
  function automatic in_code1; input [31:0] a; begin
    in_code1 = ((CODE1_LIMIT >= CODE1_BASE) && (a >= CODE1_BASE) && (a <= CODE1_LIMIT));
  end
  endfunction
  wire in_code = in_code0(req_addr) | in_code1(req_addr);

  // Policy:
  // - Reads: allowed (this module only governs writes)
  // - Writes to non-code: allowed
  // - Writes to code:
  //     * If wp_q==1 OR lock_i==1 -> denied
  //     * Else (pre-lock window): allowed only if update_en==1
  assign allow_write = (req_valid && req_write) ?
                       (in_code ? ((wp_q | lock_i) ? 1'b0 : update_en)
                                : 1'b1)
                       : 1'b1;

`ifndef SYNTHESIS
  // Code-guard invariant: post-WP or post-LOCK, no writes to code regions
  always @* begin
    if (in_code && req_write && (wp_q || lock_i)) begin
      assert (allow_write == 1'b0) else $error("Code write allowed despite WP/LOCK");
    end
  end
`endif
endmodule
