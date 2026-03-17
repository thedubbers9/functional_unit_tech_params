/**
    * simple implementation of a barrel shifter. Implementation left to synthesis tool
*/

`default_nettype none
module RightShift_16b (
    input wire [15:0] a,
    input wire [15:0] b,
    output wire [15:0] result
);
	
	assign result = a >> b;


endmodule

`default_nettype wire