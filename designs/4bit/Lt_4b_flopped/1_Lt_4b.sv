`default_nettype none
module Lt_4b (
    input wire [3:0] a,
    input wire [3:0] b,
    output wire rst
);

	assign rst = (a < b);

endmodule

`default_nettype wire
