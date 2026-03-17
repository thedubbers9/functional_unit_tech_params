`define round_near_even   3'b000
`define round_minMag      3'b001
`define round_min         3'b010
`define round_max         3'b011
`define round_near_maxMag 3'b100
`define round_odd         3'b110

/*----------------------------------------------------------------------------
*----------------------------------------------------------------------------*/
`define floatControlWidth 1
`define flControl_tininessBeforeRounding 1'b0
`define flControl_tininessAfterRounding  1'b1

/*----------------------------------------------------------------------------
*----------------------------------------------------------------------------*/
`define flRoundOpt_sigMSBitAlwaysZero  1
`define flRoundOpt_subnormsAlwaysExact 2
`define flRoundOpt_neverUnderflows     4
`define flRoundOpt_neverOverflows      8

/*----------------------------------------------------------------------------
*----------------------------------------------------------------------------*/
`define flControl_default `flControl_tininessBeforeRounding

/*----------------------------------------------------------------------------
*----------------------------------------------------------------------------*/
`define HardFloat_propagateNaNPayloads

// ============================================================================
// HELPER MODULES (Defined first to avoid synthesis blackbox errors)
// ============================================================================

function integer clog2;
    input integer a;
    begin
        a = a - 1;
        for (clog2 = 0; a > 0; clog2 = clog2 + 1) a = a>>1;
    end
endfunction

module countLeadingZeros#(parameter inWidth = 1, parameter countWidth = 1) (
        input [(inWidth - 1):0] in, output [(countWidth - 1):0] count
    );
    wire [(inWidth - 1):0] reverseIn;
    reverse#(inWidth) reverse_in(in, reverseIn);
    wire [inWidth:0] oneLeastReverseIn =
        {1'b1, reverseIn} & ({1'b0, ~reverseIn} + 1);
    genvar ix;
    generate
        for (ix = 0; ix <= inWidth; ix = ix + 1) begin :Bit
            wire [(countWidth - 1):0] countSoFar;
            if (ix == 0) begin
                assign countSoFar = 0;
            end else begin
                assign countSoFar =
                    Bit[ix - 1].countSoFar | (oneLeastReverseIn[ix] ? ix : 0);
                if (ix == inWidth) assign count = countSoFar;
            end
        end
    endgenerate
endmodule

module reverse#(parameter width = 1) (
        input [(width - 1):0] in, output [(width - 1):0] out
    );
    genvar ix;
    generate
        for (ix = 0; ix < width; ix = ix + 1) begin :Bit
            assign out[ix] = in[width - 1 - ix];
        end
    endgenerate
endmodule

module fNToRecFN#(parameter expWidth = 3, parameter sigWidth = 3) (
        input [(expWidth + sigWidth - 1):0] in,
        output [(expWidth + sigWidth):0] out
    );
    localparam normDistWidth = clog2(sigWidth);
    wire sign;
    wire [(expWidth - 1):0] expIn;
    wire [(sigWidth - 2):0] fractIn;
    assign {sign, expIn, fractIn} = in;
    wire isZeroExpIn = (expIn == 0);
    wire isZeroFractIn = (fractIn == 0);
    wire [(normDistWidth - 1):0] normDist;
    countLeadingZeros#(sigWidth - 1, normDistWidth)
        countLeadingZeros(fractIn, normDist);
    wire [(sigWidth - 2):0] subnormFract = (fractIn<<normDist)<<1;
    wire [expWidth:0] adjustedExp =
        (isZeroExpIn ? normDist ^ ((1<<(expWidth + 1)) - 1) : expIn)
            + ((1<<(expWidth - 1)) | (isZeroExpIn ? 2 : 1));
    wire isZero = isZeroExpIn && isZeroFractIn;
    wire isSpecial = (adjustedExp[expWidth:(expWidth - 1)] == 'b11);
    wire [expWidth:0] exp;
    assign exp[expWidth:(expWidth - 2)] =
        isSpecial ? {2'b11, !isZeroFractIn}
            : isZero ? 3'b000 : adjustedExp[expWidth:(expWidth - 2)];
    assign exp[(expWidth - 3):0] = adjustedExp;
    assign out = {sign, exp, isZeroExpIn ? subnormFract : fractIn};
endmodule

module isSigNaNRecFN#(parameter expWidth = 3, parameter sigWidth = 3) (
        input [(expWidth + sigWidth):0] in, output isSigNaN
    );
    wire isNaN =
        (in[(expWidth + sigWidth - 1):(expWidth + sigWidth - 3)] == 'b111);
    assign isSigNaN = isNaN && !in[sigWidth - 2];
endmodule

module compressBy2#(parameter inWidth = 1) (
        input [(inWidth - 1):0] in, output [((inWidth - 1)/2):0] out
    );
    localparam maxBitNumReduced = (inWidth - 1)/2;
    genvar ix;
    generate
        for (ix = 0; ix < maxBitNumReduced; ix = ix + 1) begin :Bit
            assign out[ix] = |in[(ix*2 + 1):ix*2];
        end
    endgenerate
    assign out[maxBitNumReduced] = |in[(inWidth - 1):maxBitNumReduced*2];
endmodule

module compressBy4#(parameter inWidth = 1) (
        input [(inWidth - 1):0] in, output [(inWidth - 1)/4:0] out
    );
    localparam maxBitNumReduced = (inWidth - 1)/4;
    genvar ix;
    generate
        for (ix = 0; ix < maxBitNumReduced; ix = ix + 1) begin :Bit
            assign out[ix] = |in[(ix*4 + 3):ix*4];
        end
    endgenerate
    assign out[maxBitNumReduced] = |in[(inWidth - 1):maxBitNumReduced*4];
endmodule

module lowMaskHiLo#(
        parameter inWidth = 1,
        parameter topBound = 1,
        parameter bottomBound = 0
    ) (
        input [(inWidth - 1):0] in,
        output [(topBound - bottomBound - 1):0] out
    );
    localparam numInVals = 1<<inWidth;
    wire signed [numInVals:0] c;
    assign c[numInVals] = 1;
    assign c[(numInVals - 1):0] = 0;
    wire [(topBound - bottomBound - 1):0] reverseOut =
        (c>>>in)>>(numInVals - topBound);
    reverse#(topBound - bottomBound) reverse(reverseOut, out);
endmodule

module lowMaskLoHi#(
        parameter inWidth = 1,
        parameter topBound = 0,
        parameter bottomBound = 1
    ) (
        input [(inWidth - 1):0] in,
        output [(bottomBound - topBound - 1):0] out
    );
    localparam numInVals = 1<<inWidth;
    wire signed [numInVals:0] c;
    assign c[numInVals] = 1;
    assign c[(numInVals - 1):0] = 0;
    wire [(bottomBound - topBound - 1):0] reverseOut =
        (c>>>~in)>>(topBound + 1);
    reverse#(bottomBound - topBound) reverse(reverseOut, out);
endmodule

module propagateFloatNaN_add#(parameter sigWidth = 3) (
        input [(`floatControlWidth - 1):0] control,
        input subOp,
        input isNaNA,
        input signA,
        input [(sigWidth - 2):0] fractA,
        input isNaNB,
        input signB,
        input [(sigWidth - 2):0] fractB,
        output signNaN,
        output [(sigWidth - 2):0] fractNaN
    );
    assign signNaN = isNaNA ? signA : isNaNB ? signB : 1;
    assign fractNaN =
        {1'b1,
         isNaNA ? fractA[(sigWidth - 3):0] : isNaNB ? fractB[(sigWidth - 3):0]
             : 1'b0};
endmodule

module recFNToRawFN#(parameter expWidth = 3, parameter sigWidth = 3) (
        input [(expWidth + sigWidth):0] in,
        output isNaN,
        output isInf,
        output isZero,
        output sign,
        output signed [(expWidth + 1):0] sExp,
        output [sigWidth:0] sig
    );
    wire [expWidth:0] exp;
    wire [(sigWidth - 2):0] fract;
    assign {sign, exp, fract} = in;
    wire isSpecial = (exp>>(expWidth - 1) == 'b11);
    assign isNaN = isSpecial &&  exp[expWidth - 2];
    assign isInf = isSpecial && !exp[expWidth - 2];
    assign isZero = (exp>>(expWidth - 2) == 'b000);
    assign sExp = exp;
    assign sig = {1'b0, !isZero, fract};
endmodule

module addRecFNToRaw#(parameter expWidth = 3, parameter sigWidth = 3) (
        input [(`floatControlWidth - 1):0] control,
        input subOp,
        input [(expWidth + sigWidth):0] a,
        input [(expWidth + sigWidth):0] b,
        input [2:0] roundingMode,
        output invalidExc,
        output out_isNaN,
        output out_isInf,
        output out_isZero,
        output out_sign,
        output signed [(expWidth + 1):0] out_sExp,
        output [(sigWidth + 2):0] out_sig
    );
    localparam alignDistWidth = clog2(sigWidth);
    wire isNaNA, isInfA, isZeroA, signA;
    wire signed [(expWidth + 1):0] sExpA;
    wire [sigWidth:0] sigA;
    recFNToRawFN#(expWidth, sigWidth)
        recFNToRawFN_a(a, isNaNA, isInfA, isZeroA, signA, sExpA, sigA);
    wire isSigNaNA;
    isSigNaNRecFN#(expWidth, sigWidth) isSigNaN_a(a, isSigNaNA);
    wire isNaNB, isInfB, isZeroB, signB;
    wire signed [(expWidth + 1):0] sExpB;
    wire [sigWidth:0] sigB;
    recFNToRawFN#(expWidth, sigWidth)
        recFNToRawFN_b(b, isNaNB, isInfB, isZeroB, signB, sExpB, sigB);
    wire effSignB = subOp ? !signB : signB;
    wire isSigNaNB;
    isSigNaNRecFN#(expWidth, sigWidth) isSigNaN_b(b, isSigNaNB);
    wire eqSigns = (signA == effSignB);
    wire notEqSigns_signZero = (roundingMode == `round_min) ? 1 : 0;
    wire signed [(expWidth + 1):0] sDiffExps = sExpA - sExpB;
    wire [(alignDistWidth - 1):0] modNatAlignDist =
        (sDiffExps < 0) ? sExpB - sExpA : sDiffExps;
    wire isMaxAlign =
        (sDiffExps>>>alignDistWidth != 0)
            && ((sDiffExps>>>alignDistWidth != -1)
                    || (sDiffExps[(alignDistWidth - 1):0] == 0));
    wire [(alignDistWidth - 1):0] alignDist =
        isMaxAlign ? (1<<alignDistWidth) - 1 : modNatAlignDist;
    wire closeSubMags = !eqSigns && !isMaxAlign && (modNatAlignDist <= 1);
    wire signed [(sigWidth + 2):0] close_alignedSigA =
          ((0 <= sDiffExps) &&  sDiffExps[0] ? sigA<<2 : 0)
        | ((0 <= sDiffExps) && !sDiffExps[0] ? sigA<<1 : 0)
        | ((sDiffExps < 0)                   ? sigA    : 0);
    wire signed [(sigWidth + 2):0] close_sSigSum =
        close_alignedSigA - (sigB<<1);
    wire [(sigWidth + 1):0] close_sigSum =
        (close_sSigSum < 0) ? -close_sSigSum : close_sSigSum;
    wire [(sigWidth + 1 + (sigWidth & 1)):0] close_adjustedSigSum =
        close_sigSum<<(sigWidth & 1);
    wire [(sigWidth + 1)/2:0] close_reduced2SigSum;
    compressBy2#(sigWidth + 2 + (sigWidth & 1))
        compressBy2_close_sigSum(close_adjustedSigSum, close_reduced2SigSum);
    wire [(alignDistWidth - 1):0] close_normDistReduced2;
    countLeadingZeros#((sigWidth + 3)/2, alignDistWidth)
        countLeadingZeros_close(close_reduced2SigSum, close_normDistReduced2);
    wire [(alignDistWidth - 1):0] close_nearNormDist =
        close_normDistReduced2<<1;
    wire [(sigWidth + 2):0] close_sigOut =
        (close_sigSum<<close_nearNormDist)<<1;
    wire close_totalCancellation =
        !(|close_sigOut[(sigWidth + 2):(sigWidth + 1)]);
    wire close_notTotalCancellation_signOut = signA ^ (close_sSigSum < 0);
    wire far_signOut = (sDiffExps < 0) ? effSignB : signA;
    wire [(sigWidth - 1):0] far_sigLarger  = (sDiffExps < 0) ? sigB : sigA;
    wire [(sigWidth - 1):0] far_sigSmaller = (sDiffExps < 0) ? sigA : sigB;
    wire [(sigWidth + 4):0] far_mainAlignedSigSmaller =
        {far_sigSmaller, 5'b0}>>alignDist;
    wire [(sigWidth + 1)/4:0] far_reduced4SigSmaller;
    compressBy4#(sigWidth + 2)
        compressBy4_far_sigSmaller(
            {far_sigSmaller, 2'b00}, far_reduced4SigSmaller);
    wire [(sigWidth + 1)/4:0] far_roundExtraMask;
    lowMaskHiLo#(alignDistWidth - 2, (sigWidth + 5)/4, 0)
        lowMask_far_roundExtraMask(
            alignDist[(alignDistWidth - 1):2], far_roundExtraMask);
    wire [(sigWidth + 2):0] far_alignedSigSmaller =
        {far_mainAlignedSigSmaller>>3,
         (|far_mainAlignedSigSmaller[2:0])
             || (|(far_reduced4SigSmaller & far_roundExtraMask))};
    wire far_subMags = !eqSigns;
    wire [(sigWidth + 3):0] far_negAlignedSigSmaller =
        far_subMags ? {1'b1, ~far_alignedSigSmaller}
            : {1'b0, far_alignedSigSmaller};
    wire [(sigWidth + 3):0] far_sigSum =
        (far_sigLarger<<3) + far_negAlignedSigSmaller + far_subMags;
    wire [(sigWidth + 2):0] far_sigOut =
        far_subMags ? far_sigSum : far_sigSum>>1 | far_sigSum[0];
    wire notSigNaN_invalidExc = isInfA && isInfB && !eqSigns;
    wire notNaN_isInfOut = isInfA || isInfB;
    wire addZeros = isZeroA && isZeroB;
    wire notNaN_specialCase = notNaN_isInfOut || addZeros;
    wire notNaN_isZeroOut =
        addZeros
            || (!notNaN_isInfOut && closeSubMags && close_totalCancellation);
    wire notNaN_signOut =
           (eqSigns                      && signA              )
        || (isInfA                       && signA              )
        || (isInfB                       && effSignB           )
        || (notNaN_isZeroOut && !eqSigns && notEqSigns_signZero)
        || (!notNaN_specialCase && closeSubMags && !close_totalCancellation
                                        && close_notTotalCancellation_signOut)
        || (!notNaN_specialCase && !closeSubMags && far_signOut);
    wire signed [(expWidth + 1):0] common_sExpOut =
        (closeSubMags || (sDiffExps < 0) ? sExpB : sExpA)
            - (closeSubMags ? close_nearNormDist : far_subMags);
    wire [(sigWidth + 2):0] common_sigOut =
        closeSubMags ? close_sigOut : far_sigOut;
    assign invalidExc = isSigNaNA || isSigNaNB || notSigNaN_invalidExc;
    assign out_isInf = notNaN_isInfOut;
    assign out_isZero = notNaN_isZeroOut;
    assign out_sExp = common_sExpOut;
`ifdef HardFloat_propagateNaNPayloads
    assign out_isNaN = isNaNA || isNaNB || notSigNaN_invalidExc;
    wire signNaN;
    wire [(sigWidth - 2):0] fractNaN;
    propagateFloatNaN_add#(sigWidth)
        propagateNaN(
            control,
            subOp,
            isNaNA,
            signA,
            sigA[(sigWidth - 2):0],
            isNaNB,
            signB,
            sigB[(sigWidth - 2):0],
            signNaN,
            fractNaN
        );
    assign out_sign = out_isNaN ? signNaN : notNaN_signOut;
    assign out_sig = out_isNaN ? {1'b1, fractNaN, 2'b00} : common_sigOut;
`else
    assign out_isNaN = isNaNA || isNaNB;
    assign out_sign = notNaN_signOut;
    assign out_sig = common_sigOut;
`endif
endmodule

module roundAnyRawFNToRecFN#(
        parameter inExpWidth = 3,
        parameter inSigWidth = 3,
        parameter outExpWidth = 3,
        parameter outSigWidth = 3,
        parameter options = 0
    ) (
        input [(`floatControlWidth - 1):0] control,
        input invalidExc,     // overrides 'infiniteExc' and 'in_*' inputs
        input infiniteExc,    // overrides 'in_*' inputs except 'in_sign'
        input in_isNaN,
        input in_isInf,
        input in_isZero,
        input in_sign,
        input signed [(inExpWidth + 1):0] in_sExp,   // limited range allowed
        input [inSigWidth:0] in_sig,
        input [2:0] roundingMode,
        output [(outExpWidth + outSigWidth):0] out,
        output [4:0] exceptionFlags
    );
    localparam sigMSBitAlwaysZero =
        ((options & `flRoundOpt_sigMSBitAlwaysZero) != 0);
    localparam effectiveInSigWidth =
        sigMSBitAlwaysZero ? inSigWidth : inSigWidth + 1;
    localparam neverUnderflows =
        ((options
              & (`flRoundOpt_neverUnderflows
                     | `flRoundOpt_subnormsAlwaysExact))
             != 0)
            || (inExpWidth < outExpWidth);
    localparam neverOverflows =
        ((options & `flRoundOpt_neverOverflows) != 0)
            || (inExpWidth < outExpWidth);
    localparam adjustedExpWidth =
          (inExpWidth < outExpWidth) ? outExpWidth + 1
        : (inExpWidth == outExpWidth) ? inExpWidth + 2
        : inExpWidth + 3;
    localparam outNaNExp = 7<<(outExpWidth - 2);
    localparam outInfExp = 6<<(outExpWidth - 2);
    localparam outMaxFiniteExp = outInfExp - 1;
    localparam outMinNormExp = (1<<(outExpWidth - 1)) + 2;
    localparam outMinNonzeroExp = outMinNormExp - outSigWidth + 1;
    wire roundingMode_near_even   = (roundingMode == `round_near_even);
    wire roundingMode_minMag      = (roundingMode == `round_minMag);
    wire roundingMode_min         = (roundingMode == `round_min);
    wire roundingMode_max         = (roundingMode == `round_max);
    wire roundingMode_near_maxMag = (roundingMode == `round_near_maxMag);
    wire roundingMode_odd         = (roundingMode == `round_odd);
    wire roundMagUp =
        (roundingMode_min && in_sign) || (roundingMode_max && !in_sign);
    wire isNaNOut = invalidExc || (!infiniteExc && in_isNaN);
`ifdef HardFloat_propagateNaNPayloads
    wire propagateNaNPayload = isNaNOut;
`else
    wire propagateNaNPayload = 0;
`endif
    wire signed [(adjustedExpWidth - 1):0] sAdjustedExp =
        in_sExp + ((1<<outExpWidth) - (1<<inExpWidth));
    wire [(outSigWidth + 2):0] adjustedSig;
    generate
        if (inSigWidth <= outSigWidth + 2) begin
            assign adjustedSig = in_sig<<(outSigWidth - inSigWidth + 2);
        end else begin
            assign adjustedSig =
                {in_sig[inSigWidth:(inSigWidth - outSigWidth - 1)],
                 |in_sig[(inSigWidth - outSigWidth - 2):0]};
        end
    endgenerate
    wire doShiftSigDown1 =
        sigMSBitAlwaysZero ? 0 : adjustedSig[outSigWidth + 2];
    wire [outExpWidth:0] common_expOut;
    wire [(outSigWidth - 2):0] common_fractOut;
    wire common_overflow, common_totalUnderflow, common_underflow;
    wire common_inexact;
    generate
        if (
            neverOverflows && neverUnderflows
                && (effectiveInSigWidth <= outSigWidth)
        ) begin
            assign common_expOut = sAdjustedExp + doShiftSigDown1;
            assign common_fractOut =
                doShiftSigDown1 ? adjustedSig>>3 : adjustedSig>>2;
            assign common_overflow       = 0;
            assign common_totalUnderflow = 0;
            assign common_underflow      = 0;
            assign common_inexact        = 0;
        end else begin
            wire [(outSigWidth + 2):0] roundMask;
            if (neverUnderflows) begin
                assign roundMask = {doShiftSigDown1, 2'b11};
            end else begin
                wire [outSigWidth:0] roundMask_main;
                lowMaskLoHi#(
                    outExpWidth + 1,
                    outMinNormExp - outSigWidth - 1,
                    outMinNormExp
                ) lowMask_roundMask(
                        sAdjustedExp[outExpWidth:0]
                            | (propagateNaNPayload ? 1'b1<<outExpWidth : 1'b0),
                        roundMask_main
                    );
                assign roundMask = {roundMask_main | doShiftSigDown1, 2'b11};
            end
            wire [(outSigWidth + 2):0] shiftedRoundMask = roundMask>>1;
            wire [(outSigWidth + 2):0] roundPosMask =
                ~shiftedRoundMask & roundMask;
            wire roundPosBit =
                (|(adjustedSig[(outSigWidth + 2):3]
                       & roundPosMask[(outSigWidth + 2):3]))
                    || ((|(adjustedSig[2:0] & roundPosMask[2:0]))
                            && !propagateNaNPayload);
            wire anyRoundExtra =
                (|(adjustedSig[(outSigWidth + 2):3]
                       & shiftedRoundMask[(outSigWidth + 2):3]))
                    || ((|(adjustedSig[2:0] & shiftedRoundMask[2:0]))
                            && !propagateNaNPayload);
            wire anyRound = roundPosBit || anyRoundExtra;
            wire roundIncr =
                ((roundingMode_near_even || roundingMode_near_maxMag)
                     && roundPosBit)
                    || (roundMagUp && anyRound);
            wire [(outSigWidth + 1):0] roundedSig =
                roundIncr
                    ? (((adjustedSig | roundMask)>>2) + 1)
                          & ~(roundingMode_near_even && roundPosBit
                                  && !anyRoundExtra
                                  ? roundMask>>1 : 0)
                    : (adjustedSig & ~roundMask)>>2
                          | (roundingMode_odd && anyRound
                                 ? roundPosMask>>1 : 0);
            wire signed [adjustedExpWidth:0] sExtAdjustedExp = sAdjustedExp;
            wire signed [adjustedExpWidth:0] sRoundedExp =
                sExtAdjustedExp + (roundedSig>>outSigWidth);
            assign common_expOut = sRoundedExp;
            assign common_fractOut =
                doShiftSigDown1 ? roundedSig>>1 : roundedSig;
            assign common_overflow =
                neverOverflows ? 0 : (sRoundedExp>>>(outExpWidth - 1) >= 3);
            assign common_totalUnderflow =
                neverUnderflows ? 0 : (sRoundedExp < outMinNonzeroExp);
            wire unboundedRange_roundPosBit =
                doShiftSigDown1 ? adjustedSig[2] : adjustedSig[1];
            wire unboundedRange_anyRound =
                (doShiftSigDown1 && adjustedSig[2]) || (|adjustedSig[1:0]);
            wire unboundedRange_roundIncr =
                ((roundingMode_near_even || roundingMode_near_maxMag)
                     && unboundedRange_roundPosBit)
                    || (roundMagUp && unboundedRange_anyRound);
            wire roundCarry =
                doShiftSigDown1
                    ? roundedSig[outSigWidth + 1] : roundedSig[outSigWidth];
            assign common_underflow =
                neverUnderflows ? 0
                    : common_totalUnderflow
                          || (anyRound && (sAdjustedExp>>>outExpWidth <= 0)
                                  && (doShiftSigDown1
                                          ? roundMask[3] : roundMask[2])
                                  && !(((control
                                           & `flControl_tininessAfterRounding)
                                            != 0)
                                           && !(doShiftSigDown1 ? roundMask[4]
                                                    : roundMask[3])
                                           && roundCarry && roundPosBit
                                           && unboundedRange_roundIncr));
            assign common_inexact = common_totalUnderflow || anyRound;
        end
    endgenerate
    wire notNaN_isSpecialInfOut = infiniteExc || in_isInf;
    wire commonCase = !isNaNOut && !notNaN_isSpecialInfOut && !in_isZero;
    wire overflow  = commonCase && common_overflow;
    wire underflow = commonCase && common_underflow;
    wire inexact = overflow || (commonCase && common_inexact);
    wire overflow_roundMagUp =
        roundingMode_near_even || roundingMode_near_maxMag || roundMagUp;
    wire pegMinNonzeroMagOut =
        commonCase && common_totalUnderflow
            && (roundMagUp || roundingMode_odd);
    wire pegMaxFiniteMagOut = overflow && !overflow_roundMagUp;
    wire notNaN_isInfOut =
        notNaN_isSpecialInfOut || (overflow && overflow_roundMagUp);
`ifdef HardFloat_propagateNaNPayloads
    wire signOut = in_sign;
`else
    wire signOut = isNaNOut ? `HardFloat_signDefaultNaN : in_sign;
`endif
    wire [outExpWidth:0] expOut =
        (common_expOut
             & ~(in_isZero || common_totalUnderflow ? 7<<(outExpWidth - 2) : 0)
             & ~(pegMinNonzeroMagOut               ? ~outMinNonzeroExp    : 0)
             & ~(pegMaxFiniteMagOut                ? 1<<(outExpWidth - 1) : 0)
             & ~(notNaN_isInfOut                   ? 1<<(outExpWidth - 2) : 0))
            | (pegMinNonzeroMagOut ? outMinNonzeroExp : 0)
            | (pegMaxFiniteMagOut  ? outMaxFiniteExp  : 0)
            | (notNaN_isInfOut     ? outInfExp        : 0)
            | (isNaNOut            ? outNaNExp        : 0);
`ifdef HardFloat_propagateNaNPayloads
    wire [(outSigWidth - 2):0] fractOut =
        {isNaNOut
             || (!in_isZero && !common_totalUnderflow
                     && common_fractOut[outSigWidth - 2]),
         isNaNOut || (!in_isZero && !common_totalUnderflow)
             ? common_fractOut[(outSigWidth - 3):0] : 1'b0}
            | {(outSigWidth - 1){pegMaxFiniteMagOut}};
`else
    wire [(outSigWidth - 2):0] fractOut =
          (isNaNOut ? `HardFloat_fractDefaultNaN(outSigWidth) : 0)
        | (!in_isZero && !common_totalUnderflow
               ? common_fractOut & `HardFloat_fractDefaultNaN(outSigWidth) : 0)
        | (!isNaNOut && !in_isZero && !common_totalUnderflow
               ? common_fractOut & ~`HardFloat_fractDefaultNaN(outSigWidth)
               : 0)
        | {(outSigWidth - 1){pegMaxFiniteMagOut}};
`endif
    assign out = {signOut, expOut, fractOut};
    assign exceptionFlags =
        {invalidExc, infiniteExc, overflow, underflow, inexact};
endmodule

module roundRawFNToRecFN#(
        parameter expWidth = 3,
        parameter sigWidth = 3,
        parameter options = 0
    ) (
        input [(`floatControlWidth - 1):0] control,
        input invalidExc,     // overrides 'infiniteExc' and 'in_*' inputs
        input infiniteExc,    // overrides 'in_*' inputs except 'in_sign'
        input in_isNaN,
        input in_isInf,
        input in_isZero,
        input in_sign,
        input signed [(expWidth + 1):0] in_sExp,   // limited range allowed
        input [(sigWidth + 2):0] in_sig,
        input [2:0] roundingMode,
        output [(expWidth + sigWidth):0] out,
        output [4:0] exceptionFlags
    );
    roundAnyRawFNToRecFN#(expWidth, sigWidth + 2, expWidth, sigWidth, options)
        roundAnyRawFNToRecFN(
            control,
            invalidExc,
            infiniteExc,
            in_isNaN,
            in_isInf,
            in_isZero,
            in_sign,
            in_sExp,
            in_sig,
            roundingMode,
            out,
            exceptionFlags
        );
endmodule

module addRecFN#(parameter expWidth = 3, parameter sigWidth = 3) (
        input [(`floatControlWidth - 1):0] control,
        input subOp,
        input [(expWidth + sigWidth):0] a,
        input [(expWidth + sigWidth):0] b,
        input [2:0] roundingMode,
        output [(expWidth + sigWidth):0] out,
        output [4:0] exceptionFlags
    );
    wire invalidExc, out_isNaN, out_isInf, out_isZero, out_sign;
    wire signed [(expWidth + 1):0] out_sExp;
    wire [(sigWidth + 2):0] out_sig;
    addRecFNToRaw#(expWidth, sigWidth)
        addRecFNToRaw(
            control,
            subOp,
            a,
            b,
            roundingMode,
            invalidExc,
            out_isNaN,
            out_isInf,
            out_isZero,
            out_sign,
            out_sExp,
            out_sig
        );
    // Defined previously in this file
    roundRawFNToRecFN#(expWidth, sigWidth, `flRoundOpt_subnormsAlwaysExact)
        roundRawOut(
            control,
            invalidExc,
            1'b0,
            out_isNaN,
            out_isInf,
            out_isZero,
            out_sign,
            out_sExp,
            out_sig,
            roundingMode,
            out,
            exceptionFlags
        );
endmodule

module recFNToFN#(parameter expWidth = 3, parameter sigWidth = 3) (
        input [(expWidth + sigWidth):0] in,
        output [(expWidth + sigWidth - 1):0] out
    );
    localparam [expWidth:0] minNormExp = (1<<(expWidth - 1)) + 2;
    localparam normDistWidth = clog2(sigWidth);
    wire isNaN, isInf, isZero, sign;
    wire signed [(expWidth + 1):0] sExp;
    wire [sigWidth:0] sig;
    recFNToRawFN#(expWidth, sigWidth)
        recFNToRawFN(in, isNaN, isInf, isZero, sign, sExp, sig);
    wire isSubnormal = (sExp < minNormExp);
    wire [(normDistWidth - 1):0] denormShiftDist = minNormExp - 1 - sExp;
    wire [(expWidth - 1):0] expOut =
        (isSubnormal ? 0 : sExp - minNormExp + 1)
            | (isNaN || isInf ? {expWidth{1'b1}} : 0);
    wire [(sigWidth - 2):0] fractOut =
        isSubnormal ? (sig>>1)>>denormShiftDist : isInf ? 0 : sig;
    assign out = {sign, expOut, fractOut};
endmodule

// ============================================================================
// TOP LEVEL WRAPPER
// ============================================================================

module fp_addsub #(
  parameter int EXP = 8,
  parameter int SIG = 24
)(
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 sub,
  input  logic [EXP+SIG-1:0]   a_ieee,
  input  logic [EXP+SIG-1:0]   b_ieee,
  input  logic [2:0]           roundingMode,
  input  logic                 detectTininess,
  output logic [EXP+SIG-1:0]   z_ieee,
  output logic [4:0]           exceptionFlags
);
  localparam int E = EXP;
  localparam int S = SIG;

  logic [E+S:0] a_rec, b_rec, z_rec;

  fNToRecFN #(.expWidth(E), .sigWidth(S)) i_f2rec_a (.in(a_ieee), .out(a_rec));
  fNToRecFN #(.expWidth(E), .sigWidth(S)) i_f2rec_b (.in(b_ieee), .out(b_rec));

  addRecFN #(.expWidth(E), .sigWidth(S)) i_addsub (
    .control        (detectTininess),
    .subOp          (sub),
    .a              (a_rec),
    .b              (b_rec),
    .roundingMode   (roundingMode),
    .out            (z_rec),
    .exceptionFlags (exceptionFlags)
  );

  recFNToFN #(.expWidth(E), .sigWidth(S)) i_rec2f (.in(z_rec), .out(z_ieee));
endmodule