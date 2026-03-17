`default_nettype none
module Lt_32b (
    input wire [31:0] a,
    input wire [31:0] b,
    output wire rst
);

	assign rst = (a < b);

endmodule

`default_nettype wire
