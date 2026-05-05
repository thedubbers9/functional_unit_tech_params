`ifndef __FLOATING_POINT_MULTIPLIER_V__
`define __FLOATING_POINT_MULTIPLIER_V__

// FP multiplier code from: 
// https://github.com/V0XNIHILI/parametrizable-floating-point-verilog (with minor modifications)

// Helper modules - is_special_float and result_rounder
module is_special_float #(
    parameter int EXPONENT_WIDTH = 8,
    parameter int MANTISSA_WIDTH = 23,
    parameter int IGNORE_SIGN_BIT_FOR_NAN = 1
) (
    input [EXPONENT_WIDTH+MANTISSA_WIDTH+1-1:0] a,
    output is_infinite,
    output is_zero,
    output is_subnormal,
    output is_signaling_nan,
    output is_quiet_nan
);

    // Taken from: https://www.semanticscholar.org/paper/Analysis-and-Research-of-Floating-Point-Exceptions-Hong-Chongyang/471be72eba3aca01cef4d979d4039691c0223235/figure/1

    wire sign;
    wire [EXPONENT_WIDTH-1:0] exponent;
    wire [MANTISSA_WIDTH-1:0] mantissa;

    assign {sign, exponent, mantissa} = a;

    // For a few variants (see here: https://www.opencompute.org/documents/ocp-microscaling-formats-mx-v1-0-spec-final-pdf)
    // there is special handling of NaN and infinite values. E5M2 fits inside the current handling
    // and therefore is not handled separately.
    wire is_E4M3 = EXPONENT_WIDTH == 4 && MANTISSA_WIDTH == 3;  // FP8
    wire is_E2M3 = EXPONENT_WIDTH == 2 && MANTISSA_WIDTH == 3;  // FP6
    wire is_E3M2 = EXPONENT_WIDTH == 3 && MANTISSA_WIDTH == 2;  // FP6
    wire is_E2M1 = EXPONENT_WIDTH == 2 && MANTISSA_WIDTH == 1;  // FP4

    wire is_exponent_zero = (exponent == {EXPONENT_WIDTH{1'b0}});
    wire is_exponent_ones = (exponent == {EXPONENT_WIDTH{1'b1}});
    wire is_mantissa_zero = (mantissa == {MANTISSA_WIDTH{1'b0}});
    wire is_mantissa_ones = (mantissa == {MANTISSA_WIDTH{1'b1}});
    wire is_negative = sign == 1'b1;
    wire ignore_sign_bit_for_nan = IGNORE_SIGN_BIT_FOR_NAN == 1;

    // E2M3, E3M2 and E2M1 do not have infinite and NaN values.
    assign is_infinite = is_E4M3 || is_E2M3 || is_E3M2 || is_E2M1 ? 1'b0 : is_exponent_ones && is_mantissa_zero;
    assign is_zero = is_exponent_zero && is_mantissa_zero;
    assign is_subnormal = is_exponent_zero && !is_mantissa_zero;
    assign is_signaling_nan = is_E2M3 || is_E3M2 || is_E2M1 ? 1'b0 : (is_E4M3 ? is_exponent_ones && is_mantissa_ones : (is_negative || ignore_sign_bit_for_nan) && is_exponent_ones && (mantissa[MANTISSA_WIDTH-1] == 1'b1));
    assign is_quiet_nan = is_E4M3 || is_E2M3 || is_E3M2 || is_E2M1 ? 1'b0 : (is_negative || ignore_sign_bit_for_nan) && is_exponent_ones && (mantissa[MANTISSA_WIDTH-1] == 1'b0) && !is_mantissa_zero;
endmodule

module result_rounder #(
    parameter int EXPONENT_WIDTH = 8,
    parameter int MANTISSA_WIDTH = 23,
    parameter int ROUND_TO_NEAREST_TIES_TO_EVEN = 1,  // 0: round to zero (chopping last bits), 1: round to nearest
    parameter int ROUNDING_BITS = 3  // Number of bits to use for rounding, should always be larger than 1, even for ROUND_TO_NEAREST_TIES_TO_EVEN = 0
) (
    input [EXPONENT_WIDTH-1:0] non_rounded_exponent,
    input [MANTISSA_WIDTH-1:0] non_rounded_mantissa,
    input [ROUNDING_BITS-1:0] rounding_bits,
    output reg [EXPONENT_WIDTH-1:0] rounded_exponent,
    output reg [MANTISSA_WIDTH-1:0] rounded_mantissa,
    output reg overflow_flag
);
    // Read-up on rounding: https://ee.usc.edu/~redekopp/cs356/slides/CS356Unit3_FP.pdf

    reg is_halfway;

    always_comb begin
        overflow_flag = 1'b0;
        rounded_mantissa = non_rounded_mantissa;
        rounded_exponent = non_rounded_exponent;

        if (ROUND_TO_NEAREST_TIES_TO_EVEN == 1) begin
            is_halfway = rounding_bits == {1'b1, {(ROUNDING_BITS - 1) {1'b0}}};

            // If the additonal mantissa bits are exactly halfway and if the last bit of the mantissa is 1
            // OR
            // if the additional bits are more than halfway,
            // round up
            if ((is_halfway && non_rounded_mantissa[0] == 1'b1) || (!is_halfway && rounding_bits[ROUNDING_BITS-1] == 1'b1)) begin
                // Rounding up

                rounded_mantissa = non_rounded_mantissa + 1;

                // If the mantissa has overflowed
                if (rounded_mantissa == 0) begin
                    // Mantissa has overflowed due to rounding

                    rounded_exponent = non_rounded_exponent + 1;

                    if (rounded_exponent == {EXPONENT_WIDTH{1'b1}}) begin
                        // Overflow detected during rounding

                        // Note: out_sign is already set
                        rounded_exponent = {EXPONENT_WIDTH{1'b1}};
                        rounded_mantissa = {MANTISSA_WIDTH{1'b0}};

                        overflow_flag = 1'b1;
                    end
                end
            end
            // Else, round down; nothing to do
        end
    end

endmodule

// MAIN MODULE - fp multiplier
module FP_MUL_PIPE5 #(
    parameter int EXPONENT_WIDTH = 8,
    parameter int MANTISSA_WIDTH = 23,
    parameter int ROUND_TO_NEAREST_TIES_TO_EVEN = 1,  // 0: round to zero (chopping last bits), 1: round to nearest
    parameter int IGNORE_SIGN_BIT_FOR_NAN = 1,
    localparam int FloatBitWidth = EXPONENT_WIDTH + MANTISSA_WIDTH + 1
) (
    input logic clk,
    input logic rst,
    input [FloatBitWidth-1:0] a,
    input [FloatBitWidth-1:0] b,
    output logic [FloatBitWidth-1:0] out,

    // Exception flags
    output logic underflow_flag,
    output logic overflow_flag,
    output logic invalid_operation_flag
);

    // Pipeline registers for 5 stages
    typedef struct packed {
        logic [FloatBitWidth-1:0] a, b;
        logic is_a_infinite, is_b_infinite;
        logic is_a_zero, is_b_zero;
        logic is_signaling_nan_a, is_signaling_nan_b;
        logic is_quiet_nan_a, is_quiet_nan_b;
    } stage1_t;
    stage1_t stage1_reg, stage1_next;

    typedef struct packed {
        logic a_sign, b_sign;
        logic [EXPONENT_WIDTH-1:0] a_exponent, b_exponent;
        logic [MANTISSA_WIDTH-1:0] a_mantissa, b_mantissa;
        logic a_implicit_leading_bit, b_implicit_leading_bit;
        logic is_a_infinite, is_b_infinite;
        logic is_a_zero, is_b_zero;
        logic is_signaling_nan_a, is_signaling_nan_b;
        logic is_quiet_nan_a, is_quiet_nan_b;
    } stage2_t;
    stage2_t stage2_reg, stage2_next;

    typedef struct packed {
        logic out_sign;
        logic signed [EXPONENT_WIDTH+2-1:0] a_mul_b_exponent;
        logic [(MANTISSA_WIDTH+1)*2-1:0] a_mul_b_mantissa;
        logic leading_one_is_MSB;
        logic is_a_zero, is_b_zero;
        logic is_a_infinite, is_b_infinite;
        logic is_signaling_nan_a, is_signaling_nan_b;
        logic is_quiet_nan_a, is_quiet_nan_b;
        logic [FloatBitWidth-1:0] quiet_nan;
        logic [EXPONENT_WIDTH-1-1:0] bias;
    } stage3_t;
    stage3_t stage3_reg, stage3_next;

    typedef struct packed {
        logic [EXPONENT_WIDTH-1:0] non_rounded_exponent;
        logic [MANTISSA_WIDTH-1:0] non_rounded_mantissa;
        logic [MANTISSA_WIDTH+1-1:0] additional_mantissa_bits;
        logic out_sign;
        logic is_a_zero, is_b_zero;
        logic is_a_infinite, is_b_infinite;
        logic is_signaling_nan_a, is_signaling_nan_b;
        logic is_quiet_nan_a, is_quiet_nan_b;
        logic [FloatBitWidth-1:0] quiet_nan;
        logic [EXPONENT_WIDTH-1-1:0] bias;
        logic signed [EXPONENT_WIDTH+2-1:0] a_mul_b_exponent;
        logic leading_one_is_MSB;
    } stage4_t;
    stage4_t stage4_reg, stage4_next;

    typedef struct packed {
        logic [FloatBitWidth-1:0] out;
        logic underflow_flag, overflow_flag, invalid_operation_flag;
        logic [EXPONENT_WIDTH-1:0] out_exponent;
        logic [MANTISSA_WIDTH-1:0] out_mantissa;
        logic out_sign;
    } stage5_t;
    stage5_t stage5_reg, stage5_next;

    // Stage 1: Unpack, special value check

    is_special_float #(EXPONENT_WIDTH, MANTISSA_WIDTH, IGNORE_SIGN_BIT_FOR_NAN) is_special_float_a (
        .a(a),
        .is_infinite(stage1_next.is_a_infinite),
        .is_zero(stage1_next.is_a_zero),
        .is_signaling_nan(stage1_next.is_signaling_nan_a),
        .is_quiet_nan(stage1_next.is_quiet_nan_a),
        .is_subnormal()
    );
    is_special_float #(EXPONENT_WIDTH, MANTISSA_WIDTH, IGNORE_SIGN_BIT_FOR_NAN) is_special_float_b (
        .a(b),
        .is_infinite(stage1_next.is_b_infinite),
        .is_zero(stage1_next.is_b_zero),
        .is_signaling_nan(stage1_next.is_signaling_nan_b),
        .is_quiet_nan(stage1_next.is_quiet_nan_b),
        .is_subnormal()
    );
    always_ff @(posedge clk or posedge rst) begin
        if (rst) stage1_reg <= '0;
        else stage1_reg <= stage1_next;
    end
    always_comb begin
        stage1_next.a = a;
        stage1_next.b = b;
    end

    // Stage 2: Unpack fields
    always_ff @(posedge clk or posedge rst) begin
        if (rst) stage2_reg <= '0;
        else stage2_reg <= stage2_next;
    end
    always_comb begin
        {stage2_next.a_sign, stage2_next.a_exponent, stage2_next.a_mantissa} = stage1_reg.a;
        {stage2_next.b_sign, stage2_next.b_exponent, stage2_next.b_mantissa} = stage1_reg.b;
        stage2_next.a_implicit_leading_bit = !(stage2_next.a_exponent == 0);
        stage2_next.b_implicit_leading_bit = !(stage2_next.b_exponent == 0);
        stage2_next.is_a_infinite = stage1_reg.is_a_infinite;
        stage2_next.is_b_infinite = stage1_reg.is_b_infinite;
        stage2_next.is_a_zero = stage1_reg.is_a_zero;
        stage2_next.is_b_zero = stage1_reg.is_b_zero;
        stage2_next.is_signaling_nan_a = stage1_reg.is_signaling_nan_a;
        stage2_next.is_signaling_nan_b = stage1_reg.is_signaling_nan_b;
        stage2_next.is_quiet_nan_a = stage1_reg.is_quiet_nan_a;
        stage2_next.is_quiet_nan_b = stage1_reg.is_quiet_nan_b;
    end

    // Stage 3: Multiply, exponent, sign
    always_ff @(posedge clk or posedge rst) begin
        if (rst) stage3_reg <= '0;
        else stage3_reg <= stage3_next;
    end
    always_comb begin
        stage3_next.out_sign = stage2_reg.a_sign ^ stage2_reg.b_sign;
        stage3_next.a_mul_b_mantissa = {stage2_reg.a_implicit_leading_bit, stage2_reg.a_mantissa} * {stage2_reg.b_implicit_leading_bit, stage2_reg.b_mantissa};
        stage3_next.a_mul_b_exponent = stage2_reg.a_exponent + stage2_reg.b_exponent - {(EXPONENT_WIDTH - 1) {1'b1}};
        stage3_next.leading_one_is_MSB = stage3_next.a_mul_b_mantissa[(MANTISSA_WIDTH+1)*2-1];
        stage3_next.is_a_zero = stage2_reg.is_a_zero;
        stage3_next.is_b_zero = stage2_reg.is_b_zero;
        stage3_next.is_a_infinite = stage2_reg.is_a_infinite;
        stage3_next.is_b_infinite = stage2_reg.is_b_infinite;
        stage3_next.is_signaling_nan_a = stage2_reg.is_signaling_nan_a;
        stage3_next.is_signaling_nan_b = stage2_reg.is_signaling_nan_b;
        stage3_next.is_quiet_nan_a = stage2_reg.is_quiet_nan_a;
        stage3_next.is_quiet_nan_b = stage2_reg.is_quiet_nan_b;
        stage3_next.quiet_nan = {1'b1, {EXPONENT_WIDTH{1'b1}}, 1'b1, {(MANTISSA_WIDTH - 1) {((EXPONENT_WIDTH == 4 && MANTISSA_WIDTH == 3) ? 1'b1 : 1'b0)}}};
        stage3_next.bias = {(EXPONENT_WIDTH - 1) {1'b1}};
    end

    // Stage 4: Normalize, prepare rounding
    always_ff @(posedge clk or posedge rst) begin
        if (rst) stage4_reg <= '0;
        else stage4_reg <= stage4_next;
    end
    always_comb begin
        stage4_next.is_a_zero = stage3_reg.is_a_zero;
        stage4_next.is_b_zero = stage3_reg.is_b_zero;
        stage4_next.is_a_infinite = stage3_reg.is_a_infinite;
        stage4_next.is_b_infinite = stage3_reg.is_b_infinite;
        stage4_next.is_signaling_nan_a = stage3_reg.is_signaling_nan_a;
        stage4_next.is_signaling_nan_b = stage3_reg.is_signaling_nan_b;
        stage4_next.is_quiet_nan_a = stage3_reg.is_quiet_nan_a;
        stage4_next.is_quiet_nan_b = stage3_reg.is_quiet_nan_b;
        stage4_next.quiet_nan = stage3_reg.quiet_nan;
        stage4_next.bias = stage3_reg.bias;
        stage4_next.a_mul_b_exponent = stage3_reg.a_mul_b_exponent;
        stage4_next.leading_one_is_MSB = stage3_reg.leading_one_is_MSB;
        stage4_next.out_sign = stage3_reg.out_sign;
        if (stage3_reg.is_signaling_nan_a || stage3_reg.is_signaling_nan_b || stage3_reg.is_quiet_nan_a || stage3_reg.is_quiet_nan_b) begin
            stage4_next.non_rounded_exponent = 0;
            stage4_next.non_rounded_mantissa = 0;
            stage4_next.additional_mantissa_bits = 0;
        end else begin
            stage4_next.non_rounded_exponent = (stage3_reg.is_a_zero || stage3_reg.is_b_zero) ? 0 : stage3_reg.a_mul_b_exponent[EXPONENT_WIDTH-1:0] + (stage3_reg.leading_one_is_MSB ? 1 : 0);
            stage4_next.non_rounded_mantissa = stage3_reg.leading_one_is_MSB ? stage3_reg.a_mul_b_mantissa[2*MANTISSA_WIDTH:MANTISSA_WIDTH+1] : stage3_reg.a_mul_b_mantissa[2*MANTISSA_WIDTH-1:MANTISSA_WIDTH];
            stage4_next.additional_mantissa_bits = stage3_reg.leading_one_is_MSB ? stage3_reg.a_mul_b_mantissa[MANTISSA_WIDTH:0] : stage3_reg.a_mul_b_mantissa[MANTISSA_WIDTH-1:0] << 1;
        end
    end

    logic [MANTISSA_WIDTH-1:0] rounded_mantissa;
    logic [EXPONENT_WIDTH-1:0] rounded_exponent;
    logic rounded_overflow_flag;
    result_rounder #(EXPONENT_WIDTH, MANTISSA_WIDTH, ROUND_TO_NEAREST_TIES_TO_EVEN, MANTISSA_WIDTH + 1) result_rounder_block (
        .non_rounded_exponent(stage4_reg.non_rounded_exponent),
        .non_rounded_mantissa(stage4_reg.non_rounded_mantissa),
        .rounding_bits(stage4_reg.additional_mantissa_bits),
        .rounded_exponent(rounded_exponent),
        .rounded_mantissa(rounded_mantissa),
        .overflow_flag(rounded_overflow_flag)
    );

    // Stage 5: Rounding, pack result, set flags
    always_ff @(posedge clk or posedge rst) begin
        if (rst) stage5_reg <= '0;
        else stage5_reg <= stage5_next;
    end
    always_comb begin
        stage5_next.underflow_flag = 1'b0;
        stage5_next.overflow_flag = 1'b0;
        stage5_next.invalid_operation_flag = 1'b0;
        stage5_next.out_sign = stage4_reg.out_sign;
        if (stage4_reg.is_signaling_nan_a || stage4_reg.is_signaling_nan_b || stage4_reg.is_quiet_nan_a || stage4_reg.is_quiet_nan_b) begin
            stage5_next.out = stage4_reg.quiet_nan;
            stage5_next.invalid_operation_flag = 1'b1;
        end else if ((stage4_reg.is_a_zero && stage4_reg.is_b_infinite) || (stage4_reg.is_b_zero && stage4_reg.is_a_infinite)) begin
            stage5_next.out = stage4_reg.quiet_nan;
            stage5_next.invalid_operation_flag = 1'b1;
        end else begin
            if (stage4_reg.a_mul_b_exponent < 0 || (stage4_reg.a_mul_b_exponent[EXPONENT_WIDTH+1-1:0] == 0 && stage4_reg.leading_one_is_MSB == 1'b0)) begin
                stage5_next.out_exponent = 0;
                stage5_next.out_mantissa = 0;
                stage5_next.underflow_flag = 1'b1;
            end else if (stage4_reg.a_mul_b_exponent[EXPONENT_WIDTH+1-1:0] >= {EXPONENT_WIDTH{1'b1}} || (stage4_reg.a_mul_b_exponent[EXPONENT_WIDTH-1:0] == ({EXPONENT_WIDTH{1'b1}} - 1) && stage4_reg.leading_one_is_MSB)) begin
                stage5_next.out_exponent = {EXPONENT_WIDTH{1'b1}};
                stage5_next.out_mantissa = {MANTISSA_WIDTH{1'b0}};
                stage5_next.overflow_flag = 1'b1;
            end else begin
                
                stage5_next.out_mantissa = rounded_mantissa;
                stage5_next.out_exponent = rounded_exponent;
                stage5_next.overflow_flag = rounded_overflow_flag;
            end
            stage5_next.out = {stage5_next.out_sign, stage5_next.out_exponent, stage5_next.out_mantissa};
        end
    end

    // Output assignments
    always_comb begin
        out = stage5_reg.out;
        underflow_flag = stage5_reg.underflow_flag;
        overflow_flag = stage5_reg.overflow_flag;
        invalid_operation_flag = stage5_reg.invalid_operation_flag;
    end
endmodule

`endif