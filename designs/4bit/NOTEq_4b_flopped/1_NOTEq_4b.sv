`default_nettype none
module NOTEq_4b (
    input wire [3:0] a,
    input wire [3:0] b,
    output wire result
);

	assign result = (a != b);

endmodule

`default_nettype wire
