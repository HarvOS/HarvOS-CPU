// SV-to-V2005 shim (auto-inserted)
`ifndef HARVOS_SV2V_SHIM
`define HARVOS_SV2V_SHIM
`ifndef FORMAL
`define logic wire
`define always_ff always
`define always_comb always @*
`define always_latch always @*
`define bit wire
`endif
`endif


module dcache_2way #(
  parameter integer LINE_BYTES = 32, // 8 words
  parameter integer SETS       = 32  // total lines = SETS * 2
) (
  input  logic        clk,
  input  logic        rst_n,

  // CPU side
  input  logic [1:0] way_mask_i,  // ASID-based way mask (1=enabled)
  input  logic        cpu_req,
  input  logic        cpu_we,
  input  logic [3:0]  cpu_be,
  input  logic [31:0] cpu_addr,
  input  logic [31:0] cpu_wdata,
  output wire [31:0] cpu_rdata,
  output wire cpu_done,
  output logic        cpu_fault,

  // Memory side
  output logic        mem_req,
  output logic        mem_we,
  output logic [3:0]  mem_be,
  output logic [31:0] mem_addr,
  output logic [31:0] mem_wdata,
  input  logic [31:0] mem_rdata,
  input  logic        mem_rvalid,
  input  logic        mem_fault,

  // Stats (debug)
  output wire [31:0] stat_hits,
  output wire [31:0] stat_misses
);
  
  
  // --- Minimal patch: keep ports as wires; drive via internal regs ---
  logic [31:0] stat_hits_q, stat_misses_q;
  assign stat_hits  = stat_hits_q;
  assign stat_misses = stat_misses_q;
  // --- End minimal patch ---
// ----- Hoisted declarations for Yosys SV parser -----
  integer s;  // hoisted loop var from for(...) header
  integer w;  // hoisted loop var from for(...) header

localparam integer WORDS_PER_LINE = LINE_BYTES/4;
  localparam integer OFFSET_BITS    = $clog2(LINE_BYTES);
  localparam integer INDEX_BITS     = $clog2(SETS);
  localparam integer TAG_BITS       = 32 - INDEX_BITS - OFFSET_BITS;

  typedef struct packed {
    logic                valid;
  logic [TAG_BITS-1:0] tag;
  } tag_s;
  logic tagv0_valid[SETS];  // flattened from tag_s tagv0_valid[SETS]
  logic [31:0] data0[SETS][WORDS_PER_LINE];
  logic [31:0] data1[SETS][WORDS_PER_LINE];

  logic tagv0_locked[SETS];  // flattened from tag_s tagv0_locked[SETS]

  logic [TAG_BITS-1:0] tagv0_tag[SETS];

  logic tagv1_valid[SETS];  // flattened from tag_s tagv1_valid[SETS]

  logic tagv1_locked[SETS];  // flattened from tag_s tagv1_locked[SETS]

  logic [TAG_BITS-1:0] tagv1_tag[SETS];
  // Write buffer (2 entries) to decouple stores; simple word-precision forwarding
  logic        wbuf_enq_valid, wbuf_enq_ready;
  logic [31:0] wbuf_enq_addr, wbuf_enq_wdata;
  logic [3:0]  wbuf_enq_wstrb;
  logic        wbuf_mem_valid;
  logic [31:0] wbuf_mem_addr, wbuf_mem_wdata;
  logic [3:0]  wbuf_mem_strb;
  logic        wbuf_fwd_req, wbuf_fwd_hit;
  logic [31:0] wbuf_fwd_addr, wbuf_fwd_data;
  wire         wbuf_mem_ready;

  // Selection tracking for write issue
  logic issuing_wbuf_q;

  // Registered CPU response
  logic        cpu_done_q;
  logic [31:0] cpu_rdata_q;
  assign cpu_done  = cpu_done_q;
  assign cpu_rdata = cpu_rdata_q;

  // Forward request addr
  assign wbuf_fwd_req  = cpu_req && !cpu_we;
  assign wbuf_fwd_addr = cpu_addr;

  dcache_wbuf #(.DEPTH(2)) u_wbuf (
    .clk(clk), .rst_n(rst_n),
    .enq_valid_i (wbuf_enq_valid),
    .enq_addr_i  (wbuf_enq_addr),
    .enq_wdata_i (wbuf_enq_wdata),
    .enq_wstrb_i (wbuf_enq_wstrb),
    .enq_ready_o (wbuf_enq_ready),
    .mem_valid_o (wbuf_mem_valid),
    .mem_addr_o  (wbuf_mem_addr),
    .mem_wdata_o (wbuf_mem_wdata),
    .mem_wstrb_o (wbuf_mem_strb),
    .mem_ready_i (wbuf_mem_ready),
    .fwd_req_i   (wbuf_fwd_req),
    .fwd_addr_i  (wbuf_fwd_addr),
    .fwd_hit_o   (wbuf_fwd_hit),
    .fwd_data_o  (wbuf_fwd_data)
  );
  logic        lru[SETS]; // 0 -> way0 is LRU; 1 -> way1 is LRU

  // Address breakdown
  wire [INDEX_BITS-1:0] index = cpu_addr[OFFSET_BITS +: INDEX_BITS];
  wire [TAG_BITS-1:0]   tag   = cpu_addr[OFFSET_BITS+INDEX_BITS +: TAG_BITS];
  wire [OFFSET_BITS-1:2] word_off = cpu_addr[OFFSET_BITS-1:2];

  // Hit detection
  wire hit0_raw = tagv0_valid[index] && (tagv0_tag[index] == tag);
  wire hit1_raw = tagv1_valid[index] && (tagv1_tag[index] == tag);
  wire hit0     = hit0_raw & way_mask_i[0];
  wire hit1     = hit1_raw & way_mask_i[1];
  wire hit      = hit0 | hit1;
  wire [31:0] hit_word = hit0 ? data0[index][word_off] : data1[index][word_off];

  // Victim choice (mask-aware)
  wire way0_ok = way_mask_i[0];
  wire way1_ok = way_mask_i[1];
  wire use_way0 = (~tagv0_valid[index] && way0_ok) ? 1'b1 :
                  (~tagv1_valid[index] && way1_ok) ? 1'b0 :
                  ( way0_ok && !way1_ok) ? 1'b1  :
                  (!way0_ok &&  way1_ok) ? 1'b0  :
                  (~lru[index]); // if way0 is LRU, replace way0

  // MSHR (1 outstanding)
  typedef struct packed {
    logic                   busy;
  logic                   target_way; // 0 or 1
    logic [INDEX_BITS-1:0]  set;
  logic [TAG_BITS-1:0]    tag;
  logic [$clog2(WORDS_PER_LINE)-1:0] fill_cnt;
  logic [OFFSET_BITS-1:2] req_word_off; // for early restart
  } mshr_s;

  mshr_s mshr_q, mshr_n;

  // FSM
  typedef enum logic [2:0] {IDLE, LOOK, HIT_LOAD, HIT_STORE_FWD, MISS_REFILL_REQ, MISS_REFILL_WAIT, MISS_STORE_FWD, WAIT_WBUF} state_e;
  state_e st_q, st_n;

  // Outputs default
  always_comb begin
    // removed comb assign to cpu_rdata
    // removed comb assign to cpu_done
    cpu_fault = 1'b0;

    mem_req   = 1'b0;
    mem_we    = 1'b0;
    mem_be    = 4'h0;
    mem_addr  = 32'h0;
    mem_wdata = 32'h0;

    // write buffer enqueue default
    wbuf_enq_valid = 1'b0;
    wbuf_enq_addr  = 32'h0;
    wbuf_enq_wdata = 32'h0;
    wbuf_enq_wstrb = 4'h0;

    st_n   = st_q;
    mshr_n = mshr_q;

    case (st_q)
      IDLE: begin
        if (cpu_req) st_n = LOOK;
      end
      LOOK: begin
        if (cpu_we) begin
          // STORE
          // enqueue to write buffer (write-through, no-allocate on miss). Update cache on hit separately (seq block updates data arrays).
          if (wbuf_enq_ready) begin
            wbuf_enq_valid = 1'b1;
            wbuf_enq_addr  = {cpu_addr[31:2],2'b00};
            wbuf_enq_wdata = cpu_wdata;
            wbuf_enq_wstrb = cpu_be;
            st_n = IDLE; // store completes immediately (done pulse in seq)
          end else begin
            st_n = WAIT_WBUF; // backpressure until space in write buffer
          end
        end else begin
          // LOAD
          if (hit) begin
            st_n = HIT_LOAD;
          end else begin
            // start refill
            mshr_n.busy        = 1'b1;
            mshr_n.target_way  = use_way0 ? 1'b0 : 1'b1;
            mshr_n.set         = index;
            mshr_n.tag         = tag;
            mshr_n.fill_cnt    = '0;
            mshr_n.req_word_off= word_off;
            mem_req  = 1'b1;
            mem_we   = 1'b0;
            mem_be   = 4'hF;
            mem_addr = {cpu_addr[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}}; // line base
            st_n     = MISS_REFILL_WAIT;
          end
        end
      end
      WAIT_WBUF: begin
        if (wbuf_enq_ready) begin
          wbuf_enq_valid = 1'b1;
          wbuf_enq_addr  = {cpu_addr[31:2],2'b00};
          wbuf_enq_wdata = cpu_wdata;
          wbuf_enq_wstrb = cpu_be;
          st_n = IDLE;
        end
      end
      HIT_LOAD: begin
        // removed comb assign to cpu_rdata
        // removed comb assign to cpu_done
        st_n      = IDLE;
      end
      HIT_STORE_FWD: begin
        if (mem_rvalid) begin
          // removed comb assign to cpu_done
          st_n     = IDLE;
        end
        cpu_fault = mem_fault;
      end
      MISS_REFILL_WAIT: begin
        // Early restart: as soon as requested word arrives, complete the CPU op
        if (mem_rvalid) begin
          // next word address
          if (mshr_q.fill_cnt == WORDS_PER_LINE-1) begin
            // line finished
            st_n = LOOK; // will now hit
          end else begin
            mem_req  = 1'b1;
            mem_addr = { {mshr_q.tag, mshr_q.set, {OFFSET_BITS{1'b0}} } } + { {(32-$clog2(LINE_BYTES)-2){1'b0}}, (mshr_q.fill_cnt+1), 2'b00 };
            st_n     = MISS_REFILL_WAIT;
          end
        end
        cpu_fault = mem_fault;
      end
      MISS_STORE_FWD: begin
        if (mem_rvalid) begin
          // removed comb assign to cpu_done
          st_n     = IDLE;
        end
        cpu_fault = mem_fault;
      end
    endcase

    // Allow write buffer to use memory port when not doing a line refill
    if (!(st_q == MISS_REFILL_WAIT && mshr_q.busy) && wbuf_mem_valid) begin
      mem_req  = 1'b1;
      mem_we   = 1'b1;
      mem_be   = wbuf_mem_strb;
      mem_addr = wbuf_mem_addr;
      mem_wdata= wbuf_mem_wdata;
    end
  end

  // Sequential logic
  always_ff @(posedge clk) begin
    // drive cpu_done/rdata registered
    if (!rst_n) begin
      cpu_done_q  <= 1'b0;
      cpu_rdata_q <= '0;
      issuing_wbuf_q <= 1'b0;
    
      st_q <= IDLE;
      mshr_q <= '0;
      stat_hits_q <= 32'h0; stat_misses_q <= 32'h0;
      for (s = 0; s<SETS; s++) begin
        tagv0_valid[s] <= 1'b0; tagv0_tag[s] <= '0;
        tagv1_valid[s] <= 1'b0; tagv1_tag[s] <= '0;
        lru[s] <= 1'b0;
        for (w = 0; w < WORDS_PER_LINE; w++) begin
          data0[s][w] <= 32'h0; data1[s][w] <= 32'h0;
        end
      end
    end else begin
      cpu_done_q  <= 1'b0;
      // store completes immediately when enqueued into write buffer
      if (wbuf_enq_valid && wbuf_enq_ready) begin
        cpu_done_q <= 1'b1;
      end
      if (st_q == HIT_LOAD) begin
        cpu_rdata_q <= hit_word;
        cpu_done_q  <= 1'b1;
      end
      if (st_q == MISS_REFILL_WAIT && mem_rvalid && !mem_fault) begin
        if (mshr_q.fill_cnt == mshr_q.req_word_off) begin
          cpu_rdata_q <= mem_rdata;
          cpu_done_q  <= 1'b1; // early restart
        end
      end
      if ((st_q == HIT_STORE_FWD || st_q == MISS_STORE_FWD) && mem_rvalid && !mem_fault) begin
        cpu_done_q <= 1'b1;
      end
      st_q   <= st_n;
      mshr_q <= mshr_n;

      // stats on LOOK stage
      if (st_q == LOOK) begin
        if (cpu_we) begin
          // don't count stores as hits/misses to keep signal clear; optional
        end else begin
          if (hit) stat_hits_q <= stat_hits_q + 1; else stat_misses_q <= stat_misses_q + 1;
        end
      end

      // Store hit update
      if (st_q == LOOK && cpu_we && hit) begin
        if (hit0) begin
          data0[index][word_off] <= ((data0[index][word_off]) & ~{ {8{cpu_be[3]}}, {8{cpu_be[2]}}, {8{cpu_be[1]}}, {8{cpu_be[0]}} }) | (({ cpu_wdata[31:24], cpu_wdata[23:16], cpu_wdata[15:8], cpu_wdata[7:0] }) & { {8{cpu_be[3]}}, {8{cpu_be[2]}}, {8{cpu_be[1]}}, {8{cpu_be[0]}} });
          lru[index] <= 1'b1; // way1 becomes LRU
        end else if (hit1) begin
          data1[index][word_off] <= ((data1[index][word_off]) & ~{ {8{cpu_be[3]}}, {8{cpu_be[2]}}, {8{cpu_be[1]}}, {8{cpu_be[0]}} }) | (({ cpu_wdata[31:24], cpu_wdata[23:16], cpu_wdata[15:8], cpu_wdata[7:0] }) & { {8{cpu_be[3]}}, {8{cpu_be[2]}}, {8{cpu_be[1]}}, {8{cpu_be[0]}} });
          lru[index] <= 1'b0; // way0 becomes LRU
        end
      end

      // Refill writes + early restart
      if (st_q == MISS_REFILL_WAIT && mem_rvalid && !mem_fault && mshr_q.busy) begin
        if (mshr_q.target_way == 1'b0) begin
          data0[mshr_q.set][mshr_q.fill_cnt] <= mem_rdata;
          if (mshr_q.fill_cnt == mshr_q.req_word_off) begin
            // early restart deliver
            cpu_rdata_q <= mem_rdata;
            cpu_done_q <= 1'b1; // will be sampled this cycle by core (single-cycle pulse)
          end
          if (mshr_q.fill_cnt == WORDS_PER_LINE-1) begin
            tagv0_valid[mshr_q.set] <= 1'b1;
            tagv0_tag[mshr_q.set]   <= mshr_q.tag;
            lru[mshr_q.set] <= 1'b1; // way1 becomes LRU
            mshr_q.busy <= 1'b0;
          end else begin
            mshr_q.fill_cnt <= mshr_q.fill_cnt + 1;
          end
        end else begin
          data1[mshr_q.set][mshr_q.fill_cnt] <= mem_rdata;
          if (mshr_q.fill_cnt == mshr_q.req_word_off) begin
            cpu_rdata_q <= mem_rdata;
            cpu_done_q <= 1'b1;
          end
          if (mshr_q.fill_cnt == WORDS_PER_LINE-1) begin
            tagv1_valid[mshr_q.set] <= 1'b1;
            tagv1_tag[mshr_q.set]   <= mshr_q.tag;
            lru[mshr_q.set] <= 1'b0; // way0 becomes LRU
            mshr_q.busy <= 1'b0;
          end else begin
            mshr_q.fill_cnt <= mshr_q.fill_cnt + 1;
          end
        end
      end
      // track when we issue a write from wbuf (for mem_ready)
      if (!(st_q == MISS_REFILL_WAIT && mshr_q.busy) && wbuf_mem_valid && !issuing_wbuf_q) begin
        issuing_wbuf_q <= 1'b1;
      end else if (mem_rvalid && issuing_wbuf_q) begin
        issuing_wbuf_q <= 1'b0;
      end
    end
  end
  // write buffer consumes mem_rvalid when its write is in flight
  assign wbuf_mem_ready = mem_rvalid && issuing_wbuf_q;
endmodule