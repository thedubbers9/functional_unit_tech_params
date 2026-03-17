`default_nettype none
module NOT_4b (
    input wire [3:0] in,
    output wire [3:0] result
);

    wire [3:0] input_val, result_val;

    assign input_val = in;

	assign result_val = ~input_val;

    assign result = result_val;

endmodule

`default_nettype wire
