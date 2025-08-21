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


module alu (
  input  logic [3:0]  op,     // 0:add,1:sub,2:and,3:or,4:xor,5:slt
  input  logic [31:0] a,
  input  logic [31:0] b,
  output logic [31:0] y
);
  always_comb begin
    case (op)
  4'd0: y = a + b;             // ADD
  4'd1: y = a - b;             // SUB
  4'd2: y = a & b;             // AND
  4'd3: y = a | b;             // OR
  4'd4: y = a ^ b;             // XOR
  4'd5: y = ($signed(a) < $signed(b)) ? 32'h1 : 32'h0; // SLT
  4'd6: y = (a < b) ? 32'h1 : 32'h0;                   // SLTU
  4'd7: y = a << b[4:0];       // SLL
  4'd8: y = a >> b[4:0];       // SRL
  4'd9: y = $signed(a) >>> b[4:0]; // SRA
  default: y = 32'h0;
endcase
  end
endmodule
