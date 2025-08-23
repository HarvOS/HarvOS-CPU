// code_sec_ctrl.sv — MMIO control block for code immutability
// Exposes two write-1-to-set bits:
//   - UPDATE_EN_SET (bit 1): Allows pre-LOCK writes to code regions. Clears automatically on LOCK.
//   - WP_SET        (bit 0): Permanently sets write-protect latch (wp_q).
// Reads back status: {reserved[31:3], lock, update_en, wp_q}
`timescale 1ns/1ps

module code_sec_ctrl (
  input  wire clk,
  input  wire rst_n,
  input  wire lock_i,

  // Write strobes into this MMIO register
  input  wire wr_en,          // 1-cycle pulse when software writes the control register
  input  wire [31:0] wr_data, // bit1=UPDATE_EN_SET, bit0=WP_SET

  output reg  update_en_q,    // Pre-LOCK update enable (clears on lock)
  output wire wp_set_pulse,   // Pulse to code_wp_latch
  output wire [31:0] rd_data  // Status readback
);
  // write-1-to-set semantics for UPDATE_EN before lock
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      update_en_q <= 1'b0;
    end else begin
      if (lock_i) begin
        update_en_q <= 1'b0; // auto-clear on LOCK
      end else if (wr_en && wr_data[1]) begin
        update_en_q <= 1'b1;
      end
    end
  end

  assign wp_set_pulse = wr_en && wr_data[0];

  assign rd_data = { 29'd0, lock_i, update_en_q, /*wp*/ 1'b0 };
endmodule
