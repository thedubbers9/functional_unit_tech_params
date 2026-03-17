/**
    * Bitwise XOR of two 16-bit inputs
*/

`default_nettype none
module BitXOR_16b (
    input wire [15:0] a,
    input wire [15:0] b,
    output wire [15:0] result
);

	assign result = a ^ b;


endmodule

`default_nettype wire