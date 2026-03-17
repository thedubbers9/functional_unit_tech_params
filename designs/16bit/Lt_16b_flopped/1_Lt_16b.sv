/**
    * Bitwise XOR of two 16-bit inputs
*/

`default_nettype none
module Lt_16b (
    input wire [15:0] a,
    input wire [15:0] b,
    output wire rst
);

	assign rst = (a < b);


endmodule

`default_nettype wire