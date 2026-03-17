`default_nettype none
module Lt_8b (
    input wire [7:0] a,
    input wire [7:0] b,
    output wire rst
);

	assign rst = (a < b);

endmodule

`default_nettype wire
