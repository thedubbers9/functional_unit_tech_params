/**
    * adds two 16-bit numbers with a carry-in. Uses the '+' operator, so synthesis tool will infer an adder
*/

`default_nettype none
module FloorDiv_16b (
    input wire [15:0] a,
    input wire [15:0] b,
    output wire [15:0] quotient
);
	
	assign quotient = a / b;


endmodule

`default_nettype wire