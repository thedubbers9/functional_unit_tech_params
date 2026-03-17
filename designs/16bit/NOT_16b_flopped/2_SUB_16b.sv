/**
    * basic 16 bit subtracter using infered subtracter from '-' operator
*/

`default_nettype none
module SUB_16b (
    input wire [15:0] a,
    input wire [15:0] b,
    output wire [15:0] diff
);

	assign diff = a - b;


endmodule

`default_nettype wire