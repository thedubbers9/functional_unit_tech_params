
`default_nettype none

module RightShift_16_flopped (
    input wire [15:0] a,
    input wire [15:0] b,
    input wire clk,          // Clock input for the flops
    output reg [15:0] sum_flopped
);

    parameter NUM_PIPELINE_STAGES = 1;
    parameter BITWIDTH = 16;

    // Flopped inputs
    logic [BITWIDTH - 1:0] a_flopped [NUM_PIPELINE_STAGES - 1:0];
    logic [BITWIDTH - 1:0] b_flopped [NUM_PIPELINE_STAGES - 1:0];

    // Multiplied results
    logic [2*BITWIDTH-1:0] multiplied_result_a, multiplied_result_b;

    // Flopped multiplied results
    logic [2*BITWIDTH-1:0] multiplied_result_flopped_a, multiplied_result_flopped_b;

    // XOR results
    logic [BITWIDTH-1:0] multiplied_xor_result_a, multiplied_xor_result_b;

    // Flopped XOR results
    logic [BITWIDTH-1:0] multiplied_xor_result_flopped_a, multiplied_xor_result_flopped_b;

    // Unflopped sum
    logic [BITWIDTH-1:0] sum_unflopped [NUM_PIPELINE_STAGES:0];

    genvar i;
    generate
        // Flop the inputs
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

    // Multiply the inputs
    assign multiplied_result_a = a_flopped[NUM_PIPELINE_STAGES - 1] * a_flopped[NUM_PIPELINE_STAGES - 1];
    assign multiplied_result_b = b_flopped[NUM_PIPELINE_STAGES - 1] * b_flopped[NUM_PIPELINE_STAGES - 1];

    // Flop the multiplied results
    always @(posedge clk) begin
        multiplied_result_flopped_a <= multiplied_result_a;
        multiplied_result_flopped_b <= multiplied_result_b;
    end

    // XOR the multiplied results
    assign multiplied_xor_result_a = multiplied_result_flopped_a[BITWIDTH - 1:0] ^ multiplied_result_flopped_a[2*BITWIDTH - 1:BITWIDTH];
    assign multiplied_xor_result_b = multiplied_result_flopped_b[BITWIDTH - 1:0] ^ multiplied_result_flopped_b[2*BITWIDTH - 1:BITWIDTH];

    // Flop the XOR results
    always @(posedge clk) begin
        multiplied_xor_result_flopped_a <= multiplied_xor_result_a;
        multiplied_xor_result_flopped_b <= multiplied_xor_result_b;
    end


    // Instantiate the DUT
    RightShift_16b iDUT (
        .a(multiplied_xor_result_flopped_a),
        .b(multiplied_xor_result_flopped_b),
        .result(sum_unflopped[0])
    );

    genvar j;
    generate
        // Flop the addition result through the pipeline
        for (j = 1; j <= NUM_PIPELINE_STAGES; j++) begin : out_flop_gen
            always @(posedge clk) begin
                sum_unflopped[j] <= sum_unflopped[j - 1];
            end
        end
    endgenerate

    // Assign the final pipeline stage to the output
    always @(posedge clk) begin
        sum_flopped <= sum_unflopped[NUM_PIPELINE_STAGES];
    end

endmodule

`default_nettype wire