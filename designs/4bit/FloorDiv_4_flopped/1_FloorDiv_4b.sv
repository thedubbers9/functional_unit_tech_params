`default_nettype none
module FloorDiv_4b (
    input wire [3:0] a,
    input wire [3:0] b,
    output wire [3:0] quotient
);
	
	assign quotient = a / b;

endmodule

`default_nettype wire
