`default_nettype none
module Modulus_4b (
    input wire [3:0] a,
    input wire [3:0] b,
    output wire [3:0] result
);
	
	assign result = a % b;

endmodule

`default_nettype wire
