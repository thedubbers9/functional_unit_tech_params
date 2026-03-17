`default_nettype none

module mult_16b_flopped (
    input wire [15:0] a,
    input wire [15:0] b,
    input wire clk,          // Clock input for the flops
    output reg [31:0] product_flopped
);

    wire [15:0] result;

    reg [15:0] a_flopped, b_flopped;

    // Instantiate the mult_16b module
    mult_16b iDUT (
        .a(a_flopped),
        .b(b_flopped),
        .result(result)
    );

    // Flop the output with synchronous reset
    always @(posedge clk) begin
        product_flopped <= result;
        a_flopped <= a;
        b_flopped <= b;
    end

endmodule

`default_nettype wire