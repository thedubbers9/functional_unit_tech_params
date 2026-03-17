/**
    * OR_32b module implements a 32-bit OR gate.
    * The module has a 32-bit input and a 1-bit output.
    * The output is the result of a bitwise OR operation on the input.
    * The module uses the bitwise OR operator '|' to perform the operation.
*/

`default_nettype none
module OR_32b (
    input wire [31:0] in,
    output wire out
);

	assign out = |in;


endmodule

`default_nettype wire
