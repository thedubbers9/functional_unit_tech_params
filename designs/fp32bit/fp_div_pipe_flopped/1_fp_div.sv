// FP divider code from: https://github.com/andmiele/SystemVerilogALUandFPUmodules

//-----------------------------------------------------------------------------
// Copyright 2024 Andrea Miele
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//-----------------------------------------------------------------------------

// fpDivider.sv
// IEEE Floating Point divider

// Helper modules

// one-hot to binary encoded
module encoder
#(parameter N = 32)
(
    input logic [N - 1 : 0] x,
    output logic [$clog2(N) - 1 : 0] out
);

always_comb
begin
    out = {$clog2(N){1'b0}};
    for (int unsigned i = 0; i < N; i++)
    begin
        if (x[i])
            out |= $clog2(N)'(i); // cast i to $clog2(N) width
    end
end
endmodule

// returns one-hot position of most significant bit
// repeated cell   out[0] = x[0] & 1, out[1] = x[1] & ~x[0] & 1, out[2] = x[2] & ~x[1] & ~x[0] & 1
module combArbiter
#(parameter N = 32)
(  
    input logic [N - 1 : 0] x,
    output logic [N - 1 : 0] out
);
logic [N - 1 : 0] notFoundYet;

genvar i;
assign notFoundYet[0] = 1'b1;

generate
for(i = 1; i < N; i++)
begin: arbiterFor
    assign notFoundYet[i] = (~x[i - 1]) & notFoundYet[i - 1];
end
endgenerate
assign out = x & notFoundYet;
endmodule

// returns number of most sigificant bits set to zero
module zeroMSBCounter
#(parameter N = 32)
(  
    input logic [N - 1 : 0] x,
    output logic [$clog2(N) - 1 : 0] out
);
logic [N - 1 : 0] xi;
logic [N - 1 : 0] caOut;
genvar i;
generate
for(i = 0; i < N; i++)
begin: invertbits
   assign xi[i] = x[N - 1 - i];
end
endgenerate

combArbiter #(N) ca(.x(xi), .out(caOut));
encoder #(N) enc(.x(caOut), .out(out));
endmodule

// MAIN MODULE
module FP_DIV
#(parameter BITS = 32, parameter MANTISSA_BITS = 23, parameter EXPONENT_BITS = 8)
(
 input logic clk,
 input logic rst,
 input logic [BITS - 1 : 0] x,
 input logic [BITS - 1 : 0] y,
 output logic [BITS - 1 : 0] out
);

localparam exponentBias = (1 << (EXPONENT_BITS - 1)) - 1;
localparam maxExponent = (1 << (EXPONENT_BITS - 1)) - 1;
localparam minExponent = 1 - maxExponent;
localparam minBiasedExponent = minExponent + exponentBias;
localparam maxBiasedExponent = maxExponent + exponentBias;
localparam infExponent = maxExponent + 1;
localparam infBiasedExponent = maxExponent + 1 + exponentBias;
localparam zeroOrDenormBiasedExponent = minExponent - 1 + exponentBias;
localparam nanMantissa = 1 << (MANTISSA_BITS - 1); // must be different than 0


// Stage 1 registers
logic [MANTISSA_BITS - 1 : 0] xM_s1, yM_s1;
logic [EXPONENT_BITS - 1 : 0] xE_s1, yE_s1;
logic xS_s1, yS_s1;
logic [BITS - 1 : 0] x_s1, y_s1;
logic stage1_valid;

// Stage 2 registers
logic [MANTISSA_BITS + 1 - 1 : 0] xMantissa_s2, yMantissa_s2;
logic [EXPONENT_BITS - 1 : 0] xExponent_s2, yExponent_s2;
logic xS_s2, yS_s2;
logic [BITS - 1 : 0] x_s2, y_s2;
logic stage2_valid;

// Stage 3 registers
logic [MANTISSA_BITS + 1 - 1 : 0] zMantissa_s3;
logic [EXPONENT_BITS - 1 : 0] zExponent_s3;
logic zSign_s3;
logic [BITS - 1 : 0] out_s3;
logic stage3_valid;


// Stage 1: Input unpacking
always_ff @(posedge clk or posedge rst) begin
	if (rst) begin
		xM_s1 <= 0;
		yM_s1 <= 0;
		xE_s1 <= 0;
		yE_s1 <= 0;
		xS_s1 <= 0;
		yS_s1 <= 0;
		x_s1 <= 0;
		y_s1 <= 0;
		stage1_valid <= 0;
	end else begin
		xM_s1 <= x[MANTISSA_BITS - 1 : 0];
		yM_s1 <= y[MANTISSA_BITS - 1 : 0];
		xE_s1 <= x[BITS - 2 : BITS - 1 - EXPONENT_BITS];
		yE_s1 <= y[BITS - 2 : BITS - 1 - EXPONENT_BITS];
		xS_s1 <= x[BITS - 1];
		yS_s1 <= y[BITS - 1];
		x_s1 <= x;
		y_s1 <= y;
		stage1_valid <= 1;
	end
end

// Stage 2: Denormal/regular handling
always_ff @(posedge clk or posedge rst) begin
	if (rst) begin
		xMantissa_s2 <= 0;
		yMantissa_s2 <= 0;
		xExponent_s2 <= 0;
		yExponent_s2 <= 0;
		xS_s2 <= 0;
		yS_s2 <= 0;
		x_s2 <= 0;
		y_s2 <= 0;
		stage2_valid <= 0;
	end else if (stage1_valid) begin
		xMantissa_s2[MANTISSA_BITS - 1 : 0] <= xM_s1;
		yMantissa_s2[MANTISSA_BITS - 1 : 0] <= yM_s1;
		if (xE_s1 == zeroOrDenormBiasedExponent) begin
			xExponent_s2 <= minBiasedExponent;
			xMantissa_s2[MANTISSA_BITS] <= 1'b0;
		end else begin
			xExponent_s2 <= xE_s1;
			xMantissa_s2[MANTISSA_BITS] <= 1'b1;
		end
		if (yE_s1 == zeroOrDenormBiasedExponent) begin
			yExponent_s2 <= minBiasedExponent;
			yMantissa_s2[MANTISSA_BITS] <= 1'b0;
		end else begin
			yExponent_s2 <= yE_s1;
			yMantissa_s2[MANTISSA_BITS] <= 1'b1;
		end
		xS_s2 <= xS_s1;
		yS_s2 <= yS_s1;
		x_s2 <= x_s1;
		y_s2 <= y_s1;
		stage2_valid <= 1;
	end
end

// Stage 3: Finalization (core computation, rounding, special cases)
// Local signals for stage 3
logic [2 * (MANTISSA_BITS + 1) + 1 - 1 : 0] xNormalizedExtendedMantissa_s3;
logic [MANTISSA_BITS + 1 - 1 : 0] yNormalizedMantissa_s3;
logic [(MANTISSA_BITS + 3) - 1 : 0] quotient_s3;
logic [(MANTISSA_BITS + 3) - 1 : 0] remainder_s3;
logic [$clog2((MANTISSA_BITS + 3)) - 1 : 0] normalizeShiftAmount_s3;
logic [$clog2((MANTISSA_BITS + 1)) - 1 : 0] normalizeShiftAmountX_s3;
logic [$clog2((MANTISSA_BITS + 1)) - 1 : 0] normalizeShiftAmountY_s3;
logic [EXPONENT_BITS + 1 : 0] xNormalizedExponent_s3, yNormalizedExponent_s3;
logic [EXPONENT_BITS + 1 : 0] tentativeExponent_s3, tentativeExponent2_s3;
logic [EXPONENT_BITS + 1 : 0] rightShiftAmount_s3;
logic guardBit_s3, roundBit_s3, stickyBit_s3;
logic guardBit2_s3, roundBit2_s3, stickyBit2_s3;
logic [MANTISSA_BITS + 1 - 1 : 0] normalizedMantissa_s3, normalizedMantissa2_s3;
logic roundFlag_s3, shiftUnderflowFlag_s3;

always_ff @(posedge clk or posedge rst) begin
	if (rst) begin
		zMantissa_s3 <= 0;
		zExponent_s3 <= 0;
		zSign_s3 <= 0;
		out_s3 <= 0;
		stage3_valid <= 0;
	end else if (stage2_valid) begin
		// Normalization shift amounts
		zeroMSBCounter #(.N((MANTISSA_BITS + 3))) msbZerosSum_inst(quotient_s3, normalizeShiftAmount_s3);
		zeroMSBCounter #(.N((MANTISSA_BITS + 1))) msbZerosSumX_inst(xMantissa_s2, normalizeShiftAmountX_s3);
		zeroMSBCounter #(.N((MANTISSA_BITS + 1))) msbZerosSumY_inst(yMantissa_s2, normalizeShiftAmountY_s3);

		// Exponent normalization
		xNormalizedExponent_s3 = xExponent_s2 - normalizeShiftAmountX_s3;
		yNormalizedExponent_s3 = yExponent_s2 - normalizeShiftAmountY_s3;
		xNormalizedExtendedMantissa_s3 = xMantissa_s2 << (normalizeShiftAmountX_s3 + MANTISSA_BITS + 2);
		yNormalizedMantissa_s3 = yMantissa_s2 << normalizeShiftAmountY_s3;

		// Division
		quotient_s3 = xNormalizedExtendedMantissa_s3 / yNormalizedMantissa_s3;
		remainder_s3 = xNormalizedExtendedMantissa_s3 % yNormalizedMantissa_s3;

		// Round-to-nearest extra bits
		guardBit_s3 = (normalizeShiftAmount_s3 != 0) ? (normalizeShiftAmount_s3 > 1) ? 1'b0 : quotient_s3[0] : quotient_s3[1];
		roundBit_s3 = (normalizeShiftAmount_s3 != 0) ? 1'b0 : quotient_s3[0];
		stickyBit_s3 = remainder_s3 != 0;

		// Normalized mantissa
		normalizedMantissa_s3 = (quotient_s3 << normalizeShiftAmount_s3) >> 2;

		tentativeExponent_s3 = xNormalizedExponent_s3 - yNormalizedExponent_s3 + exponentBias - normalizeShiftAmount_s3;
		shiftUnderflowFlag_s3 = $signed(tentativeExponent_s3) < $signed(minBiasedExponent);
		rightShiftAmount_s3 = minBiasedExponent - tentativeExponent_s3;
		tentativeExponent2_s3 = shiftUnderflowFlag_s3 ? tentativeExponent_s3 + rightShiftAmount_s3 : tentativeExponent_s3;

		guardBit2_s3 = (shiftUnderflowFlag_s3) ? (normalizedMantissa_s3 >> (rightShiftAmount_s3 - 1)) & 1 : guardBit_s3;
		roundBit2_s3 = (shiftUnderflowFlag_s3) ? rightShiftAmount_s3 > 1 ? (normalizedMantissa_s3 >> (rightShiftAmount_s3 - 2)) & 1 : guardBit_s3 : roundBit_s3;
		stickyBit2_s3 = stickyBit_s3 | (shiftUnderflowFlag_s3 ? ((rightShiftAmount_s3 > 2) ? (normalizedMantissa_s3 >> (rightShiftAmount_s3 - 3)) & 1 : ((rightShiftAmount_s3 > 1) ? guardBit_s3 : roundBit_s3)) : 0);

		// Normalized mantissa
		normalizedMantissa2_s3 = shiftUnderflowFlag_s3 ? normalizedMantissa_s3 >> rightShiftAmount_s3 : normalizedMantissa_s3;

		roundFlag_s3 = guardBit2_s3 && (normalizedMantissa2_s3[0] | roundBit2_s3 | stickyBit2_s3);

		// Special cases and output assignment
		if (((yExponent_s2 == infBiasedExponent) && (yMantissa_s2[MANTISSA_BITS - 1 : 0] != 0)) ||  ((xExponent_s2 == infBiasedExponent) && (xMantissa_s2[MANTISSA_BITS - 1 : 0] != 0))) begin
			zSign_s3 <= 1'b0;
			zExponent_s3 <= infBiasedExponent;
			zMantissa_s3 <= {1'b0, nanMantissa};
		end else if ((xExponent_s2 == infBiasedExponent) && (yExponent_s2 == infBiasedExponent)) begin
			zSign_s3 <= 1'b1;
			zExponent_s3 <= infBiasedExponent;
			zMantissa_s3 <= {1'b0, nanMantissa};
		end else if (xExponent_s2 == infBiasedExponent) begin
			if ((yExponent_s2 == zeroOrDenormBiasedExponent) && (yMantissa_s2[MANTISSA_BITS - 1 : 0] == 0)) begin
				zSign_s3 <= 1'b0;
				zExponent_s3 <= infBiasedExponent;
				zMantissa_s3 <= {1'b0, nanMantissa};
			end else begin
				zSign_s3 <= xS_s2 ^ yS_s2;
				zExponent_s3 <= infBiasedExponent;
				zMantissa_s3 <= 0;
			end
		end else if (yExponent_s2 == infBiasedExponent) begin
			zSign_s3 <= xS_s2 ^ yS_s2;
			zExponent_s3 <= zeroOrDenormBiasedExponent;
			zMantissa_s3 <= 0;
		end else if ((xExponent_s2 == zeroOrDenormBiasedExponent) && (xMantissa_s2[MANTISSA_BITS - 1 : 0] == 0)) begin
			if ((yExponent_s2 == zeroOrDenormBiasedExponent) && (yMantissa_s2[MANTISSA_BITS - 1 : 0] == 0)) begin
				zSign_s3 <= 1'b0;
				zExponent_s3 <= infBiasedExponent;
				zMantissa_s3 <= {1'b0, nanMantissa};
			end else begin
				zSign_s3 <= xS_s2 ^ yS_s2;
				zExponent_s3 <= zeroOrDenormBiasedExponent;
				zMantissa_s3 <= 0;
			end
		end else if ((yExponent_s2 == zeroOrDenormBiasedExponent) && (yMantissa_s2[MANTISSA_BITS - 1 : 0] == 0)) begin
			zSign_s3 <= xS_s2 ^ yS_s2;
			zExponent_s3 <= infBiasedExponent;
			zMantissa_s3 <= 0;
		end else begin
			if (roundFlag_s3 == 1'b1) begin
				zMantissa_s3 <= (tentativeExponent2_s3 < infBiasedExponent) ? normalizedMantissa2_s3 + 1 : {(MANTISSA_BITS + 1){1'b0}};
				if (normalizedMantissa2_s3 == {(MANTISSA_BITS + 1){1'b1}}) begin
					if (!(tentativeExponent2_s3 == maxBiasedExponent || tentativeExponent2_s3 == infBiasedExponent)) begin
						zExponent_s3 <= tentativeExponent2_s3[EXPONENT_BITS - 1 : 0] + 1;
					end else begin
						zExponent_s3 <= infBiasedExponent;
					end
				end else begin
					if ((tentativeExponent2_s3 == minBiasedExponent) && (normalizedMantissa2_s3[MANTISSA_BITS + 1 - 1] == 1'b0)) begin
						zExponent_s3 <= zeroOrDenormBiasedExponent;
					end else begin
						zExponent_s3 <= (tentativeExponent2_s3 < infBiasedExponent) ? tentativeExponent2_s3[EXPONENT_BITS - 1 : 0] : infBiasedExponent;
					end
				end
			end else begin
				zMantissa_s3 <= (tentativeExponent2_s3 < infBiasedExponent) ? normalizedMantissa2_s3 : {(MANTISSA_BITS + 1){1'b0}};
				if ((tentativeExponent2_s3 == minBiasedExponent) && (normalizedMantissa2_s3[MANTISSA_BITS + 1 - 1] == 1'b0)) begin
					zExponent_s3 <= zeroOrDenormBiasedExponent;
				end else begin
					zExponent_s3 <= (tentativeExponent2_s3 < infBiasedExponent) ? tentativeExponent2_s3[EXPONENT_BITS - 1 : 0] : infBiasedExponent;
				end
			end
			zSign_s3 <= xS_s2 ^ yS_s2;
		end

		// Assign outputs
		out_s3[BITS - 1] <= zSign_s3;
		out_s3[BITS - 2 : BITS - 1 - EXPONENT_BITS] <= zExponent_s3;
		out_s3[BITS - 1 - EXPONENT_BITS - 1 : 0] <= zMantissa_s3[MANTISSA_BITS + 1 - 2 : 0];
		stage3_valid <= 1;
	end
end

assign out = out_s3;

assign xNormalizedExponent = xExponent - normalizeShiftAmountX;
assign yNormalizedExponent = yExponent - normalizeShiftAmountY;
assign xNormalizedExtendedMantissa = xMantissa << normalizeShiftAmountX + MANTISSA_BITS + 2;
assign yNormalizedMantissa = yMantissa << normalizeShiftAmountY;

assign quotient = xNormalizedExtendedMantissa / yNormalizedMantissa;
assign remainder = xNormalizedExtendedMantissa % yNormalizedMantissa;

// ...existing code...