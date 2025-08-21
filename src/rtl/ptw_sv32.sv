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

`ifndef __YOSYS_ASSERT_STUBS__
`define __YOSYS_ASSERT_STUBS__ 1
`ifndef ASSERT_IMP
`define ASSERT_IMP(name, expr)
`endif
`ifndef ASSERT_NEVER
`define ASSERT_NEVER(name, expr)
`endif
`endif


`include "harvos_pkg_flat.svh"
module ptw_sv32 (
  input  logic              clk,
  input  logic              rst_n,
  // control
  input  logic              start,
  input  [31:0]             satp,       // MODE assumed enabled externally; satp[21:0]=PPN (Sv32)
  input  priv_e cur_priv,
  input  acc_e  acc,        // ACC_FETCH/LOAD/STORE
  input  [31:0]             vaddr,
  output logic              busy,
  output logic              done,
  output logic              fault,

  // result
  output logic [21:0]       res_ppn,
  output logic              res_r,
  output logic              res_w,
  output logic              res_x,
  output logic              res_u,
  output logic              res_g,

  // memory interface (read-only)
  output logic              mem_req,
  output logic [31:0]       mem_addr,
  input  logic [31:0]       mem_rdata,
  input  logic              mem_rvalid,
  input  logic              mem_fault
);

  // ---------- Helpers ----------
  function automatic void decode_pte(input logic [31:0] pte,
                                     output logic V,R,W,X,U,G,A,D,
                                     output logic [21:0] PPN);
    begin
      V   = pte[0];
      R   = pte[1];
      W   = pte[2];
      X   = pte[3];
      U   = pte[4];
      G   = pte[5];
      A   = pte[6];
      D   = pte[7];
      PPN = pte[31:10];
    end
  endfunction

  // ---------- State ----------
  typedef enum logic [2:0] {IDLE, READ_L1, READ_L0, FINISH, FAIL} st_e;
  st_e st_q, st_n;

  // Latched inputs
  logic [31:0] vaddr_q;
  logic [21:0] root_ppn;
  logic [9:0]  vpn1, vpn0;

  // Decode fields from vaddr (Sv32)
  wire [9:0] vpn1_w = vaddr_q[31:22];
  wire [9:0] vpn0_w = vaddr_q[21:12];

  // L1 / L0 PTE fields
  logic V1,R1,W1,X1,U1,G1,A1,D1;
  logic V0,R0,W0,X0,U0,G0,A0,D0;
  logic [21:0] PPN1, PPN0;

  // internal handshake to memory
  logic issue, pending;

  // Outputs
  assign busy  = (st_q != IDLE) && (st_q != FINISH) && (st_q != FAIL);
  assign done  = (st_q == FINISH);
  assign fault = (st_q == FAIL);

  // Memory address for current level
  always_comb begin
    mem_addr = 32'h0;
    case (st_q)
      READ_L1: mem_addr = {root_ppn, 12'h000} + {22'h0, vpn1_w, 2'b00};
      READ_L0: mem_addr = {PPN1,     12'h000} + {22'h0, vpn0_w, 2'b00};
      default: mem_addr = 32'h0;
    endcase
  end

  // Memory request: pulse 'mem_req' when (issue) asserted; simple one-beat protocol
  assign mem_req = issue;

  // Sequencing registers
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st_q    <= IDLE;
      vaddr_q <= 32'h0;
      root_ppn<= 22'h0;
      pending <= 1'b0;
      // clear outputs
      res_ppn <= 22'h0;
      res_r   <= 1'b0; res_w <= 1'b0; res_x <= 1'b0; res_u <= 1'b0; res_g <= 1'b0;
      // clear cached PTE fields
      V1<=0; R1<=0; W1<=0; X1<=0; U1<=0; G1<=0; A1<=0; D1<=0; PPN1<='0;
      V0<=0; R0<=0; W0<=0; X0<=0; U0<=0; G0<=0; A0<=0; D0<=0; PPN0<='0;
    end else begin
      st_q <= st_n;

      // Accept a issued request
      if (issue) begin
        pending <= 1'b1;
      end
      // Complete read
      if (pending && (mem_rvalid || mem_fault)) begin
        pending <= 1'b0;
        if (st_q == READ_L1 && mem_rvalid && !mem_fault) begin
          decode_pte(mem_rdata, V1,R1,W1,X1,U1,G1,A1,D1, PPN1);
        end
        if (st_q == READ_L0 && mem_rvalid && !mem_fault) begin
          decode_pte(mem_rdata, V0,R0,W0,X0,U0,G0,A0,D0, PPN0);
        end
      end

      // Latch inputs on start
      if (start && st_q == IDLE) begin
        vaddr_q  <= vaddr;
        root_ppn <= satp[21:0];
      end
    end
  end

  // Next-state logic and result composition
  logic leaf_l1, leaf_l0;
  assign leaf_l1 = (V1 && (R1 || X1)); // Sv32: leaf at level 1 if R or X set
  assign leaf_l0 = (V0 && (R0 || X0)); // Sv32: leaf at level 0 if R or X set

  // Basic illegal encodings: W implies R (RISC-V spec)
  function automatic logic w_implies_r(input logic R, input logic W);
    w_implies_r = (W && !R) ? 1'b1 : 1'b0;
  endfunction

  // Compose final perms with basic privilege filter (no SUM/MXR modeled here)
  task automatic set_result(input logic R, input logic W, input logic X,
                            input logic U, input logic G,
                            input logic [21:0] PPN, input logic l1_superpage);
    begin
      // Superpage (L1 leaf): lower PPN part comes from VPN0
      if (l1_superpage) begin
        res_ppn = { PPN[21:10], vpn0_w }; // PPN1 from PTE, PPN0 from VA
      end else begin
        res_ppn = PPN;
      end
      // Privilege: U pages only accessible in U; S can access both (no SUM modeled)
      if (cur_priv == PRIV_U && !U) begin
        res_r = 1'b0; res_w = 1'b0; res_x = 1'b0; res_u = U; res_g = G;
      end else begin
        res_r = R; res_w = W; res_x = X; res_u = U; res_g = G;
      end
    end
  endtask

  always_comb begin
    st_n  = st_q;
    issue = 1'b0;

    case (st_q)
      IDLE: begin
        if (start) begin
          st_n  = READ_L1;
          issue = 1'b1; // read root[vpn1]
        end
      end

      READ_L1: begin
        // Wait for memory response
        if (!pending && mem_rvalid) begin
          // Decode has happened in seq block
          // Check legal PTE
          if (!V1 || w_implies_r(R1,W1)) begin
            st_n = FAIL;
          end else if (leaf_l1) begin
            // A/D enforcement: if A==0 or (STORE && D==0) -> software-managed fault
            if (!A1 || (acc==ACC_STORE && !D1)) begin
              st_n = FAIL;
            end else begin
              // Leaf at L1 (superpage): finish if perms allow this access
              set_result(R1,W1,X1,U1,G1,PPN1, /*l1_superpage=*/1'b1);
              st_n = FINISH;
            end
          end else begin
            // Pointer to next level: kick READ_L0
            st_n  = READ_L0;
            issue = 1'b1;
          end
        end else if (!pending && mem_fault) begin
          st_n = FAIL;
        end
      end

      READ_L0: begin
        if (!pending && mem_rvalid) begin
          if (!V0 || w_implies_r(R0,W0)) begin
            st_n = FAIL;
          end else if (leaf_l0) begin
            // A/D enforcement at L0
            if (!A0 || (acc==ACC_STORE && !D0)) begin
              st_n = FAIL;
            end else begin
              set_result(R0,W0,X0,U0,G0,PPN0, /*l1_superpage=*/1'b0);
              st_n = FINISH;
            end
          end else begin
            // Non-leaf at L0 is illegal
            st_n = FAIL;
          end
        end else if (!pending && mem_fault) begin
          st_n = FAIL;
        end
      end

      FINISH: begin
        // Hold one cycle; upstream will sample 'done'
        if (!start) st_n = IDLE;
      end

      FAIL: begin
        if (!start) st_n = IDLE;
      end

      default: st_n = IDLE;
    endcase
  end

  // ---------- Optional Assertions (enable with +define+HARVOS_ASSERT) ----------
`ifdef HARVOS_ASSERT
  // W implies R (checked at both levels)
  property w_implies_r_l1;
    @(posedge clk) disable iff (!rst_n)
      (st_q==READ_L1 && !pending && mem_rvalid) |-> (!w_implies_r(R1,W1));
  endproperty
// yosys: assertion stripped:   assert property (w_implies_r_l1);
  property w_implies_r_l0;
    @(posedge clk) disable iff (!rst_n)
      (st_q==READ_L0 && !pending && mem_rvalid) |-> (!w_implies_r(R0,W0));
  endproperty
// yosys: assertion stripped:   assert property (w_implies_r_l0);
`endif

endmodule