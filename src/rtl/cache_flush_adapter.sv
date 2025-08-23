// cache_flush_adapter.sv — adapt a 1-cycle req to a cache's invalidate-all handshake
// This module stretches a single-cycle 'flush_req' into an active-high 'flush_do' for N cycles
// or until 'flush_ack' arrives (if present). Tie 'flush_ack' low if your cache has no ack.
`timescale 1ns/1ps
module cache_flush_adapter #(
  parameter integer HOLD_CYCLES = 8
) (
  input  wire clk,
  input  wire rst_n,
  input  wire flush_req,  // 1-cycle pulse
  input  wire flush_ack,  // optional cache ack (active high); can be 0
  output reg  flush_do    // drive this into your cache's "invalidate all" input
);
  reg [7:0] cnt;
  reg active;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt <= 8'd0; active <= 1'b0; flush_do <= 1'b0;
    end else begin
      flush_do <= 1'b0;
      if (flush_req) begin
        active <= 1'b1; cnt <= HOLD_CYCLES[7:0];
      end
      if (active) begin
        flush_do <= 1'b1;
        if (flush_ack || (cnt==8'd0)) active <= 1'b0;
        else cnt <= cnt - 8'd1;
      end
    end
  end
endmodule
