
// Included into mpu.sv under `ifdef FORMAL`
generate
  genvar gi;
  for (gi=0; gi<NREG; gi=gi+1) begin : g_lock
    always @(posedge clk) begin
      if (lock_q) begin
        assert($stable(regs_valid[gi]));
        assert($stable(regs_base[gi]));
        assert($stable(regs_limit[gi]));
        assert($stable(regs_allow_r[gi]));
        assert($stable(regs_allow_w[gi]));
        assert($stable(regs_allow_x[gi]));
        assert($stable(regs_user_ok[gi]));
        assert($stable(regs_is_ispace[gi]));
      end
    end
  end
endgenerate
