`default_nettype none
module LtE_32b (
    input wire [31:0] a,
    input wire [31:0] b,
    output wire result
);

	assign result = (a <= b);

endmodule

`default_nettype wire
