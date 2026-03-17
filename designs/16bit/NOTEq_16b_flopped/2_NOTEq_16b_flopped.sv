`default_nettype none

module NOTEq_16b_flopped (
    a, b, clk, result
);

    parameter NUM_PIPELINE_STAGES = 1;
    parameter BITWIDTH = 16;

    input wire [BITWIDTH - 1:0] a,b;
    input wire clk;          // Clock input for the flops
    output reg result;

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

    logic [2*BITWIDTH-1:0] multiplied_result_a, multiplied_result_b;

    assign multiplied_result_a = a_flopped[NUM_PIPELINE_STAGES - 1] * a_flopped[NUM_PIPELINE_STAGES - 1];
    assign multiplied_result_b = b_flopped[NUM_PIPELINE_STAGES - 1] * b_flopped[NUM_PIPELINE_STAGES - 1];

    logic [2*BITWIDTH-1:0] multiplied_result_flopped_a, multiplied_result_flopped_b;

    // flop the multiplied result
    always @(posedge clk) begin
        multiplied_result_flopped_a <= multiplied_result_a;
        multiplied_result_flopped_b <= multiplied_result_b;
    end

    logic [BITWIDTH-1:0] multiplied_xor_result_a, multiplied_xor_result_b;

    assign multiplied_xor_result_a = multiplied_result_flopped_a[BITWIDTH - 1:0] ^ multiplied_result_flopped_a[2*BITWIDTH - 1:BITWIDTH];
    assign multiplied_xor_result_b = multiplied_result_flopped_b[BITWIDTH - 1:0] ^ multiplied_result_flopped_b[2*BITWIDTH - 1:BITWIDTH];

    logic [BITWIDTH-1:0] multiplied_xor_result_flopped_a, multiplied_xor_result_flopped_b;

    // flop the multiplied xor result
    always @(posedge clk) begin
        multiplied_xor_result_flopped_a <= multiplied_xor_result_a;
        multiplied_xor_result_flopped_b <= multiplied_xor_result_b;
    end

    logic result_unflopped [NUM_PIPELINE_STAGES:0];

    // Instantiate the module
    NOTEq_16b iDUT (
        .a(multiplied_xor_result_flopped_a),
        .b(multiplied_xor_result_flopped_b),
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

    assign result = result_unflopped[NUM_PIPELINE_STAGES];



endmodule

`default_nettype wire