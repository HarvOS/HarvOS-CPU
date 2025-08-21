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

`ifndef HARVOS_IMEM_IF_SV
`define HARVOS_IMEM_IF_SV

interface harvos_imem_if;
  logic        req;
  logic [31:0] addr;
  logic [31:0] rdata;
  logic        rvalid;
  logic        fault;
  modport master (input rdata, rvalid, fault, output req, addr);
  modport slave  (output rdata, rvalid, fault, input req, addr);
endinterface
`endif
