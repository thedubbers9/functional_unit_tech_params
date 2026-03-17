`default_nettype none

module Modulus_8_flopped (
    input wire [7:0] a,
    input wire [7:0] b,
    input wire clk,          // Clock input for the flops
    output reg [7:0] result_flopped
);

    // Registers for flopped inputs
    reg [7:0] a_flopped;
    reg [7:0] b_flopped;

    // Wires for intermediate results
    wire [7:0] result;

    // Instantiate the DUT
    Modulus_8b iDUT (
        .a(a_flopped),
        .b(b_flopped),
        .result(result)
    );

    // Flop the inputs and the output
    always @(posedge clk) begin
        a_flopped <= a;
        b_flopped <= b;
        result_flopped <= result;
    end

endmodule

`default_nettype wire
