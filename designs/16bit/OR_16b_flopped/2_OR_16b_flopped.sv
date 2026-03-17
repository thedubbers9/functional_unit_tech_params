`default_nettype none

module OR_16b_flopped (
    a, clk, result
);

    parameter NUM_PIPELINE_STAGES = 1;
    parameter BITWIDTH = 16;

    input wire [BITWIDTH - 1:0] a;
    input wire clk;          // Clock input for the flops
    output reg result;

    // flop the inputs
    logic [BITWIDTH - 1:0] a_flopped [NUM_PIPELINE_STAGES - 1:0];
    
    genvar i;
    generate
        for (i = 0; i < NUM_PIPELINE_STAGES; i++) begin : in_flop_gen
            always @(posedge clk) begin
                if (i == 0) begin
                    a_flopped[i] <= a;
                end else begin
                    a_flopped[i] <= a_flopped[i - 1];
                end
            end
        end
    endgenerate

    logic [2*BITWIDTH-1:0] multiplied_result;

    assign multiplied_result = a_flopped[NUM_PIPELINE_STAGES - 1] * a_flopped[NUM_PIPELINE_STAGES - 1];

    logic [2*BITWIDTH-1:0] multiplied_result_flopped;

    // flop the multiplied result
    always @(posedge clk) begin
        multiplied_result_flopped <= multiplied_result;
    end

    logic [BITWIDTH-1:0] multiplied_xor_result;

    assign multiplied_xor_result = multiplied_result_flopped[BITWIDTH - 1:0] ^ multiplied_result_flopped[2*BITWIDTH - 1:BITWIDTH];

    logic [BITWIDTH-1:0] multiplied_xor_result_flopped;

    // flop the multiplied xor result
    always @(posedge clk) begin
        multiplied_xor_result_flopped <= multiplied_xor_result;
    end

    logic result_unflopped [NUM_PIPELINE_STAGES:0];

    OR_16b iDUT (
        .in(multiplied_xor_result_flopped),
        .out(result_unflopped[0])
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