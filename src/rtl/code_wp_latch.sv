// code_wp_latch.sv — Sticky Write-Protect latch for code storage
// Sets permanently (until reset) when either:
//   - LOCK (smpuctl.LOCK) is asserted, or
//   - software writes WP_SET=1 via the control MMIO register.
// Optional manufacturing strap can keep WP cleared during factory flashing.
//
// This is a single-bit "write-1-to-set" latch. Clearing is impossible without reset.
`timescale 1ns/1ps

module code_wp_latch (
  input  wire clk,
  input  wire rst_n,
  input  wire lock_i,           // sticky system LOCK (e.g., from CSR smpuctl[0])
  input  wire wp_set_i,         // pulse from MMIO: write 1 to set
  input  wire manuf_mode_i,     // 1 = factory mode; WP is not auto-set by reset; still sets if wp_set_i or lock_i
  output reg  wp_q              // 1 = write-protect active
);
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // In manufacturing mode we start with WP=0; otherwise also 0 (Boot decides when to set)
      wp_q <= 1'b0;
    end else begin
      // Once set, never clears until reset
      if (wp_q) begin
        wp_q <= 1'b1;
      end else if (lock_i | wp_set_i) begin
        wp_q <= 1'b1;
      end else begin
        wp_q <= 1'b0;
      end
    end
  end
endmodule
