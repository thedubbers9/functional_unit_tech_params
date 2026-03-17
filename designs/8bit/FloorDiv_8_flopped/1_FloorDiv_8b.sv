`default_nettype none
module FloorDiv_8b (
    input wire [7:0] a,
    input wire [7:0] b,
    output wire [7:0] quotient
);
	
	assign quotient = a / b;

endmodule

`default_nettype wire
