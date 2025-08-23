
// mmu_sv32.sv — Milestone 7: simple TLB + PTW integration (Sv32), MXR/SUM, W^X, SFENCE
// Verilog-2005 compatible (no typedef/logic/always_ff).
// Notes: Simplified PTW (Sv32 2-level), supports leaf at L1/L0, minimal checks.
// Enforces: Paging-on, W^X (mask X if W=1), D-path NX (by policy), MXR/SUM, selective SFENCE.
//
// Ports must match harvos_core u_mmu instance.
module mmu_sv32 (
  input  wire         clk,
  input  wire         rst,
  input  wire         rst_n,

  // IF side
  input  wire [31:0]  if_vaddr,
  input  wire         if_req,
  output wire [31:0]  if_paddr,
  output wire         if_ready,
  output wire         if_fault,
  output wire         if_perm_x,

  // D side
  input  wire [31:0]  d_vaddr,
  input  wire         d_req,
  input  wire [1:0]   d_acc,       // 00=LOAD, 01=STORE
  output wire [31:0]  d_paddr,
  output wire         d_ready,
  output wire         d_fault,
  output wire         d_perm_r,
  output wire         d_perm_w,
  output wire         d_perm_x,

  // CSR
  input  wire [31:0]  csr_satp_q,
  input  wire [31:0]  csr_sstatus_q,
  input  wire [1:0]   cur_priv,

  // SFENCE interface
  input  wire         sfence_flush_all,
  input  wire [31:0]  sfence_vaddr,
  input  wire         sfence_addr_valid,
  input  wire [15:0]  sfence_asid,
  input  wire         sfence_asid_valid,

  // PTW interface
  output reg          ptw_req,
  output reg  [31:0]  ptw_addr,
  input  wire [31:0]  ptw_rdata,
  input  wire         ptw_rvalid,
  input  wire         ptw_fault
);

  // Combined reset (sync logic)
  wire rst_i = rst | ~rst_n;

  // ===== Sv32 fields =====
  // satp: MODE [31:30], ASID (implementation-defined width; we capture 16b), PPN [21:0]
  wire [1:0]  satp_mode = csr_satp_q[31:30];
  wire [15:0] satp_asid = csr_satp_q[29:14];  // widened for compatibility
  wire [21:0] satp_ppn  = csr_satp_q[21:0];
  wire        mode_bare = (satp_mode == 2'b00);

  // vaddr split
  function [9:0] vpn1; input [31:0] v; begin vpn1 = v[31:22]; end endfunction
  function [9:0] vpn0; input [31:0] v; begin vpn0 = v[21:12]; end endfunction
  wire [11:0] page_off_if = if_vaddr[11:0];
  wire [11:0] page_off_d  = d_vaddr[11:0];

  // ===== TLB (direct-mapped, 16 entries each for IF/D) =====
  localparam TLB_ENTRIES = 16;
  localparam TLB_IDXW    = 4;

  function [TLB_IDXW-1:0] tlb_index; input [31:0] v; begin
    tlb_index = v[15:12] ^ v[19:16]; // simple hash of VPN0/1 bits
  end endfunction

  // TLB arrays: one per channel
  reg               itlb_v    [0:TLB_ENTRIES-1];
  reg [15:0]        itlb_asid [0:TLB_ENTRIES-1];
  reg [19:0]        itlb_vpn  [0:TLB_ENTRIES-1]; // {vpn1,vpn0}
  reg [21:0]        itlb_ppn  [0:TLB_ENTRIES-1]; // PPN from leaf

  // ---- HarvOS Harvard-Alias invariant (inline CAM of exec PPNs) ----
  reg [19:0] exec_ppn_cam [0:15];
  reg        exec_ppn_v   [0:15];
  reg [3:0]  exec_wr_ptr;
  reg               itlb_p_r  [0:TLB_ENTRIES-1];
  reg               itlb_p_w  [0:TLB_ENTRIES-1];
  reg               itlb_p_x  [0:TLB_ENTRIES-1];
  reg               itlb_p_u  [0:TLB_ENTRIES-1];
  reg               itlb_p_a  [0:TLB_ENTRIES-1];
  reg               itlb_p_d  [0:TLB_ENTRIES-1];

  reg               dtlb_v    [0:TLB_ENTRIES-1];
  reg [15:0]        dtlb_asid [0:TLB_ENTRIES-1];
  reg [19:0]        dtlb_vpn  [0:TLB_ENTRIES-1];
  reg [21:0]        dtlb_ppn  [0:TLB_ENTRIES-1];
  reg               dtlb_p_r  [0:TLB_ENTRIES-1];
  reg               dtlb_p_w  [0:TLB_ENTRIES-1];
  reg               dtlb_p_x  [0:TLB_ENTRIES-1];
  reg               dtlb_p_u  [0:TLB_ENTRIES-1];
  reg               dtlb_p_a  [0:TLB_ENTRIES-1];
  reg               dtlb_p_d  [0:TLB_ENTRIES-1];

`ifndef SYNTHESIS
  // ---- Whitepaper invariants (runtime checks) ----
  genvar gi;
  generate
    for (gi=0; gi<TLB_ENTRIES; gi=gi+1) begin: G_INV
      // No page may be both writable and executable in TLB
      assert (!(itlb_p_w[gi] && itlb_p_x[gi])) else $error("W^X violated in ITLB at %0d", gi);
      assert (!(dtlb_p_w[gi] && dtlb_p_x[gi])) else $error("W^X violated in DTLB at %0d", gi);
    end
  endgenerate
`endif


  // ===== SUM / MXR =====
  localparam SSTATUS_SUM_BIT = 18;
  localparam SSTATUS_MXR_BIT = 19;
  wire sstatus_sum = csr_sstatus_q[SSTATUS_SUM_BIT];
  wire sstatus_mxr = csr_sstatus_q[SSTATUS_MXR_BIT];

  // Privilege decode
  wire is_u = (cur_priv == 2'b00);
  wire is_s = (cur_priv == 2'b01);

  // ===== Lookup =====
  wire [3:0] itlb_idx = tlb_index(if_vaddr);
  wire [3:0] dtlb_idx = tlb_index(d_vaddr);

  wire        itlb_hit = itlb_v[itlb_idx] && (itlb_asid[itlb_idx] == satp_asid) && (itlb_vpn[itlb_idx] == {vpn1(if_vaddr), vpn0(if_vaddr)});
  wire        dtlb_hit = dtlb_v[dtlb_idx] && (dtlb_asid[dtlb_idx] == satp_asid) && (dtlb_vpn[dtlb_idx] == {vpn1(d_vaddr), vpn0(d_vaddr)});

  wire [31:0] itlb_paddr = {itlb_ppn[itlb_idx], page_off_if};
  wire [31:0] dtlb_paddr = {dtlb_ppn[dtlb_idx], page_off_d};

  // ===== Permissions (from TLB) =====
  // IF
  wire itlb_perm_x = itlb_p_x[itlb_idx];
  wire itlb_perm_u = itlb_p_u[itlb_idx];
  // D
  wire dtlb_perm_r = dtlb_p_r[dtlb_idx] | (sstatus_mxr & itlb_p_x[dtlb_idx]); // MXR: X==R for loads
  wire dtlb_perm_w = dtlb_p_w[dtlb_idx];
  wire dtlb_perm_x = 1'b0; // D path NX by policy
  // A/D bits
  wire itlb_perm_a = itlb_p_a[itlb_idx];
  wire dtlb_perm_a = dtlb_p_a[dtlb_idx];
  wire dtlb_perm_d = dtlb_p_d[dtlb_idx];

  // U/S checks
  wire if_u_ok = is_u ? itlb_perm_u : 1'b1; // S can execute from U or S (conservative)
  wire d_u_ok  = is_u ? dtlb_p_u[dtlb_idx] : (dtlb_p_u[dtlb_idx] ? sstatus_sum : 1'b1); // S needs SUM for U pages

  // ===== Ready / Fault logic =====
  // Miss/walk handling FSM (shared, IF prio)
  localparam W_IDLE=2'd0, W_L1=2'd1, W_L0=2'd2, W_DONE=2'd3;
  reg [1:0]  w_state;
  reg        w_is_if;         // 1==IF walk, 0==D walk
  reg [31:0] w_vaddr;
  reg [9:0]  w_vpn1, w_vpn0;
  reg [21:0] w_ppn_l1;
  reg        w_valid_resp;    // a fill happened this cycle
  reg        w_fault;

  // default outputs
  assign if_ready = ~mode_bare & (w_state==W_IDLE);
  assign d_ready  = ~mode_bare & (w_state==W_IDLE);

  // paddr mux: if hit use TLB, else pass VA (don't care until hit)
  assign if_paddr = itlb_hit ? itlb_paddr : {itlb_paddr[31:12], page_off_if};
  assign d_paddr  = dtlb_hit ? dtlb_paddr : {dtlb_paddr[31:12], page_off_d};

  // perm outputs
  assign if_perm_x = ~mode_bare & itlb_hit & itlb_perm_x & if_u_ok & itlb_perm_a;
  assign d_perm_r  = ~mode_bare & dtlb_hit & dtlb_perm_r & d_u_ok & dtlb_perm_a & (d_acc==2'b00);
  assign d_perm_w  = ~mode_bare & dtlb_hit & dtlb_perm_w & d_u_ok & dtlb_perm_a & dtlb_perm_d & (d_acc==2'b01);
  assign d_perm_x  = 1'b0;


  // Exec-hit for D-side physical address
  wire [19:0] d_ppn = d_paddr[31:12];
  reg exec_hit;
  integer j;
  always @* begin
    exec_hit = 1'b0;
    for (j=0;j<16;j=j+1) begin
      if (exec_ppn_v[j] && exec_ppn_cam[j]==d_ppn) exec_hit = 1'b1;
    end
  end

  // faults
  wire if_fault_perm = itlb_hit & (~(itlb_perm_x & if_u_ok & itlb_perm_a));
  wire d_fault_perm  = dtlb_hit & (
    ~d_u_ok |
    ((d_acc==2'b00) & ~(dtlb_perm_r & dtlb_perm_a)) |
    ((d_acc==2'b01) & ~(dtlb_perm_w & dtlb_perm_a & dtlb_perm_d))
  );

  // Harvard D-path trap window (parameterized; optional, can be replaced by MPU)
  parameter [31:0] I_SPACE_BASE = 32'h0000_0000;
  parameter [31:0] I_SPACE_END  = 32'h000F_FFFF;
  function [0:0] is_in_ispace; input [31:0] paddr; begin
    is_in_ispace = (paddr >= I_SPACE_BASE) && (paddr <= I_SPACE_END);
  end endfunction
  wire d_harvard_fault = dtlb_hit & d_req & is_in_ispace(d_paddr);

  assign if_fault = mode_bare ? if_req : (if_req & ( (~itlb_hit) ? 1'b0 : if_fault_perm ));
  assign d_fault  = mode_bare ? d_req  : (d_req  & ( (~dtlb_hit) ? 1'b0 : (d_fault_perm | d_harvard_fault | (dtlb_hit & d_req & (d_acc==2'b01) & exec_hit)) ));

  // ===== PTW walk =====
  // Compute PTE addresses
  function [31:0] pte_addr_l1; input [21:0] root_ppn; input [9:0] vpn1_i;
    begin pte_addr_l1 = {root_ppn, 12'b0} + {vpn1_i, 2'b00}; end
  endfunction
  function [31:0] pte_addr_l0; input [21:0] parent_ppn; input [9:0] vpn0_i;
    begin pte_addr_l0 = {parent_ppn, 12'b0} + {vpn0_i, 2'b00}; end
  endfunction

  // PTE decode helpers
  function [0:0] pte_v; input [31:0] p; begin pte_v = p[0]; end endfunction
  function [0:0] pte_r; input [31:0] p; begin pte_r = p[1]; end endfunction
  function [0:0] pte_w; input [31:0] p; begin pte_w = p[2]; end endfunction
  function [0:0] pte_x; input [31:0] p; begin pte_x = p[3]; end endfunction
  function [0:0] pte_u; input [31:0] p; begin pte_u = p[4]; end endfunction
  function [21:0] pte_ppn; input [31:0] p; begin pte_ppn = {p[31:20], p[19:10]}; end endfunction
  function [0:0] pte_a; input [31:0] p; begin pte_a = p[6]; end endfunction
  function [0:0] pte_d; input [31:0] p; begin pte_d = p[7]; end endfunction

  // Walk & fill
  integer i;
  always @(posedge clk) begin
    if (rst_i) begin
      // Alias CAM reset
      for (i=0;i<16;i=i+1) begin exec_ppn_v[i] <= 1'b0; exec_ppn_cam[i] <= 20'h0; end
      exec_wr_ptr <= 4'h0;

      w_state <= W_IDLE;
      w_is_if <= 1'b0;
      w_vaddr <= 32'b0;
      w_vpn1  <= 10'b0;
      w_vpn0  <= 10'b0;
      w_ppn_l1<= 22'b0;
      w_valid_resp <= 1'b0;
      w_fault <= 1'b0;
      ptw_req <= 1'b0;
      ptw_addr<= 32'b0;
      // Invalidate TLBs
      for (i=0; i<TLB_ENTRIES; i=i+1) begin
        itlb_v[i] <= 1'b0; dtlb_v[i] <= 1'b0;
      end
    end else begin
      // Clear exec CAM on global sfence flush
      if (sfence_flush_all) begin
        for (i=0;i<16;i=i+1) exec_ppn_v[i] <= 1'b0;
      end

      w_valid_resp <= 1'b0;
      // SFENCE handling
      if (sfence_flush_all) begin
        for (i=0; i<TLB_ENTRIES; i=i+1) begin
          itlb_v[i] <= 1'b0; dtlb_v[i] <= 1'b0;
        end
      end else if (sfence_addr_valid) begin
        // selective by VA (+ ASID if valid)
        reg [3:0] idxs;
        reg [19:0] vtag;
        idxs = tlb_index(sfence_vaddr);
        vtag = {vpn1(sfence_vaddr), vpn0(sfence_vaddr)};
        if (!sfence_asid_valid) begin
          if (itlb_v[idxs] && itlb_vpn[idxs]==vtag) itlb_v[idxs] <= 1'b0;
          if (dtlb_v[idxs] && dtlb_vpn[idxs]==vtag) dtlb_v[idxs] <= 1'b0;
        end else begin
          if (itlb_v[idxs] && itlb_vpn[idxs]==vtag && itlb_asid[idxs]==sfence_asid) itlb_v[idxs] <= 1'b0;
          if (dtlb_v[idxs] && dtlb_vpn[idxs]==vtag && dtlb_asid[idxs]==sfence_asid) dtlb_v[idxs] <= 1'b0;
        end
      end

      // Miss detection → walk start
      if (w_state==W_IDLE && ~mode_bare) begin
        if (if_req && ~itlb_hit) begin
          w_state <= W_L1; w_is_if <= 1'b1; w_vaddr <= if_vaddr;
          w_vpn1 <= vpn1(if_vaddr); w_vpn0 <= vpn0(if_vaddr);
          ptw_req <= 1'b1; ptw_addr <= pte_addr_l1(satp_ppn, vpn1(if_vaddr));
        end else if (d_req && ~dtlb_hit) begin
          w_state <= W_L1; w_is_if <= 1'b0; w_vaddr <= d_vaddr;
          w_vpn1 <= vpn1(d_vaddr); w_vpn0 <= vpn0(d_vaddr);
          ptw_req <= 1'b1; ptw_addr <= pte_addr_l1(satp_ppn, vpn1(d_vaddr));
        end else begin
          ptw_req <= 1'b0;
        end
      end else begin
        // Walk progression
        case (w_state)
          W_L1: begin
            if (ptw_rvalid) begin
              ptw_req <= 1'b0;
              if (ptw_fault || ~pte_v(ptw_rdata)) begin
                w_fault <= 1'b1; w_state <= W_DONE;
              end else if ((pte_r(ptw_rdata) || pte_x(ptw_rdata)) && ~(~pte_r(ptw_rdata) & pte_w(ptw_rdata))) begin
                // Leaf at L1 (superpage): construct PPN with VPN0 in low bits
                w_ppn_l1 <= pte_ppn(ptw_rdata);
                // Fill TLB now (superpage) — permissions with W^X enforced
                begin : fill_l1
                  reg [21:0] fill_ppn;
                  reg [21:0] l1_ppn;
                  reg [3:0]  idx;
                  l1_ppn = pte_ppn(ptw_rdata);
                  fill_ppn = {l1_ppn[21:10], w_vpn0}; // ppn[0] from vpn0
                  idx = tlb_index(w_vaddr);
                  if (w_is_if) begin
                    itlb_v[idx]    <= 1'b1;
                    itlb_asid[idx] <= satp_asid;
                    itlb_vpn[idx]  <= {w_vpn1, w_vpn0};
                    itlb_ppn[idx]  <= fill_ppn;
                    itlb_p_r[idx]  <= pte_r(ptw_rdata);
                    itlb_p_w[idx]  <= 1'b0; // R must be 1 if W=1
                    itlb_p_x[idx]  <= pte_w(ptw_rdata) ? 1'b0 : pte_x(ptw_rdata); 
                                        // Alias CAM insert if executable
                    begin : alias_ins
                      reg [21:0] __ppn;
                      __ppn = pte_ppn(ptw_rdata);
                      if (pte_x(ptw_rdata) && ~pte_w(ptw_rdata)) begin
                        exec_ppn_cam[exec_wr_ptr] <= __ppn[19:0];
                        exec_ppn_v[exec_wr_ptr]   <= 1'b1;
                        exec_wr_ptr               <= exec_wr_ptr + 4'h1;
                      end
                    end

// W^X
                    itlb_p_u[idx]  <= pte_u(ptw_rdata);
                    itlb_p_a[idx]  <= pte_a(ptw_rdata);
                    itlb_p_d[idx]  <= pte_d(ptw_rdata);
                    itlb_p_a[idx]  <= pte_a(ptw_rdata);
                    itlb_p_d[idx]  <= pte_d(ptw_rdata);
                  end else begin
                    dtlb_v[idx]    <= 1'b1;
                    dtlb_asid[idx] <= satp_asid;
                    dtlb_vpn[idx]  <= {w_vpn1, w_vpn0};
                    dtlb_ppn[idx]  <= fill_ppn;
                    dtlb_p_r[idx]  <= pte_r(ptw_rdata);
                    dtlb_p_w[idx]  <= pte_w(ptw_rdata) & pte_r(ptw_rdata);
                    dtlb_p_x[idx]  <= 1'b0;
                    dtlb_p_u[idx]  <= pte_u(ptw_rdata);
                    dtlb_p_a[idx]  <= pte_a(ptw_rdata);
                    dtlb_p_d[idx]  <= pte_d(ptw_rdata);
                    dtlb_p_a[idx]  <= pte_a(ptw_rdata);
                    dtlb_p_d[idx]  <= pte_d(ptw_rdata);
                  end
                end
                w_state <= W_DONE;
              end else begin
                // Non-leaf, go to L0
                w_ppn_l1 <= pte_ppn(ptw_rdata);
                w_state <= W_L0;
                ptw_req <= 1'b1;
                ptw_addr <= pte_addr_l0(pte_ppn(ptw_rdata), w_vpn0);
              end
            end
          end
          W_L0: begin
            if (ptw_rvalid) begin
              ptw_req <= 1'b0;
              if (ptw_fault || ~pte_v(ptw_rdata) || (~pte_r(ptw_rdata) & pte_w(ptw_rdata))) begin
                w_fault <= 1'b1; w_state <= W_DONE;
              end else begin
                // Leaf at L0 — fill entry; enforce W^X (mask X if W=1)
                begin : fill_l0
                  reg [3:0] idx;
                  idx = tlb_index(w_vaddr);
                  if (w_is_if) begin
                    itlb_v[idx]    <= 1'b1;
                    itlb_asid[idx] <= satp_asid;
                    itlb_vpn[idx]  <= {w_vpn1, w_vpn0};
                    itlb_ppn[idx]  <= pte_ppn(ptw_rdata);
                    itlb_p_r[idx]  <= pte_r(ptw_rdata);
                    itlb_p_w[idx]  <= 1'b0;
                    itlb_p_x[idx]  <= pte_w(ptw_rdata) ? 1'b0 : pte_x(ptw_rdata);
                    
                                        // Alias CAM insert if executable
                    begin : alias_ins
                      reg [21:0] __ppn;
                      __ppn = pte_ppn(ptw_rdata);
                      if (pte_x(ptw_rdata) && ~pte_w(ptw_rdata)) begin
                        exec_ppn_cam[exec_wr_ptr] <= __ppn[19:0];
                        exec_ppn_v[exec_wr_ptr]   <= 1'b1;
                        exec_wr_ptr               <= exec_wr_ptr + 4'h1;
                      end
                    end

itlb_p_u[idx]  <= pte_u(ptw_rdata);
                    itlb_p_a[idx]  <= pte_a(ptw_rdata);
                    itlb_p_d[idx]  <= pte_d(ptw_rdata);
                    itlb_p_a[idx]  <= pte_a(ptw_rdata);
                    itlb_p_d[idx]  <= pte_d(ptw_rdata);
                  end else begin
                    dtlb_v[idx]    <= 1'b1;
                    dtlb_asid[idx] <= satp_asid;
                    dtlb_vpn[idx]  <= {w_vpn1, w_vpn0};
                    dtlb_ppn[idx]  <= pte_ppn(ptw_rdata);
                    dtlb_p_r[idx]  <= pte_r(ptw_rdata);
                    dtlb_p_w[idx]  <= pte_w(ptw_rdata) & pte_r(ptw_rdata);
                    dtlb_p_x[idx]  <= 1'b0;
                    dtlb_p_u[idx]  <= pte_u(ptw_rdata);
                    dtlb_p_a[idx]  <= pte_a(ptw_rdata);
                    dtlb_p_d[idx]  <= pte_d(ptw_rdata);
                    dtlb_p_a[idx]  <= pte_a(ptw_rdata);
                    dtlb_p_d[idx]  <= pte_d(ptw_rdata);
                  end
                end
                w_state <= W_DONE;
              end
            end
          end
          W_DONE: begin
            // One-cycle done; faults reported only if request still pending
            w_state <= W_IDLE;
            w_fault <= 1'b0;
          end
        endcase
      end
    end
  end

endmodule
