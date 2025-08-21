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


`include "harvos_pkg_flat.svh"
`include "bus_if.sv"

// Minimal, synthesis-friendly icache with optional "lock" ports ignored.
// Acts as a 1-deep request buffer that forwards CPU fetches to the imem bus.
// No tags, no real locking; suitable to get synthesis unblocked.
module icache_lock #(
  parameter integer LINE_BYTES = 32,
  parameter integer LINES      = 64
) (
  input  logic                  clk,
  input  logic                  rst_n,

  // CPU side
  input  logic                  cpu_req,
  input  logic [31:0]           cpu_addr,   // physical
  // MPU says this fetch is allowed to execute
  input  logic                  mpu_exec_allow,
  output logic [31:0]           cpu_rdata,
  output logic                  cpu_rvalid,
  output logic                  cpu_fault,

  // Memory side (to external imem bus)
  harvos_imem_if.master         mem,

  // Optional line lock programming (debug / TB)
  input  logic                  lock_we,
  // Flush-all (FENCE.I)
  input  logic                  flush_all,
  input  logic [$clog2(LINES)-1:0] lock_index,
  input  logic                  lock_set,

  // Stats (debug only)
  output logic [31:0]           stat_hits,
  output logic [31:0]           stat_misses
);

  typedef enum logic [1:0] {IDLE, REQ, WAIT} state_e;
  state_e st_q, st_n;

  logic [31:0] addr_q;

  // default outputs
  always_comb begin
    mem.req    = 1'b0;
    mem.addr   = addr_q;
    cpu_rdata  = mem.rdata;
    cpu_rvalid = 1'b0;
    cpu_fault  = 1'b0;
    st_n       = st_q;

    case (st_q)
      IDLE: begin
        if (cpu_req) begin
          st_n   = REQ;
        end
      end
      REQ: begin
        mem.req = 1'b1;     // one-cycle pulse
        st_n    = WAIT;
      end
      WAIT: begin
        if (mem.rvalid) begin
          cpu_rvalid = 1'b1;
          // fault if MPU disallows exec
          if (!mpu_exec_allow) cpu_fault = 1'b1;
          st_n       = IDLE;
        end else if (mem.fault) begin
          cpu_fault = 1'b1;
          st_n      = IDLE;
        end
      end
      default: st_n = IDLE;
    endcase
  end

  // state & address registers
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st_q      <= IDLE;
      addr_q    <= 32'h0;
      stat_hits   <= 32'h0;
      stat_misses <= 32'h0;
    end else begin
      st_q <= st_n;
      if (cpu_req && st_q == IDLE) begin
        addr_q <= cpu_addr & 32'hFFFF_FFFC; // align to word
      end
      // stats: simplistic (count all as misses)
      if (cpu_req && st_q == IDLE) begin
        stat_misses <= stat_misses + 1;
      end
      // ignore lock_we/lock_index/lock_set; ignore flush_all
    end
  end

endmodule
