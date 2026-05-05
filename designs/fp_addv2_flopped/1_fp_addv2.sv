// FP adder code from: 
// https://github.com/V0XNIHILI/parametrizable-floating-point-verilog (with minor modifications)

// Helper modules
module leading_one_detector #(
    parameter int WIDTH = 8
) (
    input [WIDTH-1:0] value,
    output reg [$clog2(WIDTH)-1:0] position,
    output reg has_leading_one
);

    integer i;

    // Required to support Icarus Verilog
    reg stop_bit;

    always_comb begin
        position = {$clog2(WIDTH) {1'bx}};
        has_leading_one = value != 0;
        stop_bit = 1'b0;

        for (i = WIDTH - 1; i >= 0; i = i - 1) begin
            if (value[i] == 1'b1 && stop_bit == 1'b0) begin
                // Index selection to avoid the error:
                // "Operator ASSIGN expects 5 bits on the Assign RHS, but Assign RHS's VARREF 'i' generates 32 bits."
                // from Verilator.
                position = i[$clog2(WIDTH)-1:0];

                $display("Found leading one at position %d", position);

`ifdef __ICARUS__
                stop_bit = 1'b1;
`else
                break;
`endif
            end
        end
    end

endmodule


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

// MAIN MODULE - fp adder

module FP_ADD #(
    parameter int EXPONENT_WIDTH = 8,
    parameter int MANTISSA_WIDTH = 23,
    parameter int ROUND_TO_NEAREST_TIES_TO_EVEN = 1,  // 0: round to zero (chopping last bits), 1: round to nearest
    parameter int IGNORE_SIGN_BIT_FOR_NAN = 1,
    localparam int FloatBitWidth = EXPONENT_WIDTH + MANTISSA_WIDTH + 1
) (
    input [FloatBitWidth-1:0] a,
    input [FloatBitWidth-1:0] b,
    output reg [FloatBitWidth-1:0] out,

    // Subtraction flag
    input subtract,

    // Exception flags
    output reg underflow_flag,
    output reg overflow_flag,
    output reg invalid_operation_flag
);

    localparam int RoundingBits = MANTISSA_WIDTH;
    localparam int TrueRoundingBits = RoundingBits * ROUND_TO_NEAREST_TIES_TO_EVEN;

    // Unpack input floats

    wire a_sign, temp_b_sign, b_sign;
    wire a_implicit_leading_bit, b_implicit_leading_bit;
    wire [EXPONENT_WIDTH-1:0] a_exponent, b_exponent;
    wire [MANTISSA_WIDTH-1:0] a_mantissa, b_mantissa;

    assign {a_sign, a_exponent, a_mantissa} = a;
    assign {temp_b_sign, b_exponent, b_mantissa} = b;

    assign b_sign = subtract ? ~temp_b_sign : temp_b_sign;

    assign a_implicit_leading_bit = !(a_exponent == 0);
    assign b_implicit_leading_bit = !(b_exponent == 0);

    // Result variables
    reg out_sign;
    reg [EXPONENT_WIDTH-1:0] out_exponent;
    reg [MANTISSA_WIDTH-1:0] out_mantissa;

    // Temporary variables
    reg signed [EXPONENT_WIDTH+1-1:0] exponent_difference;
    reg [EXPONENT_WIDTH+1-1:0] positive_exponent;  // Extra step required for taking the correct number of bits in Verilator
    reg [EXPONENT_WIDTH-1:0] abs_exponent_difference;

    reg [MANTISSA_WIDTH+1+TrueRoundingBits-1:0] a_shifted_mantissa, b_shifted_mantissa;  // TrueRoundingBits extra bits for rounding

    reg signed [MANTISSA_WIDTH+2+TrueRoundingBits+1-1:0] summed_mantissa;
    reg [MANTISSA_WIDTH+2+TrueRoundingBits-1:0] positive_summed_mantissa;
    reg [MANTISSA_WIDTH+2+TrueRoundingBits-1:0] normalized_mantissa;
    reg [MANTISSA_WIDTH-1:0] non_rounded_mantissa;

    reg [RoundingBits-1:0] additional_mantissa_bits;
    reg negate_exponent_update;
    reg signed [EXPONENT_WIDTH+2-1:0] temp_exponent;

    // Extra statement used to avoid WIDTHTRUNC from Verilator
    wire [32-1:0] int_exponent_change_from_mantissa = MANTISSA_WIDTH + TrueRoundingBits - leading_one_pos;
    
    wire signed [3+$clog2(MANTISSA_WIDTH)+$clog2(TrueRoundingBits)-1:0] exponent_change_from_mantissa = int_exponent_change_from_mantissa[3+$clog2(MANTISSA_WIDTH)+$clog2(TrueRoundingBits)-1:0];

    wire is_E4M3 = EXPONENT_WIDTH == 4 && MANTISSA_WIDTH == 3;

    // Special pre-defined values. {MANTISSA_WIDTH-1{...}} could also have been {MANTISSA_WIDTH-1{1'bX}}
    // but like this it explicitly supports the E4M3 variant.
    wire [FloatBitWidth-1:0] quiet_nan = {1'b1, {EXPONENT_WIDTH{1'b1}}, 1'b1, {(MANTISSA_WIDTH - 1) {is_E4M3 ? 1'b1 : 1'b0}}};

    // Leading one detection

    wire [$clog2(MANTISSA_WIDTH+2+TrueRoundingBits)-1:0] leading_one_pos;
    wire has_leading_one;

    leading_one_detector #(
        .WIDTH(MANTISSA_WIDTH + 2 + TrueRoundingBits)
    ) leading_one_detector_summed_mantissa (
        .value(positive_summed_mantissa),
        .position(leading_one_pos),
        .has_leading_one(has_leading_one)
    );

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

    reg [MANTISSA_WIDTH-1:0] rounded_mantissa;
    reg [EXPONENT_WIDTH-1:0] rounded_exponent;
    reg rounded_overflow_flag;

    result_rounder #(
        .EXPONENT_WIDTH(EXPONENT_WIDTH),
        .MANTISSA_WIDTH(MANTISSA_WIDTH),
        .ROUND_TO_NEAREST_TIES_TO_EVEN(ROUND_TO_NEAREST_TIES_TO_EVEN),
        .ROUNDING_BITS(RoundingBits)
    ) result_rounder_block (
        // We need to remove the extra bits from temp_exponent, which
        // are normally used for overflow detection.
        .non_rounded_exponent(temp_exponent[EXPONENT_WIDTH-1:0]),
        .non_rounded_mantissa(non_rounded_mantissa),
        .rounding_bits(additional_mantissa_bits),
        .rounded_exponent(rounded_exponent),
        .rounded_mantissa(rounded_mantissa),
        .overflow_flag(rounded_overflow_flag)
    );

    // Perform actual addition operation

    always_comb begin
        underflow_flag = 1'b0;
        overflow_flag = 1'b0;
        invalid_operation_flag = 1'b0;

        // We set these to avoid latch inference for Verilator but in fact these are not used in this path
        out_sign = 1'bx;
        out_exponent = {EXPONENT_WIDTH{1'bx}};
        out_mantissa = {MANTISSA_WIDTH{1'bx}};
        non_rounded_mantissa = {MANTISSA_WIDTH{1'bx}};
        positive_summed_mantissa = {(MANTISSA_WIDTH + 2 + TrueRoundingBits) {1'bx}};
        normalized_mantissa = {(MANTISSA_WIDTH + 2 + TrueRoundingBits) {1'bx}};
        exponent_difference = {(EXPONENT_WIDTH + 1) {1'bx}};
        positive_exponent = {(EXPONENT_WIDTH + 1) {1'bx}};
        abs_exponent_difference = {EXPONENT_WIDTH{1'bx}};
        a_shifted_mantissa = {(MANTISSA_WIDTH + 1 + TrueRoundingBits) {1'bx}};
        b_shifted_mantissa = {(MANTISSA_WIDTH + 1 + TrueRoundingBits) {1'bx}};
        summed_mantissa = {(MANTISSA_WIDTH + 2 + TrueRoundingBits + 1) {1'bx}};
        additional_mantissa_bits = {RoundingBits{1'bx}};
        temp_exponent = {(EXPONENT_WIDTH + 2) {1'bx}};
        negate_exponent_update = 1'bx;

        if (is_signaling_nan_a || is_signaling_nan_b || is_quiet_nan_a || is_quiet_nan_b) begin
            // Result is QNaN due to one or both of the operands being NaN

            out = quiet_nan;

            if ((is_signaling_nan_a || is_signaling_nan_b) || ((is_quiet_nan_a && (!is_signaling_nan_b && !is_quiet_nan_b)) || (is_quiet_nan_b && (!is_signaling_nan_a && !is_quiet_nan_a)))) begin
                invalid_operation_flag = 1'b1;
            end
        end else
        // Cover the following cases:
        // -Inf + +Inf = QNaN
        // -Inf - -Inf = QNaN
        // +Inf - +Inf = QNaN
        // +Inf + -Inf = QNaN
        if ((is_a_infinite && is_b_infinite) && ((a_sign && !b_sign && !subtract) || (a_sign && b_sign && subtract) || (!a_sign && !b_sign && subtract) || (!a_sign && b_sign && !subtract))) begin
            // Result is QNaN due to the fact that two opposite infinities were added

            out = quiet_nan;

            invalid_operation_flag = 1'b1;
        end else
        // Handle two special cases that otherwise are not correctly covered by the logic in the else block;
        // -Inf + -Inf = -Inf and +Inf + +Inf = +Inf
        if ((is_a_infinite && is_b_infinite) && !subtract && a_sign == b_sign) begin
            // Overflow detected

            out = {a_sign, {EXPONENT_WIDTH{1'b1}}, {MANTISSA_WIDTH{1'b0}}};

            overflow_flag = 1'b1;
        end else
        // Perform regular addition operation
        begin
            exponent_difference = a_exponent - b_exponent;
            out_sign = 1'b0;

            a_shifted_mantissa = {a_implicit_leading_bit, a_mantissa} << TrueRoundingBits;
            b_shifted_mantissa = {b_implicit_leading_bit, b_mantissa} << TrueRoundingBits;

            if (exponent_difference > 0) begin
                // A exponent is bigger than B exponent

                abs_exponent_difference = exponent_difference[EXPONENT_WIDTH-1:0];
                out_exponent = a_exponent;
                b_shifted_mantissa = b_shifted_mantissa >> abs_exponent_difference;
            end else if (exponent_difference == 0) begin
                // A exponent is equal to B exponent

                abs_exponent_difference = 0;
                out_exponent = a_exponent;
            end else begin
                // B exponent is bigger than A exponent

                positive_exponent = -exponent_difference;
                abs_exponent_difference = positive_exponent[EXPONENT_WIDTH-1:0];
                out_exponent = b_exponent;
                a_shifted_mantissa = a_shifted_mantissa >> abs_exponent_difference;
            end

            if (a_sign == b_sign) begin
                summed_mantissa = a_shifted_mantissa + b_shifted_mantissa;
                out_sign = a_sign;
                negate_exponent_update = 1'b0;
            end else begin
                if (a_sign == 1'b1) begin
                    summed_mantissa = b_shifted_mantissa - a_shifted_mantissa;
                end else
                // Effectively: 'else if (b_sign == 1'b1)'
                begin
                    summed_mantissa = a_shifted_mantissa - b_shifted_mantissa;
                end

                if (summed_mantissa < 0) begin
                    // Result is negative due to mantissa summation being negative

                    summed_mantissa = -summed_mantissa;
                    out_sign = 1'b1;
                end

                negate_exponent_update = 1'b1;
            end

            // At this line, summed_mantissa is always positive
            positive_summed_mantissa = summed_mantissa[MANTISSA_WIDTH+2+TrueRoundingBits-1:0];

            // Multiply with leading_one_pos to only shift if there is a leading 1
            // Separate shift statements to handle the case of a shift with a negative amount (i.e., shift the other direction)
            normalized_mantissa = leading_one_pos >= (MANTISSA_WIDTH + RoundingBits) ? positive_summed_mantissa >> (leading_one_pos - (MANTISSA_WIDTH + RoundingBits)) : positive_summed_mantissa << ((MANTISSA_WIDTH + RoundingBits) - leading_one_pos);
            // In case there is no leading one, it means that the mantissa is zero (for example when a = 0)
            // This weird if-statement with if exponent_change_from_mantissa is larger than zero is required because else the subtraction does not work correctly
            // Furthermore, it is XORed with negate_exponent_update to make sure that the subtraction is done at the right moment, else sometimes
            // when dealing with negative + positive numbers, the temp_exponent is not correct.
            temp_exponent = has_leading_one ? ((exponent_change_from_mantissa >= 0) ^ negate_exponent_update ? out_exponent + exponent_change_from_mantissa : out_exponent - exponent_change_from_mantissa) : 0;

            if (temp_exponent < 0) begin
                // Underflow detected

                // Note: out_sign is already set
                out_exponent = 0;
                out_mantissa = 0;

                underflow_flag = 1'b1;
            end else if (temp_exponent >= {EXPONENT_WIDTH{1'b1}}) begin
                // Overflow detected

                // Note: out_sign is already set
                out_exponent = {EXPONENT_WIDTH{1'b1}};
                out_mantissa = {MANTISSA_WIDTH{1'b0}};

                overflow_flag = 1'b1;
            end else
            // In the normal case
            begin
                // No overflow or underflow detected

                // These two values are fed into the result_rounder module
                non_rounded_mantissa = normalized_mantissa[MANTISSA_WIDTH+TrueRoundingBits-1:TrueRoundingBits];
                additional_mantissa_bits = normalized_mantissa[RoundingBits-1:0];

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