// crypto_ed25519_verify.sv — Placeholder Ed25519 verify (SIM model)
// NOTE: This is a development-time stub. Replace with a real implementation/IP.
module crypto_ed25519_verify #(
  parameter bit SIM_FAKE = 1
)(
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        start_i,
  input  logic [255:0] pubkey_i,
  input  logic [511:0] signature_i,
  input  logic [255:0] msg_hash_i,
  output logic        done_o,
  output logic        ok_o
);
`ifdef SIMULATION
  // Very rough SIM behavior: one-cycle done; ok if lower 256b of signature XOR pubkey equals msg_hash
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      done_o <= 1'b0;
      ok_o   <= 1'b0;
    end else if (start_i) begin
      done_o <= 1'b1;
      ok_o   <= ((signature_i[255:0] ^ pubkey_i) == msg_hash_i);
    end else begin
      done_o <= 1'b0;
    end
  end
`else
  // Default non-sim model: simple fixed latency and deterministic false unless SIM_FAKE==1
  localparam integer LAT = 8;
  logic [$clog2(LAT):0] cnt;
  logic busy;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      busy  <= 1'b0;
      cnt   <= '0;
      done_o<= 1'b0;
      ok_o  <= 1'b0;
    end else begin
      done_o <= 1'b0;
      if (start_i && !busy) begin
        busy <= 1'b1;
        cnt  <= LAT;
      end else if (busy) begin
        if (cnt == 0) begin
          busy  <= 1'b0;
          done_o<= 1'b1;
          ok_o  <= (SIM_FAKE ? 1'b1 : 1'b0);
        end else begin
          cnt <= cnt - 1'b1;
        end
      end
    end
  end
`endif
endmodule
