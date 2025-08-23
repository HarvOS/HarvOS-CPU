// boot_sigcheck.sv — Boot signature gate with mailbox + (sim) crypto verify
`timescale 1ns/1ps
module boot_sigcheck (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        lock_i,      // sticky LOCK — blocks further writes
  input  logic        wr_en,       // MMIO write strobe to mailbox (single address)
  input  logic [31:0] wr_data,     // write data (word stream)
  output logic [31:0] rd_data,     // readback: {done, ok, idx[7:0], reserved}
  output logic        sig_ok       // 1 when signature check passed
);
  // Mailbox collects: 8 words pubkey (256b), 16 words signature (512b), 8 words msg_hash (256b), then CTRL
  typedef enum logic [1:0] { MB_PKH=2'd0, MB_SIG=2'd1, MB_HASH=2'd2, MB_CTRL=2'd3 } mb_seg_e;

  logic [7:0]  idx_q, idx_n;
  mb_seg_e     seg_q, seg_n;
  logic        started_q, started_n;
  logic        done_q, done_n;
  logic        ok_q, ok_n;

  logic [255:0] pkh_q,   pkh_n;    // public key (Ed25519)
  logic [511:0] sig_q,   sig_n;    // signature (R||S)
  logic [255:0] hash_q,  hash_n;   // message hash (use SHA-512[255:0] low half in sim)

  // Write collect logic
  always_comb begin
    seg_n      = seg_q;
    idx_n      = idx_q;
    pkh_n      = pkh_q;
    sig_n      = sig_q;
    hash_n     = hash_q;
    started_n  = started_q;
    done_n     = done_q;
    ok_n       = ok_q;

    if (wr_en && !lock_i && !started_q) begin
      case (seg_q)
        MB_PKH: begin
          pkh_n  = {wr_data, pkh_q[255:32]};
          idx_n  = idx_q + 8'd1;
          if (idx_q == 8'd7) begin seg_n = MB_SIG; idx_n = 8'd0; end
        end
        MB_SIG: begin
          sig_n  = {wr_data, sig_q[511:32]};
          idx_n  = idx_q + 8'd1;
          if (idx_q == 8'd15) begin seg_n = MB_HASH; idx_n = 8'd0; end
        end
        MB_HASH: begin
          hash_n = {wr_data, hash_q[255:32]};
          idx_n  = idx_q + 8'd1;
          if (idx_q == 8'd7) begin seg_n = MB_CTRL; idx_n = 8'd0; end
        end
        MB_CTRL: begin
          // bit0 = start
          if (wr_data[0]) begin
            started_n = 1'b1;
          end
        end
      endcase
    end

    // Latch results
    if (sig_done && started_q && !done_q) begin
      done_n = 1'b1;
      ok_n   = sig_ok_int;
    end

    // Expose rd_data
  end

  // Register state
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      seg_q     <= MB_PKH;
      idx_q     <= '0;
      pkh_q     <= '0;
      sig_q     <= '0;
      hash_q    <= '0;
      started_q <= 1'b0;
      done_q    <= 1'b0;
      ok_q      <= 1'b0;
    end else begin
      seg_q     <= seg_n;
      idx_q     <= idx_n;
      pkh_q     <= pkh_n;
      sig_q     <= sig_n;
      hash_q    <= hash_n;
      started_q <= started_n;
      done_q    <= done_n;
      ok_q      <= ok_n;
    end
  end

  // Crypto verify (simulation model by default)
  logic sig_done, sig_ok_int;

  crypto_ed25519_verify #(.SIM_FAKE(1)) u_verify (
    .clk_i(clk), .rst_ni(rst_n),
    .start_i(started_q & ~done_q),
    .pubkey_i(pkh_q),
    .signature_i(sig_q),
    .msg_hash_i(hash_q),
    .done_o(sig_done),
    .ok_o(sig_ok_int)
  );

  // Outputs
  assign sig_ok  = ok_q;
  always_comb begin
    rd_data = 32'h0;
    rd_data[31]   = done_q;
    rd_data[30]   = ok_q;
    rd_data[7:0]  = idx_q;
  end

endmodule
