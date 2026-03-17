`default_nettype none
module SUB_32b (
    input wire [31:0] a,
    input wire [31:0] b,
    output wire [31:0] diff
);

	assign diff = a - b;

endmodule

`default_nettype wire
