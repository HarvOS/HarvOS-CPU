// SPDX-License-Identifier: MIT
package harvos_sva_pkg;
  // common SVA helpers
  `define ASSUME_STABLE(sig) assume property (@(posedge clk) disable iff (!rst_n) $stable(sig))
  `define ASSERT_STABLE(sig) assert property (@(posedge clk) disable iff (!rst_n) $stable(sig))
  `define ASSERT_NEVER(expr) assert property (@(posedge clk) disable iff (!rst_n) !(expr))
  `define ASSERT_IMP(a,b)    assert property (@(posedge clk) disable iff (!rst_n) (a) |-> (b))
  `define COVER(expr)        cover property  (@(posedge clk) disable iff (!rst_n) (expr))
endpackage
