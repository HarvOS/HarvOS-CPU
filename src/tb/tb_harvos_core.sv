
`timescale 1ns/1ps
`include "harvos_pkg_flat.svh"
`include "bus_if.sv"

module tb_harvos_core;
  logic clk=0, rst_n=0;
  always #5 clk = ~clk;

  harvos_imem_if imem(clk);
  
  // ----- Hoisted declarations for Yosys SV parser -----
  integer i;  // hoisted loop var from for(...) header
  integer i;  // hoisted loop var from for(...) header
  integer i;  // hoisted loop var from for(...) header

harvos_dmem_if dmem(clk);
  logic ext_irq;

  // Simple memories
  localparam int IMEM_WORDS = 1024;
  localparam int DMEM_WORDS = 2048;
  logic [31:0] IMEM[0:IMEM_WORDS-1];
  logic [31:0] DMEM[0:DMEM_WORDS-1];

    
    // Instruction ROM: program enabling all IRQs + SSIP self-trigger + trap logger
  initial begin
    for (i = 0;i<IMEM_WORDS;i++) IMEM[i]=32'h00000013; // NOP
    IMEM[0] = 32'h00400093;
    IMEM[1] = 32'h10509073;
    IMEM[2] = 32'h08000293;
    IMEM[3] = 32'h10129073;
    IMEM[4] = 32'h22200313;
    IMEM[5] = 32'h10631073;
    IMEM[6] = 32'h0C800413;
    IMEM[7] = 32'h18141073;
    IMEM[8] = 32'h000026B7;
    IMEM[9] = 32'h00200493;
    IMEM[10] = 32'h1074A073;
    IMEM[11] = 32'h00000073;
    IMEM[12] = 32'h0000006F;
    // sstatus.SIE=1 (reuse existing literal from prior TB)
    IMEM[6] = 32'h00100393; // addi x7,x0,1
    IMEM[7] = 32'h1003e073; // csrrs x0,sstatus,x7
    IMEM[32] = 32'h10202573;
    IMEM[33] = 32'h00450513;
    IMEM[34] = 32'h103025F3;
    IMEM[35] = 32'h00B6A023;
    IMEM[36] = 32'h00468693;
    IMEM[37] = 32'h10251073;
    IMEM[38] = 32'h0C840413;
    IMEM[39] = 32'h18141073;
    IMEM[40] = 32'h10200073;
    // Mirror program and trap to PA 0x1000 for post-paging fetch
    IMEM[16'h0400 + 0] = 32'h00400093;
    IMEM[16'h0400 + 1] = 32'h10509073;
    IMEM[16'h0400 + 2] = 32'h08000293;
    IMEM[16'h0400 + 3] = 32'h10129073;
    IMEM[16'h0400 + 4] = 32'h22200313;
    IMEM[16'h0400 + 5] = 32'h10631073;
    IMEM[16'h0400 + 6] = 32'h0C800413;
    IMEM[16'h0400 + 7] = 32'h18141073;
    IMEM[16'h0400 + 8] = 32'h000026B7;
    IMEM[16'h0400 + 9] = 32'h00200493;
    IMEM[16'h0400 + 10] = 32'h1074A073;
    IMEM[16'h0400 + 11] = 32'h00000073;
    IMEM[16'h0400 + 12] = 32'h0000006F;
    IMEM[16'h0400 + 32] = 32'h10202573;
    IMEM[16'h0400 + 33] = 32'h00450513;
    IMEM[16'h0400 + 34] = 32'h103025F3;
    IMEM[16'h0400 + 35] = 32'h00B6A023;
    IMEM[16'h0400 + 36] = 32'h00468693;
    IMEM[16'h0400 + 37] = 32'h10251073;
    IMEM[16'h0400 + 38] = 32'h0C840413;
    IMEM[16'h0400 + 39] = 32'h18141073;
    IMEM[16'h0400 + 40] = 32'h10200073;
  end




  // Data RAM and page tables
  // Root page-table at physical 0x00004000 (DMEM index 0x1000 >> 2 = 4096/4 = 1024)
  localparam PADDR_PGT_ROOT = 32'h00004000;
  localparam integer DMEM_BASE = 0; // start at 0 for simplicity

  // Fill DMEM with zeros
  initial begin
    for (i = 0; i < DMEM_WORDS; i++) DMEM[i]=32'h00000000;
  end

  
  // Page table entries (sv32):
  // Root at 0x00004000; L0 at 0x00005000
  // VA 0x00000000 -> PA 0x00001000 (RX, U=1)
  // VA 0x00002000 -> PA 0x00002000 (RW, U=1)
  initial begin
    // Root PTE for vpn1=0 → pointer to L0 table (V=1)
    DMEM[(PADDR_PGT_ROOT>>2) + 0] = { (PADDR_PGT_L0[31:12]), 10'h000, 8'b00000001 };
    // L0[0] — VA 0x00000000 → PA 0x00001000, R=1, W=0, X=1, U=1, V=1
    DMEM[(PADDR_PGT_L0>>2) + 0]   = { (32'h00001000[31:12]), 2'b00, 6'b00011011 };
    // L0[2] — VA 0x00002000 → PA 0x00002000, R=1, W=1, X=0, U=1, V=1
    DMEM[(PADDR_PGT_L0>>2) + 2]   = { (32'h00002000[31:12]), 2'b00, 6'b00001111 };
  end


  // Simple imem model
  assign imem.rdata  = IMEM[imem.addr[31:2]];
  assign imem.rvalid = imem.req;  // can change to add latency if needed
  assign imem.fault  = 1'b0;

  // Simple dmem model
  always_ff @(posedge clk) begin
    if (dmem.req) begin
      if (dmem.we) begin
        if (dmem.be[0]) DMEM[dmem.addr[31:2]][7:0]   <= dmem.wdata[7:0];
        if (dmem.be[1]) DMEM[dmem.addr[31:2]][15:8]  <= dmem.wdata[15:8];
        if (dmem.be[2]) DMEM[dmem.addr[31:2]][23:16] <= dmem.wdata[23:16];
        if (dmem.be[3]) DMEM[dmem.addr[31:2]][31:24] <= dmem.wdata[31:24];
      end
    end
  end
  
  // Add 3-cycle latency pipeline for data memory responses
  logic [2:0] rvalid_pipe;
  logic [31:0] rdata_pipe[2:0];
  always_ff @(posedge clk) begin
    rvalid_pipe <= {rvalid_pipe[1:0], dmem.req};
    rdata_pipe[0] <= DMEM[dmem.addr[31:2]];
    rdata_pipe[1] <= rdata_pipe[0];
    rdata_pipe[2] <= rdata_pipe[1];
  end
  assign dmem.rdata  = rdata_pipe[2];
  assign dmem.rvalid = rvalid_pipe[2];
  assign dmem.fault  = 1'b0;



  // MPU programming: region 0 = code (I-space, RX), region 1 = data (RW)
  logic        mpu_prog_en;
  logic [2:0]  mpu_prog_idx;
  logic [31:0] mpu_prog_base, mpu_prog_limit;
  logic [2:0]  mpu_prog_perm;  // {x,w,r}
  logic        mpu_prog_user_ok, mpu_prog_is_ispace;

  initial begin
    mpu_prog_en = 0;
    mpu_prog_idx = 0;
    mpu_prog_base = 32'h0; mpu_prog_limit = 32'h0;
    mpu_prog_perm = 3'b000; mpu_prog_user_ok = 1'b0; mpu_prog_is_ispace = 1'b0;
    @(posedge rst_n);
    // Program code region: PA 0x00001000..0x00001FFF, RX, user ok, is_ispace=1
    #10;
    mpu_prog_idx       = 3'd0;
    mpu_prog_base      = 32'h00001000;
    mpu_prog_limit     = 32'h00001FFF;
    mpu_prog_perm      = 3'b101; // X=1, W=0, R=1
    mpu_prog_user_ok   = 1'b1;
    mpu_prog_is_ispace = 1'b1;
    mpu_prog_en        = 1'b1;
    #10 mpu_prog_en     = 1'b0;

    // Program data region: PA 0x00002000..0x00002FFF, RW, no execute, data-space
    #20;
    mpu_prog_idx       = 3'd1;
    mpu_prog_base      = 32'h00002000;
    mpu_prog_limit     = 32'h00002FFF;
    mpu_prog_perm      = 3'b011; // X=0, W=1, R=1
    mpu_prog_user_ok   = 1'b1;
    mpu_prog_is_ispace = 1'b0;
    mpu_prog_en        = 1'b1;
    #10 mpu_prog_en     = 1'b0;
  end


  // DUT
  harvos_core dut (
    .clk(clk), .rst_n(rst_n),
    .imem(imem), .dmem(dmem),
    .entropy_valid(1'b0), .entropy_data(32'h0),
    .ext_irq(ext_irq),
    .mpu_prog_en(mpu_prog_en), .mpu_prog_idx(mpu_prog_idx),
    .mpu_prog_base(mpu_prog_base), .mpu_prog_limit(mpu_prog_limit),
    .mpu_prog_perm(mpu_prog_perm), .mpu_prog_user_ok(mpu_prog_user_ok), .mpu_prog_is_ispace(mpu_prog_is_ispace)
  );

  // CSR init sequence
  initial begin
    rst_n = 0;
    #50;
    rst_n = 1;

    // Program satp to enable paging (MODE implied) with root PPN
    // In a real system you'd write CSRs via instructions; here we poke internal signals or rely on defaults.
    // This minimal TB doesn't drive CSR writes; the core's CSR file defaults satp=0.
    // For demo purposes you can extend the TB to write CSRs through a tiny ROM program.
    #2000 $finish;
  end

endmodule

  // Benchmark: simple loop to exercise D$ — loads/stores to 0x2000
  // We keep the existing ROM program (it already stores/loads and traps). Here we just run longer.
  initial begin
    @(posedge rst_n);
    repeat (500) @(posedge clk);
    $display("[TB] Done. Dumping cache stats:");
    // I$ stats
    $display("  I$: hits=%0d, misses=%0d", dut.IC.stat_hits, dut.IC.stat_misses);
    // D$ stats
    $display("  D$: hits=%0d, misses=%0d", dut.DC.stat_hits, dut.DC.stat_misses);
    #10 $finish;
  end

  // External IRQ pulse after some time
  initial begin
    ext_irq = 1'b0;
    @(posedge rst_n);
    repeat (300) @(posedge clk);
    ext_irq = 1'b1;
    repeat (10) @(posedge clk);
    ext_irq = 1'b0;
  end

  // After runtime, dump interrupt log from DMEM[0x2000..]
  initial begin
    @(posedge rst_n);
    repeat (800) @(posedge clk);
    $display("[TB] Interrupt log (scause values) at VA 0x2000:");
    for for (i = 0;; i++) begin
      $display("  log[%0d] = 0x%08h", i, DMEM[(32'h00002000>>2) + i]);
    end
  end

  // Compliance mini-test: write bytes/halves and read back with LB/LBU/LH/LHU; shift ops and AUIPC
  initial begin
    @(posedge rst_n);
    // Preload some data into DMEM around 0x2000
    DMEM[(32'h00002000>>2)]     = 32'h80FF_7F01; // bytes: [01,7F,FF,80]
    DMEM[(32'h00002004>>2)]     = 32'h0000_ABCD;
  end
