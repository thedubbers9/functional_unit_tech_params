/**
    * adds two 8-bit numbers with a carry-in. Uses the '+' operator, so synthesis tool will infer an adder
*/

`default_nettype none
module ADD_8b (
    input wire [7:0] a,
    input wire [7:0] b,
    input wire carry_in,
    output wire carry_out, 
    output wire [7:0] sum
);
	
    assign {carry_out, sum} = a + b + carry_in;


endmodule

`default_nettype wire
