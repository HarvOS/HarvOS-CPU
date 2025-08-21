# HarvOS Formal Pack (Milestone 6)

This pack provides a ready-to-run SymbiYosys setup to prove core invariants
for `mmu_sv32` (D-path NX, no W^X, Harvard D fault).

## Quick start
1. Install SymbiYosys + Yosys + a solver (e.g. z3).
2. From this folder, run:
   ```bash
   sby -f formal/mmu_invariants.sby
   ```
3. The proof runs in BMC mode up to depth 32. Increase `depth` for more coverage.

## Files
- `HarvOS/src/rtl/mmu_sv32.sv` — the DUT (patched, V2005-friendly).
- `formal/mmu_harness.sv` — formal harness with assumptions and assertions (no binds).
- `formal/mmu_invariants.sby` — SymbiYosys config.

You can adapt the I-space window in both the DUT and harness if your ROM ranges differ.
