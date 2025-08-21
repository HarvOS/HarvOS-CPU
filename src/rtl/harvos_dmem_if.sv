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

`ifndef HARVOS_DMEM_IF_SV
`define HARVOS_DMEM_IF_SV

interface harvos_dmem_if;
  logic        req;
  logic        we;
  logic [3:0]  be;
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [31:0] rdata;
  logic        done;
  logic        fault;
  modport master (input rdata, done, fault, output req, we, be, addr, wdata);
  modport slave  (output rdata, done, fault, input req, we, be, addr, wdata);
endinterface
`endif
