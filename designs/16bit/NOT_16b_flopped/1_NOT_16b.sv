/**
    * performs a bitwise AND operation on two 16-bit inputs
*/

`default_nettype none
module NOT_16b (
    input wire [15:0] in,
    output wire [15:0] result
);

    wire [15:0] input_val, result_val;

    assign input_val = in;

	assign result_val = ~input_val;

    assign result = result_val;

endmodule

`default_nettype wire