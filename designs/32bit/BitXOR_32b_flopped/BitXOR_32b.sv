/**
    * Bitwise XOR of two 32-bit inputs
*/

`default_nettype none
module BitXOR_32b (
    input wire [31:0] a,
    input wire [31:0] b,
    output wire [31:0] result
);

	assign result = a ^ b;


endmodule

`default_nettype wire
