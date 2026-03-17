`default_nettype none
module mult_32b (
    input wire [31:0] a,
    input wire [31:0] b,
    output wire [63:0] result
);

	assign result = a * b;

endmodule

`default_nettype wire
