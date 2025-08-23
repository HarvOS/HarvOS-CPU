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


// Direct-mapped D-Cache with 4-word lines, write-through, write-allocate,
// early restart for loads (delivers requested word as soon as it arrives).
module dcache #(
  parameter integer LINES = 64,          // number of cache lines (power of 2)
  parameter integer LINE_WORDS = 4       // words per line (fixed to 4 for 16B lines)
) (
  input  logic        clk,
  input  logic        rst_n,

  // CPU side (single-request handshake)
  input  logic        cpu_req,       // pulse to start an access
  input  logic        cpu_we,        // 0=load, 1=store
  input  logic [3:0]  cpu_be,        // byte enables for store
  input  logic [31:0] cpu_addr,
  input  logic [31:0] cpu_wdata,
  output logic [31:0] cpu_rdata,
  output logic        cpu_done,      // 1 when the access (load/store) has completed
  input  logic        inv_all,
  output logic        inv_ack,
  output logic        cpu_fault,     // propagated from memory on refill/forward
  // Security: cache control
  input  logic          inv_all,


  // Memory side (to arbiter m0)
  output logic        mem_req,
  output logic        mem_we,
  output logic [3:0]  mem_be,
  output logic [31:0] mem_addr,
  output logic [31:0] mem_wdata,
  input  logic [31:0] mem_rdata,
  input  logic        mem_rvalid,
  input  logic        mem_fault
);
  
    logic [31:0] data[LINES][LINE_WORDS];
// ----- Hoisted declarations for Yosys SV parser -----
  integer i;  // hoisted loop var from for(...) header
  integer w;  // hoisted loop var from for(...) header

  // Flush handshake
  logic inv_seen_q;

// -------- Address decomposition --------
  localparam integer LINE_BITS = $clog2(LINES);
  localparam integer WORD_BITS = $clog2(LINE_WORDS); // 2 for 4 words
  localparam integer OFF_BITS  = 2 + WORD_BITS;      
  localparam integer TAG_BITS       = 32 - LINE_BITS - OFF_BITS;
// byte(2) + word offset

  wire [LINE_BITS-1:0] index_w    = cpu_addr[2 + WORD_BITS +: LINE_BITS];
  wire [WORD_BITS-1:0] word_off_w = cpu_addr[2 +: WORD_BITS];
  wire [TAG_BITS-1:0] tag_w = cpu_addr[31 : (2+WORD_BITS+LINE_BITS)];

  // -------- Line storage --------
  typedef struct packed {
    logic                                valid;
  logic [TAG_BITS-1:0]      tag;
  } tagv_s;
  logic tagv_valid[LINES];  // flattened from tagv_s tagv_valid[LINES]

  logic [TAG_BITS-1:0] tagv_tag[LINES];

  // -------- FSM --------
  typedef enum logic [2:0] {IDLE, LOOK, REFILL, WRITE_THROUGH} st_e;
  st_e st_q, st_n;

  // latched request
  logic        req_we_q;
  logic [3:0]  req_be_q;
  logic [31:0] req_addr_q, req_wdata_q;
  logic [LINE_BITS-1:0] req_index_q;
  logic [WORD_BITS-1:0] req_word_off_q;
  logic [TAG_BITS-1:0] req_tag_q;

  // refill machinery
  logic [WORD_BITS-1:0] rf_cnt_q, rf_cnt_n;  // which word of the line we are fetching
  logic                  rf_pending_q, rf_pending_n;
  logic [31:0]           line_base_addr;     // line-aligned

  // hit detection (combinational for LOOK)
  wire hit_now = tagv_valid[index_w] && (tagv_tag[index_w] == tag_w);

  // outputs default
    // SV-to-Verilog friendly temps for store byte-mask merge
  logic [31:0] be_mask_w;
  logic [31:0] store_merge_w;

always_comb begin
    mem_req   = 1'b0;
    mem_we    = 1'b0;
    mem_be    = 4'h0;
    mem_addr  = 32'h0;
    mem_wdata = 32'h0;

    cpu_done  = 1'b0;
    cpu_fault = 1'b0;
    cpu_rdata = 32'h0;
    // defaults for mask/merge
    be_mask_w = { {8{cpu_be[3]}}, {8{cpu_be[2]}}, {8{cpu_be[1]}}, {8{cpu_be[0]}} };
    store_merge_w = data[index_w][word_off_w];

    rf_cnt_n      = rf_cnt_q;
    rf_pending_n  = rf_pending_q;

    st_n = st_q;

    case (st_q)
      IDLE: begin
        if (cpu_req) begin
          st_n = LOOK;
        end
      end

      LOOK: begin
        if (hit_now) begin
          // ---- HIT ----
          if (!cpu_we) begin
            // load
            cpu_rdata = data[index_w][word_off_w];
            cpu_done  = 1'b1;
            st_n      = IDLE;
          end else begin
            // store: update cached word and write-through
            // store byte-enable merge done combinationally
            store_merge_w = (data[index_w][word_off_w] & ~be_mask_w) | (cpu_wdata & be_mask_w);

            // Write-through to memory
            mem_req   = 1'b1;
            mem_we    = 1'b1;
            mem_be    = cpu_be;
            mem_addr  = cpu_addr;
            mem_wdata = cpu_wdata;
            st_n      = WRITE_THROUGH;

            // Update cache line immediately
            // Note: do actual write in seq block to avoid write-after-read hazards
          end
        end else begin
          // ---- MISS ----
          // Latch request and start burst refill of the whole line
          st_n = REFILL;

          // Issue first read if not pending
          if (!rf_pending_q) begin
            mem_req   = 1'b1;
            mem_we    = 1'b0;
            mem_be    = 4'hF;
            mem_addr  = {cpu_addr[31:OFF_BITS], {OFF_BITS{1'b0}}}; // base of the line
          end
        end
      end

      REFILL: begin
        // While refilling, we drive mem_req to fetch next word whenever not pending
        if (!rf_pending_q && (rf_cnt_q < LINE_WORDS)) begin
          mem_req  = 1'b1;
          mem_we   = 1'b0;
          mem_be   = 4'hF;
          mem_addr = line_base_addr + { {30-WORD_BITS{1'b0}}, rf_cnt_q, 2'b00 };
        end

        // Early restart: when the requested word arrives, we can complete a LOAD
        if (mem_rvalid || mem_fault) begin
          if (mem_fault) begin
            cpu_fault = 1'b1;
            cpu_done  = (req_we_q==1'b0); // for stores we still need to write-through; choose to fail early on read
            st_n      = IDLE;
          end else begin
            // Early restart condition
            if (!req_we_q && (rf_cnt_q == req_word_off_q)) begin
              cpu_rdata = mem_rdata;
              cpu_done  = 1'b1;
            end
            // For store-miss: we will update the word in seq block when its beat arrives, and after refill ends we write-through.
          end
        end

        // When all words fetched, either finish (load) or go write-through (store)
        if ((rf_cnt_q == LINE_WORDS) && !rf_pending_q) begin
          if (req_we_q) begin
            // Perform write-through now with original request
            mem_req   = 1'b1;
            mem_we    = 1'b1;
            mem_be    = req_be_q;
            mem_addr  = req_addr_q;
            mem_wdata = req_wdata_q;
            st_n      = WRITE_THROUGH;
          end else begin
            st_n = IDLE;
          end
        end
      end

      WRITE_THROUGH: begin
        // wait for ack/fault (some fabrics assert rvalid also for writes)
        if (mem_rvalid || mem_fault) begin
          cpu_fault = mem_fault;
          cpu_done  = 1'b1;
          st_n      = IDLE;
        end
      end

      default: st_n = IDLE;
    endcase
  end

  // sequential: requests/refill bookkeeping and data array writes
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st_q <= IDLE;
      rf_cnt_q <= '0;
      rf_pending_q <= 1'b0;

      for (i = 0;i<LINES;i++) begin
        tagv_valid[i] <= 1'b0;
        tagv_tag[i]   <= '0;
        for (w = 0; w < LINE_WORDS; w++) data[i][w] <= 32'h0;
      end
    
      inv_seen_q <= 1'b0;
      inv_ack    <= 1'b0;
end else begin
      // Flush-ack: pulse one cycle after consuming inv_all
      inv_seen_q <= inv_all;
      inv_ack    <= inv_seen_q;

      // Invalidate-all on inv_all
      if (inv_all) begin
        integer k;
        for (k=0;k<LINES;k=k+1) begin
          tagv_valid[k] <= 1'b0;
        end
      end

      st_q <= st_n;
      rf_cnt_q <= rf_cnt_n;
      rf_pending_q <= rf_pending_n;

      // Latch request at the start (IDLE→LOOK)
      if (st_q==IDLE && st_n==LOOK) begin
        req_we_q       <= cpu_we;
        req_be_q       <= cpu_be;
        req_addr_q     <= cpu_addr;
        req_wdata_q    <= cpu_wdata;
        req_index_q    <= index_w;
        req_word_off_q <= word_off_w;
        req_tag_q      <= tag_w;
        line_base_addr <= {cpu_addr[31:OFF_BITS], {OFF_BITS{1'b0}}};
      end

      // Transition LOOK→REFILL: set up first beat
      if (st_q==LOOK && st_n==REFILL) begin
        rf_cnt_q     <= '0;
        rf_pending_q <= 1'b1; // first request issued in comb
      end

      // Issue → pending
      if (st_q==REFILL && !rf_pending_q && (rf_cnt_q < LINE_WORDS) && mem_req) begin
        rf_pending_q <= 1'b1;
      end

      // Accept a refill beat
      if (st_q==REFILL && rf_pending_q && (mem_rvalid || mem_fault)) begin
        rf_pending_q <= 1'b0;
        if (!mem_fault) begin
          // write beat into cache
          data[req_index_q][rf_cnt_q] <= mem_rdata;

          // on store-miss, when requested word arrives, merge store into cached word
          if (req_we_q && (rf_cnt_q == req_word_off_q)) begin
            data[req_index_q][rf_cnt_q] <= ((mem_rdata) & ~{ {8{req_be_q[3]}}, {8{req_be_q[2]}}, {8{req_be_q[1]}}, {8{req_be_q[0]}} }) | (({ req_wdata_q[31:24], req_wdata_q[23:16], req_wdata_q[15:8], req_wdata_q[7:0] }) & { {8{req_be_q[3]}}, {8{req_be_q[2]}}, {8{req_be_q[1]}}, {8{req_be_q[0]}} });
          end

          rf_cnt_q <= rf_cnt_q + 1'b1;

          // After last beat, mark line valid and tag
          if (rf_cnt_q == LINE_WORDS-1) begin
            tagv_tag[req_index_q]   <= req_tag_q;
            tagv_valid[req_index_q] <= 1'b1;
          end
        end else begin
          // fault on refill: invalidate line
          tagv_valid[req_index_q] <= 1'b0;
          rf_cnt_q <= LINE_WORDS; // allow comb to progress to WT/IDLE
        end
      end

      // Update cached word on store-hit (done after LOOK comb)
      if (st_q==LOOK && st_n==WRITE_THROUGH && hit_now && cpu_we) begin
        data[index_w][word_off_w] <= store_merge_w;
        // tag/valid unchanged
      end
    end
  end
endmodule