// alias_guard.sv — Enforce Harvard-Alias invariant at the physical level
// Blocks D-side writes to any physical page (PPN) that is currently executable.
// Inputs:
//   - write_valid, write_addr (PA), write_en
//   - lock_i: when 1, overrides are ignored (post-LOCK hard enforcement)
//   - allow_override_prelock: when 1 and lock_i==0, allows writes despite exec hit (for controlled updates)
// Connect exec_ppn tracker 'hit_exec_ppn' to this module.
`timescale 1ns/1ps

module alias_guard (
  input  wire        write_valid,
  input  wire        write_en,
  input  wire [31:0] write_addr,

  input  wire        hit_exec_ppn,           // from exec_ppn_tracker(query_pa=write_addr)

  input  wire        lock_i,                 // sticky LOCK
  input  wire        allow_override_prelock, // e.g., Boot's update window

  output wire        allow_write             // 1=permit, 0=block
);
  wire block = write_valid && write_en && hit_exec_ppn && (lock_i || !allow_override_prelock);
  assign allow_write = !block;

`ifndef SYNTHESIS
  // Alias-guard invariant: D-writes into executable PPNs must be denied once LOCK is active
  always @* begin
    if (write_valid && write_en && hit_exec_ppn && lock_i) begin
      assert (!allow_write) else $error("Alias-guard failed to deny write into exec PPN");
    end
  end
`endif
endmodule

