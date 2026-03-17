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
module FP_MUL #(
    parameter int EXPONENT_WIDTH = 8,
    parameter int MANTISSA_WIDTH = 23,
    parameter int ROUND_TO_NEAREST_TIES_TO_EVEN = 1,  // 0: round to zero (chopping last bits), 1: round to nearest
    parameter int IGNORE_SIGN_BIT_FOR_NAN = 1,
    localparam int FloatBitWidth = EXPONENT_WIDTH + MANTISSA_WIDTH + 1
) (
    input [FloatBitWidth-1:0] a,
    input [FloatBitWidth-1:0] b,
    output reg [FloatBitWidth-1:0] out,

    // Exception flags
    output reg underflow_flag,
    output reg overflow_flag,
    output reg invalid_operation_flag
);

    // Unpack input floats

    wire a_sign, b_sign;
    wire a_implicit_leading_bit, b_implicit_leading_bit;
    wire [EXPONENT_WIDTH-1:0] a_exponent, b_exponent;
    wire [MANTISSA_WIDTH-1:0] a_mantissa, b_mantissa;

    assign {a_sign, a_exponent, a_mantissa} = a;
    assign {b_sign, b_exponent, b_mantissa} = b;

    assign a_implicit_leading_bit = !(a_exponent == 0);
    assign b_implicit_leading_bit = !(b_exponent == 0);

    // Result variables
    reg out_sign;
    reg [EXPONENT_WIDTH-1:0] out_exponent;
    reg [MANTISSA_WIDTH-1:0] out_mantissa, non_rounded_mantissa;

    // Temporary variables
    reg [(MANTISSA_WIDTH+1)*2-1:0] a_mul_b_mantissa;
    reg [MANTISSA_WIDTH+1-1:0] additional_mantissa_bits;
    reg is_halfway;
    reg signed [EXPONENT_WIDTH+2-1:0] a_mul_b_exponent;
    reg [EXPONENT_WIDTH-1:0] non_rounded_exponent;
    reg leading_one_is_MSB;

    wire is_E4M3 = EXPONENT_WIDTH == 4 && MANTISSA_WIDTH == 3;

    // Special pre-defined values. {MANTISSA_WIDTH-1{...}} could also have been {MANTISSA_WIDTH-1{1'bX}}
    // but like this it explicitly supports the E4M3 variant.
    wire [FloatBitWidth-1:0] quiet_nan = {1'b1, {EXPONENT_WIDTH{1'b1}}, 1'b1, {(MANTISSA_WIDTH - 1) {is_E4M3 ? 1'b1 : 1'b0}}};
    wire [EXPONENT_WIDTH-1-1:0] bias = {(EXPONENT_WIDTH - 1) {1'b1}};

    // Find special float values

    wire is_a_infinite, is_b_infinite;
    wire is_a_zero, is_b_zero;
    wire is_signaling_nan_a, is_signaling_nan_b;
    wire is_quiet_nan_a, is_quiet_nan_b;

    is_special_float #(
        .EXPONENT_WIDTH(EXPONENT_WIDTH),
        .MANTISSA_WIDTH(MANTISSA_WIDTH),
        .IGNORE_SIGN_BIT_FOR_NAN(IGNORE_SIGN_BIT_FOR_NAN)
    ) is_special_float_a (
        .a(a),
        .is_infinite(is_a_infinite),
        .is_zero(is_a_zero),
        .is_signaling_nan(is_signaling_nan_a),
        .is_quiet_nan(is_quiet_nan_a),
        .is_subnormal()
    );

    is_special_float #(
        .EXPONENT_WIDTH(EXPONENT_WIDTH),
        .MANTISSA_WIDTH(MANTISSA_WIDTH),
        .IGNORE_SIGN_BIT_FOR_NAN(IGNORE_SIGN_BIT_FOR_NAN)
    ) is_special_float_b (
        .a(b),
        .is_infinite(is_b_infinite),
        .is_zero(is_b_zero),
        .is_signaling_nan(is_signaling_nan_b),
        .is_quiet_nan(is_quiet_nan_b),
        .is_subnormal()
    );

    // Rounding

    wire [MANTISSA_WIDTH-1:0] rounded_mantissa;
    wire [EXPONENT_WIDTH-1:0] rounded_exponent;
    wire rounded_overflow_flag;

    result_rounder #(
        .EXPONENT_WIDTH(EXPONENT_WIDTH),
        .MANTISSA_WIDTH(MANTISSA_WIDTH),
        .ROUND_TO_NEAREST_TIES_TO_EVEN(ROUND_TO_NEAREST_TIES_TO_EVEN),
        .ROUNDING_BITS(MANTISSA_WIDTH + 1)
    ) result_rounder_block (
        .non_rounded_exponent(non_rounded_exponent),
        .non_rounded_mantissa(non_rounded_mantissa),
        .rounding_bits(additional_mantissa_bits),
        .rounded_exponent(rounded_exponent),
        .rounded_mantissa(rounded_mantissa),
        .overflow_flag(rounded_overflow_flag)
    );

    // Perform actual multiplication operation

    always_comb begin
        underflow_flag = 1'b0;
        overflow_flag = 1'b0;
        invalid_operation_flag = 1'b0;

        // We set these to avoid latch inference for Verilators but in fact these are not used in this path
        out_sign = 1'bx;
        out_exponent = {EXPONENT_WIDTH{1'bx}};
        out_mantissa = {MANTISSA_WIDTH{1'bx}};
        non_rounded_mantissa = {MANTISSA_WIDTH{1'bx}};
        a_mul_b_mantissa = {((MANTISSA_WIDTH + 1) * 2) {1'bx}};
        additional_mantissa_bits = {(MANTISSA_WIDTH + 1) {1'bx}};
        is_halfway = 1'bx;
        a_mul_b_exponent = {(EXPONENT_WIDTH + 2) {1'bx}};
        non_rounded_exponent = {EXPONENT_WIDTH{1'bx}};
        leading_one_is_MSB = 1'bx;

        // TODO: handle subnormal numbers
        // TODO: make sure that all operations of special values are readily handled by the current code

        if (is_signaling_nan_a || is_signaling_nan_b || is_quiet_nan_a || is_quiet_nan_b) begin
            // Result is QNaN due to one or both of the operands being NaN

            out = quiet_nan;

            if ((is_signaling_nan_a || is_signaling_nan_b) || ((is_quiet_nan_a && (!is_signaling_nan_b && !is_quiet_nan_b)) || (is_quiet_nan_b && (!is_signaling_nan_a && !is_quiet_nan_a)))) begin
                invalid_operation_flag = 1'b1;
            end
        end else if ((is_a_zero && is_b_infinite) || (is_b_zero && is_a_infinite)) begin
            // Result is QNaN due to one of the operands being zero and the other being infinite

            out = quiet_nan;

            invalid_operation_flag = 1'b1;
        end else begin
            // Result is probably not QNaN

            out_sign = a_sign ^ b_sign;
            a_mul_b_mantissa = {a_implicit_leading_bit, a_mantissa} * {b_implicit_leading_bit, b_mantissa};
            a_mul_b_exponent = a_exponent + b_exponent - bias;

            leading_one_is_MSB = a_mul_b_mantissa[(MANTISSA_WIDTH+1)*2-1];

            // If the exponent is negative (first condition), the number is out of the IEEE 754
            // single precision normalized numbers range; in this case the output is signaled to 0
            // and an underflow flag is asserted. In the second case, the exponent is zero and it
            // cannot be compensated by normalization, so there is also an underflow.
            if (a_mul_b_exponent < 0 || (a_mul_b_exponent[EXPONENT_WIDTH+1-1:0] == 0 && leading_one_is_MSB == 1'b0)) begin
                // Underflow detected

                // Note: out_sign is already set
                out_exponent = 0;
                out_mantissa = 0;

                underflow_flag = 1'b1;
            end else
            // If overflow is detected. Overflow is present when the resulting exponent is equal to
            // or larger than 111...111 (all ones value with the same width as the exponent). For FP32,
            // this value is 255. Overflow can also occur when the exponent is equal to 111...110 and
            // +1 will be done for normalization, leading to 111...111: again, overflow.
            if (a_mul_b_exponent[EXPONENT_WIDTH+1-1:0] >= {EXPONENT_WIDTH{1'b1}} || (a_mul_b_exponent[EXPONENT_WIDTH-1:0] == ({EXPONENT_WIDTH{1'b1}} - 1) && leading_one_is_MSB)) begin
                // Overflow detected

                // Note: out_sign is already set
                out_exponent = {EXPONENT_WIDTH{1'b1}};
                out_mantissa = {MANTISSA_WIDTH{1'b0}};

                overflow_flag = 1'b1;
            end else
            // In the normal case
            begin
                // No overflow or underflow detected

                // Note: out_sign is already set
                // Handle the special case where one of the inputs is zero: the output exponent
                // should then also be explicitly set to 0.
                non_rounded_exponent = (is_a_zero || is_b_zero) ? 0 : a_mul_b_exponent[EXPONENT_WIDTH-1:0] + (leading_one_is_MSB ? 1 : 0);
                non_rounded_mantissa = leading_one_is_MSB ? a_mul_b_mantissa[2*MANTISSA_WIDTH:MANTISSA_WIDTH+1] : a_mul_b_mantissa[2*MANTISSA_WIDTH-1:MANTISSA_WIDTH];
                additional_mantissa_bits = leading_one_is_MSB ? a_mul_b_mantissa[MANTISSA_WIDTH:0] : a_mul_b_mantissa[MANTISSA_WIDTH-1:0] << 1;

                // Then the result is rounded
                out_mantissa = rounded_mantissa;
                out_exponent = rounded_exponent;
                overflow_flag = rounded_overflow_flag;
            end

            out = {out_sign, out_exponent, out_mantissa};
        end
    end
endmodule

`endif