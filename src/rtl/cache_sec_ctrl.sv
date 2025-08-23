// cache_sec_ctrl.sv — Cache security control: context-switch flush + way masks per cache
// Verilog-2005 compatible
`timescale 1ns/1ps

module cache_sec_ctrl #(
  parameter integer I_WAYS = 4,
  parameter integer D_WAYS = 4
) (
  input  wire        clk,
  input  wire        rst_n,

  // From CSR/MMU
  input  wire        asid_change_pulse, // from asid_change_pulse or satp_guard
  input  wire        sfence_global,     // sfence.vma global (optional, OR with asid_change)

  // From MPU/CSR (sticky lock)
  input  wire        lock_i,

  // MMIO control (simple single 32-bit register, write-1-to-set policy for bits that are sticky)
  input  wire        wr_en,
  input  wire [31:0] wr_data,
  output wire [31:0] rd_data,

  // Outputs to caches
  output reg         ic_flush_req,
  output reg         dc_flush_req,
  output reg [I_WAYS-1:0] ic_way_mask, // 1=way enabled; applied by icache replacement/select logic
  output reg [D_WAYS-1:0] dc_way_mask  // 1=way enabled
);
  // Register map (single 32-bit reg):
  // [31]     FLUSH_ON_ASID (sticky; write 1 to set; clears only on reset)
  // [30]     FLUSH_ON_SFENCE (sticky)
  // [29:24]  reserved
  // [23:16]  DC_WAY_MASK (masked to D_WAYS)
  // [15:8]   IC_WAY_MASK (masked to I_WAYS)
  // [7]      FORCE_FLUSH_DC (write 1 -> generates dc_flush_req one cycle)
  // [6]      FORCE_FLUSH_IC (write 1 -> generates ic_flush_req one cycle)
  // [5:0]    reserved

  reg        flush_on_asid_q;
  reg        flush_on_sfence_q;

  wire [7:0] ic_mask_w = wr_data[15:8];
  wire [7:0] dc_mask_w = wr_data[23:16];

  // Way mask defaults to all enabled
  wire [I_WAYS-1:0] ic_mask_all = {I_WAYS{1'b1}};
  wire [D_WAYS-1:0] dc_mask_all = {D_WAYS{1'b1}};

  // Sticky config (LOCK prevents further changes)
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      flush_on_asid_q   <= 1'b1; // default: enabled
      flush_on_sfence_q <= 1'b1; // default: enabled
      ic_way_mask       <= ic_mask_all;
      dc_way_mask       <= dc_mask_all;
      ic_flush_req      <= 1'b0;
      dc_flush_req      <= 1'b0;
    end else begin
      // one-cycle force flush pulses
      ic_flush_req <= wr_en && wr_data[6];
      dc_flush_req <= wr_en && wr_data[7];

      // generated on context events
      if ((flush_on_asid_q && asid_change_pulse) || (flush_on_sfence_q && sfence_global)) begin
        ic_flush_req <= 1'b1;
        dc_flush_req <= 1'b1;
      end

      // config writes before LOCK
      if (wr_en && !lock_i) begin
        // Sticky enable bits
        if (wr_data[31]) flush_on_asid_q   <= 1'b1;
        if (wr_data[30]) flush_on_sfence_q <= 1'b1;
        // Way masks (non-sticky; can be tuned per boot policy before LOCK)
        ic_way_mask <= ic_mask_w[I_WAYS-1:0];
        dc_way_mask <= dc_mask_w[D_WAYS-1:0];
      end
    end
  end

  assign rd_data = { flush_on_asid_q, flush_on_sfence_q, 6'd0,
                     dc_way_mask, ic_way_mask, 2'd0, // [15:8]=IC, [23:16]=DC
                     6'd0 };

endmodule
