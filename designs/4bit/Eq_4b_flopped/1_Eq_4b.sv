/**
    * Bitwise XOR of two 4-bit inputs
*/

`default_nettype none
module Eq_4b (
    input wire [3:0] a,
    input wire [3:0] b,
    output wire result
);

	assign result = (a == b);


endmodule

`default_nettype wire
