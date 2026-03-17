`default_nettype none
module LeftShift_32b (
    input wire [31:0] a,
    input wire [31:0] b,
    output wire [31:0] result
);
	
	assign result = a << b;

endmodule

`default_nettype wire
