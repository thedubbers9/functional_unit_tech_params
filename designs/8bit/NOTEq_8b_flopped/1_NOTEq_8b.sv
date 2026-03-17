`default_nettype none
module NOTEq_8b (
    input wire [7:0] a,
    input wire [7:0] b,
    output wire result
);

	assign result = (a != b);

endmodule

`default_nettype wire
