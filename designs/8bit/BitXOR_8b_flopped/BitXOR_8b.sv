/**
    * Bitwise XOR of two 8-bit inputs
*/

`default_nettype none
module BitXOR_8b (
    input wire [7:0] a,
    input wire [7:0] b,
    output wire [7:0] result
);

	assign result = a ^ b;


endmodule

`default_nettype wire
