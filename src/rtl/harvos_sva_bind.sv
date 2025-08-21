// harvos_sva_bind.sv (rtl shim)
// Disabled for synthesis; enabled under FORMAL to include tmp bindings
`ifndef FORMAL
// no content
`else
`include "../tmp/harvos_sva_bind.sv"
`endif
