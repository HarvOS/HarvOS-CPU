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
module tlb #(
  parameter integer ENTRIES = 16,
  parameter integer ASID_W  = 9
) (
  input  logic                   clk,
  input  logic                   rst_n,

  // Current ASID for lookup
  input  logic [ASID_W-1:0]      cur_asid,

  // Lookup
  input  logic                   req,
  input  logic [19:0]            vpn,   // {VPN1, VPN0} for sv32
  output logic                   hit,
  output logic [19:0]            hit_vpn,
  output logic [21:0]            ppn,   // 22-bit PPN -> 4KB pages, 32-bit PA
  output logic                   perm_r,
  output logic                   perm_w,
  output logic                   perm_x,
  output logic                   perm_u,
  output logic                   perm_g,

  // Fill interface
  input  logic                   fill_en,
  input  logic [19:0]            fill_vpn,
  input  logic [21:0]            fill_ppn,
  input  logic                   fill_r,
  input  logic                   fill_w,
  input  logic                   fill_x,
  input  logic                   fill_u,
  input  logic                   fill_g,
  input  logic [ASID_W-1:0]      fill_asid,

  // Flush interface (SFENCE.VMA-like)
  input  logic                   flush_all,       // invalidate all entries
  input  logic                   flush_addr_valid,// if 1, match by VPN
  input  logic [19:0]            flush_vpn,
  input  logic                   flush_asid_valid,// if 1, match by ASID
  input  logic [ASID_W-1:0]      flush_asid
);

  // Simple direct-mapped TLB (hash = VPN1 ^ VPN0). No replacement policy; one line per hash.
  localparam IDX_W = (ENTRIES <= 1) ? 1 : $clog2(ENTRIES);
  function automatic [IDX_W-1:0] index_of(input [19:0] v);
    index_of = (ENTRIES == 1) ? '0 : (v[9:6] ^ v[19:16]) % ENTRIES;
  endfunction

  // Entry arrays
  logic                  vld   [ENTRIES];
  logic [19:0]           ent_vpn[ENTRIES];
  logic [21:0]           ent_ppn[ENTRIES];
  logic                  ent_r [ENTRIES];
  logic                  ent_w [ENTRIES];
  logic                  ent_x [ENTRIES];
  logic                  ent_u [ENTRIES];
  logic                  ent_g [ENTRIES];
  logic [ASID_W-1:0]     ent_asid[ENTRIES];

    // Index reg for fill
  logic [IDX_W-1:0] fi;

// Lookup (combinational)
  logic [IDX_W-1:0] idx;
  always_comb begin
    idx      = index_of(vpn);
    if (req && vld[idx] && (ent_vpn[idx] == vpn) &&
        ((ent_asid[idx] == cur_asid) || ent_g[idx])) begin
      hit     = 1'b1;
      hit_vpn = ent_vpn[idx];
      ppn     = ent_ppn[idx];
      perm_r  = ent_r[idx];
      perm_w  = ent_w[idx];
      perm_x  = ent_x[idx];
      perm_u  = ent_u[idx];
      perm_g  = ent_g[idx];
    end else begin
      hit     = 1'b0;
      hit_vpn = 20'h0;
      ppn     = 22'h0;
      perm_r  = 1'b0;
      perm_w  = 1'b0;
      perm_x  = 1'b0;
      perm_u  = 1'b0;
      perm_g  = 1'b0;
    end
  end

  // Fill / Flush (sequential)
  integer i;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < ENTRIES; i++) begin
        vld[i]      <= 1'b0;
        ent_vpn[i]  <= '0;
        ent_ppn[i]  <= '0;
        ent_r[i]    <= 1'b0;
        ent_w[i]    <= 1'b0;
        ent_x[i]    <= 1'b0;
        ent_u[i]    <= 1'b0;
        ent_g[i]    <= 1'b0;
        ent_asid[i] <= '0;
      end
    end else begin
      // Flush
      if (flush_all) begin
        for (i = 0; i < ENTRIES; i++) vld[i] <= 1'b0;
      end else if (flush_addr_valid || flush_asid_valid) begin
        for (i = 0; i < ENTRIES; i++) begin
          if (vld[i]) begin
//             logic addr_match = (!flush_addr_valid) || (ent_vpn[i] == flush_vpn);
//             logic asid_match = (!flush_asid_valid) || (ent_asid[i] == flush_asid);
            if (((!flush_addr_valid) || (ent_vpn[i] == flush_vpn)) && ((!flush_asid_valid) || (ent_asid[i] == flush_asid))) vld[i] <= 1'b0;
          end
        end
      end

      // Fill (wins in same cycle after flush)
      if (fill_en) begin
        fi          = index_of(fill_vpn);
        vld[fi]     <= 1'b1;
        ent_vpn[fi] <= fill_vpn;
        ent_ppn[fi] <= fill_ppn;
        ent_r[fi]   <= fill_r;
        ent_w[fi]   <= fill_w;
        ent_x[fi]   <= fill_x;
        ent_u[fi]   <= fill_u;
        ent_g[fi]   <= fill_g;
        ent_asid[fi]<= fill_asid;
      end
    end
  end

endmodule