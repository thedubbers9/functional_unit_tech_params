`default_nettype none
module SUB_8b (
    input wire [7:0] a,
    input wire [7:0] b,
    output wire [7:0] diff
);

	assign diff = a - b;

endmodule

`default_nettype wire
