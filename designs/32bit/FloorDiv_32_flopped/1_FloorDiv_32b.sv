`default_nettype none
module FloorDiv_32b (
    input wire [31:0] a,
    input wire [31:0] b,
    output wire [31:0] quotient
);
	
	assign quotient = a / b;

endmodule

`default_nettype wire
