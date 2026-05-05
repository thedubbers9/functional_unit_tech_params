`default_nettype none

module mult_16b_flopped (
    a, b, clk, product_flopped
);

    `ifdef NUM_PIPELINE_STAGES_VAL
        parameter NUM_PIPELINE_STAGES = `NUM_PIPELINE_STAGES_VAL;
    `else
        parameter NUM_PIPELINE_STAGES = 1;
    `endif
    parameter BITWIDTH = 16;

    input wire [BITWIDTH - 1:0] a,b;
    input wire clk;          // Clock input for the flops
    output reg [2*BITWIDTH - 1:0] product_flopped;

    // flop the inputs
    logic [BITWIDTH - 1:0] a_flopped [NUM_PIPELINE_STAGES - 1:0];
    logic [BITWIDTH - 1:0] b_flopped [NUM_PIPELINE_STAGES - 1:0];
    
    genvar i;
    generate
        for (i = 0; i < NUM_PIPELINE_STAGES; i++) begin : in_flop_gen
            always @(posedge clk) begin
                if (i == 0) begin
                    a_flopped[i] <= a;
                    b_flopped[i] <= b;
                end else begin
                    a_flopped[i] <= a_flopped[i - 1];
                    b_flopped[i] <= b_flopped[i - 1];
                end
            end
        end
    endgenerate
    
    logic [2*BITWIDTH - 1:0] result_unflopped [NUM_PIPELINE_STAGES:0];

    // Instantiate the mult_16b module
    mult_16b iDUT (
        .a(a_flopped[NUM_PIPELINE_STAGES - 1]),
        .b(b_flopped[NUM_PIPELINE_STAGES - 1]),
        .result(result_unflopped[0])
    );

    genvar j;

    generate
        for (j = 1; j <= NUM_PIPELINE_STAGES; j++) begin : out_flop_gen
            always @(posedge clk) begin
                result_unflopped[j] <= result_unflopped[j - 1];
            end
        end

    endgenerate

    assign product_flopped = result_unflopped[NUM_PIPELINE_STAGES];

endmodule

`default_nettype wire
