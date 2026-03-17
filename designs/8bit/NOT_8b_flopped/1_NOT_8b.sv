`default_nettype none
module NOT_8b (
    input wire [7:0] in,
    output wire [7:0] result
);

    wire [7:0] input_val, result_val;

    assign input_val = in;

	assign result_val = ~input_val;

    assign result = result_val;

endmodule

`default_nettype wire
