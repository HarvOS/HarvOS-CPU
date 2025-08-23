`timescale 1ns/1ps
module tb_alias_guard;
  // clock
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0;

  // tracker
  reg        clear_i, insert_i;
  reg [19:0] insert_ppn;
  reg [31:0] query_pa;
  wire       hit_exec_ppn;

  exec_ppn_tracker #(.PPN_W(20), .N(8)) u_trk (
    .clk(clk), .rst_n(rst_n),
    .clear_i(clear_i), .insert_i(insert_i), .insert_ppn(insert_ppn),
    .query_pa(query_pa), .hit_exec_ppn(hit_exec_ppn)
  );

  // guard
  reg        lock_i, allow_override_prelock;
  reg        write_valid, write_en;
  reg [31:0] write_addr;
  wire       allow_write;

  alias_guard u_guard (
    .write_valid(write_valid), .write_en(write_en), .write_addr(write_addr),
    .hit_exec_ppn(hit_exec_ppn),
    .lock_i(lock_i), .allow_override_prelock(allow_override_prelock),
    .allow_write(allow_write)
  );

  // helpers
  task add_exec_page(input [31:0] pa);
    begin
      insert_ppn = pa[31:12];
      insert_i   = 1'b1; @(posedge clk); insert_i = 1'b0; @(posedge clk);
    end
  endtask

  task try_store(input [31:0] pa, input string tag, input bit expect_allow);
    begin
      write_addr=pa; query_pa=pa; write_en=1; write_valid=1; @(posedge clk);
      write_valid=0; write_en=0; @(posedge clk);
      if (allow_write !== expect_allow) begin
        $display("FAIL %s: addr=%h expected allow=%0d got %0d", tag, pa, expect_allow, allow_write);
        $fatal;
      end else $display("OK   %s (allow=%0d)", tag, allow_write);
    end
  endtask

  initial begin
    // reset
    clear_i=0; insert_i=0; insert_ppn=0; query_pa=0;
    lock_i=0; allow_override_prelock=0;
    write_valid=0; write_en=0; write_addr=0;
    repeat(3) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

    // 1) No exec pages yet -> write allowed
    try_store(32'h0800_4000, "no exec pages", 1'b1);

    // 2) Mark that page as executable (ITLB filled with X=1)
    add_exec_page(32'h0800_4000);
    try_store(32'h0800_4010, "exec page blocks write", 1'b0);

    // 3) Pre-lock override window -> allow write just for boot-time updates
    allow_override_prelock = 1'b1;
    try_store(32'h0800_4020, "pre-lock override", 1'b1);

    // 4) After LOCK, override is ignored
    lock_i = 1'b1; @(posedge clk);
    try_store(32'h0800_4030, "post-lock must block", 1'b0);

    // 5) Flush (sfence.vma global) -> clears tracker -> allowed again
    clear_i = 1'b1; @(posedge clk); clear_i = 1'b0; @(posedge clk);
    try_store(32'h0800_4040, "after flush allowed", 1'b1);

    $display("All alias_guard tests passed.");
    $finish;
  end

endmodule
