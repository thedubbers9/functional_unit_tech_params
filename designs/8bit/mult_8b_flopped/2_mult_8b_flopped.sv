`default_nettype none

module mult_8b_flopped (
    input wire [7:0] a,
    input wire [7:0] b,
    input wire clk,          // Clock input for the flops
    output reg [15:0] product_flopped
);

    wire [15:0] result;

    reg [7:0] a_flopped, b_flopped;

    // Instantiate the mult_8b module
    mult_8b iDUT (
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
