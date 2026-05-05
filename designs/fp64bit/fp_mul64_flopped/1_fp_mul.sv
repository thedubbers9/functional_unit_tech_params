// FP multiplier code from: 
// https://github.com/andmiele/SystemVerilogALUandFPUmodules, with some modifications


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


// 64 bit floating point

// fpMultiplier.sv
// IEEE Floating Point multiplier

//helper modules


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

module halfAdder
(
    input logic x,
    input logic y,
    output logic sum,
    output logic cout
);

assign sum = x ^ y;
assign cout = (x & y);
endmodule

module fullAdder
(
    input logic x,
    input logic y,
    input logic cin,
    output logic sum,
    output logic cout
);

assign sum = x ^ y ^ cin;
assign cout = (x & y) | (x & cin) | (y & cin);

endmodule

// 4-to-2 bits compressor for Wallace tree multiplier
// x1 + x2 + x3 + x4 + cin = sum + 2(carry + cout)
module compressor_42
(
    input logic x1,
    input logic x2,
    input logic x3,
    input logic x4,
    input logic cin,
    output logic sum, // sum
    output logic carry, // vertical carry
    output logic cout // lateral carry
);

logic xor12;
logic xor34;
logic xor1234;

assign xor12 = x1 ^ x2;
assign xor34 = x3 ^ x4;
assign xor1234 = xor12 ^ xor34;

//cout: high if x1 + x2 + x3 generates carry
// cout MUX
assign cout = (xor12) ? x3 : x1;    

// carry: high if sum(x1, x2, x3) + x4 + cin generates carry
// carry MUX
assign carry = (xor1234) ? cin : x4;

//sum
assign sum = xor1234 ^ cin;

endmodule

// 3-bits Booth recoder (radix-4)
// 0,0,0 -> multiplicand * 0
// 0,0,1 -> multiplicand * 1
// 0,1,0 -> multiplicand * 1
// 0,1,1 -> multiplicand * 2
// 1,0,0 -> multiplicand * -2
// 1,0,1 -> multiplicand * -1
// 1,1,0 -> multiplicand * -1
// 1,1,1 -> multipilcand * 0
module boothRecoder3 
(
    input logic [2:0] in,
    output logic zero,
    output logic neg,
    output logic two
);

always_comb
begin
    case (in)
        3'b000 : begin  zero = 1;  neg = 0;  two = 0; end
        3'b001 : begin  zero = 0;  neg = 0;  two = 0; end
        3'b010 : begin  zero = 0;  neg = 0;  two = 0; end
        3'b011 : begin  zero = 0;  neg = 0;  two = 1; end
        3'b100 : begin  zero = 0;  neg = 1;  two = 1; end
        3'b101 : begin  zero = 0;  neg = 1;  two = 0; end
        3'b110 : begin  zero = 0;  neg = 1;  two = 0; end
        3'b111 : begin  zero = 1;  neg = 1;  two = 0; end
    endcase
end
endmodule

// Single partial product generation for radix-4 Booth multiplier
// Generate input, -input, 0, 2 * input or - 2 * input based on input flags
// negative values are just 1's complement, remember to add 1 in addition tree
module pProd
#(parameter INPUT_SIZE = 16, parameter OUTPUT_SIZE = INPUT_SIZE + 2)
(
	input logic signedFlag,
	input logic [INPUT_SIZE - 1 : 0] in,
	output logic [OUTPUT_SIZE - 1 : 0] out,
	output logic signLow,
	input logic zero,
	input logic neg,
	input logic two
);

logic [OUTPUT_SIZE - 1 : 0] res;
always_comb
begin
	if (zero == 1)
	begin
		out = {OUTPUT_SIZE {1'b0}};
		res = {OUTPUT_SIZE {1'b0}};		
		signLow = 1'b0;
	end

	else
	begin
		if (two == 1)
			res = {{OUTPUT_SIZE - INPUT_SIZE - 1 {signedFlag & in[INPUT_SIZE - 1]}}, in[INPUT_SIZE - 1 : 0], 1'b0};
		else
			res = {{OUTPUT_SIZE - INPUT_SIZE {signedFlag & in[INPUT_SIZE - 1]}}, in}; 
		if (neg == 1)
			res[OUTPUT_SIZE - 1 : 0] = ~res[OUTPUT_SIZE - 1 : 0];
		else
			res[OUTPUT_SIZE - 1 : 0] = res[OUTPUT_SIZE - 1 : 0];
		out[OUTPUT_SIZE - 2 : 0] = res[OUTPUT_SIZE - 2 : 0];
		if (signedFlag == 1)
			out[OUTPUT_SIZE - 1] = neg != in[INPUT_SIZE - 1];
		else
			out[OUTPUT_SIZE - 1] = res[OUTPUT_SIZE - 1];
		signLow = neg;
	end

end
endmodule

// Partial product generation for radix-4 Booth multiplier
// Generate all partial products 
module pProdsGen
#(parameter M = 16, parameter N = 16, parameter NPP = N / 2 + 1)
(
	input logic signedFlag,
	input logic [M - 1 : 0] multiplicand,
	input logic [N - 1 : 0] multiplier,
	output logic [M + 2 - 1 : 0] pprods [0 : NPP - 1],
	output logic [0 : NPP - 1] signsLow
);

// Pad msb with 2 zeros if N is even and 1 zero if N is odd
	// add 1 0 lsb
	localparam msbZeroPadding = 2 - (N % 2);
	logic [N + msbZeroPadding : 0] paddedMultiplier;
	// sign extend for signed mul with odd N
	assign paddedMultiplier = {{msbZeroPadding{multiplier[N - 1] && (N % 2 == 1)}}, multiplier, 1'b0};

	genvar i;
	generate
	for (i = 0; i < NPP; i = i + 1)
	begin: pps
		logic zero, neg, two;
		boothRecoder3 br(paddedMultiplier[2 * (i + 1) : 2 * i], zero, neg, two);
		pProd #(.INPUT_SIZE(M), .OUTPUT_SIZE(M + 2)) pp_i (.signedFlag(signedFlag),.in(multiplicand), 
			.out(pprods[i]), .signLow(signsLow[i]), .zero(zero | ((i == (NPP - 1)) & signedFlag & (N % 2 == 0))), .neg(neg), .two(two));
	end
	endgenerate
endmodule

// 2-bit Carry Look-Ahead logic
// r-bit CLA Logic: r(r + 1) / 2 + r = (r^2 + r + 2r) / 2 = r(r + 3)/ 2 (+ 2 gates if cout is needed)

module claLogic2
(
    input logic cin,
    input logic [1 : 0] gi,
    input logic [1 : 0] pi,
    output logic c1,
    output logic g,
    output logic p,
    output logic cout
);

assign c1 = (cin & pi[0]) | gi[0]; // 2 gates

assign p = pi[0] & pi[1]; // 1 gate
assign g = (gi[0] & pi[1]) | // 2 gates
gi[1];
assign cout = (cin & p) | g; // 2 gates
endmodule

module claLogic4
(
    input logic cin,
    input logic [3 : 0] gi,
    input logic [3 : 0] pi,
    output logic [3 : 1] ci,
    output logic g,
    output logic p,
    output logic cout
);

assign ci[1] = (cin & pi[0]) | gi[0]; // 2 gates
assign ci[2] = (cin & pi[0] & pi[1]) |  // 3 gates
(gi[0] & pi[1]) | gi[1];
assign ci[3] = (cin & pi[0] & pi[1] & pi[2]) | // 4 gates
(gi[0] & pi[1] & pi[2]) |
(gi[1] & pi[2]) | gi[2];

assign p = pi[0] & pi[1] & pi[2] & pi[3]; // 1 gate
assign g = (gi[0] & pi[1] & pi[2] & pi[3]) | // 4 gates
(gi[1] & pi[2] & pi[3]) |
(gi[2] & pi[3]) | 
gi[3];
assign cout = (cin & p) | g; // 2 gates
endmodule



module fullAdderPG
(
    input logic cin,
    input logic x,
    input logic y,
    output logic sum,
    output logic g,
    output logic p
);
assign p = x ^ y;
assign g = x & y;
assign sum = p ^ cin;
endmodule

module claAddSub4
(
    input logic sub,
    input logic cin, // arithmetic carry ignored if sub is 1
    input logic [3 : 0] x,
    input logic [3 : 0] y,
    output logic [3 : 0] out,
    output logic cout,
    output logic g,
    output logic p,
    output logic v
);

logic [3 : 0] gi;
logic [3 : 0] pi;
logic [3 : 0] ci;
logic [3 : 0] yn;

assign ci[0] = sub | cin;
assign yn = y ^ {4{sub}};

genvar i;
generate
for(i = 0; i <= 3; i++)
begin: fullAdderGen
    fullAdderPG fa_i(
        .x(x[i]), .y(yn[i]),
        .cin(ci[i]), .sum(out[i]),
        .g(gi[i]), .p(pi[i])
    );
end
endgenerate
// CLA logic
claLogic4 cla4(.cin(ci[0]), .pi(pi), .gi(gi), 
    .ci(ci[3 : 1]), .g(g), .p(p), 
.cout(cout));
assign v = cout ^ ci[3];

endmodule

module claAddSub8
(
    input logic sub,
    input logic cin, // arithmetic carry ignored if sub is 1
    input logic [7 : 0] x,
    input logic [7 : 0] y,
    output logic [7 : 0] out,
    output logic cout,
    output logic g,
    output logic p,
    output logic v
);

logic [1 : 0] gi;
logic [1 : 0] pi;
logic [1 : 0] ci;
logic [7 : 0] yn;

assign ci[0] = sub | cin;
assign yn = y ^ {8{sub}};

claAddSub4 cla0(.sub(1'b0), .cin(ci[0]), .x(x[3 : 0]), .y(yn[3 : 0]), .out(out[3 : 0]), .cout(), .g(gi[0]), .p(pi[0]), .v());
claAddSub4 cla1(.sub(1'b0), .cin(ci[1]), .x(x[7 : 4]), .y(yn[7 : 4]), .out(out[7 : 4]), .cout(), .g(gi[1]), .p(pi[1]), .v(v));

// CLA logic
claLogic2 cla2(.cin(ci[0]), .pi(pi), .gi(gi), 
.c1(ci[1 : 1]), .g(g), .p(p), .cout(cout));

endmodule

module claAddSub16
#(parameter M = 16) 
(
 input logic sub,
 input logic cin, // arithmetic carry ignored if sub is 1
 input logic [M -1 : 0] x,
 input logic [M - 1 : 0] y,
 output logic [M - 1 : 0] out,
 output logic cout,
 output logic v,
 output logic g,
 output logic p
 );

logic [4 : 0] ci;
logic [4 : 0] gi;
logic [4 : 0] pi;
logic [4 : 0] vi;

logic [M - 1 : 0] yn;

assign ci[0] = sub | cin;
assign yn = y ^ {M{sub}};

localparam M4 = M / 4;
genvar i;
generate
for(i = 0; i < 4; i = i + 1)
begin: claFor
    if(M == 16)
    begin: M_eq_16
        claAddSub4 a4(
                        .sub(1'b0), .cin(ci[i]),
                        .x(x[M4 * i + M4 - 1 : M4 * i]),
                        .y(yn[M4 * i + M4 - 1 : M4 * i]), 
                        .out(out[M4 * i + M4 - 1 : M4 * i]),
                        .cout(),
                        .v(vi[i]),
                        .g(gi[i]),
                        .p(pi[i])
                     );
    end
    else
    begin: claAdders
        claAddSub4 aM(
                        .sub(1'b0), .cin(ci[i]),
                        .x(x[M4 * i + M4 - 1 : M4 * i]),
                        .y(yn[M4 * i + M4 - 1 : M4 * i]), 
                        .out(out[M4 * i + M4 - 1 : M4 * i]),
                        .cout(),
                        .v(vi[i]),
                        .g(gi[i]),
                        .p(pi[i])
                        );  
    end
end
endgenerate

    claLogic4 cla(.cin(ci[0]), .gi(gi), 
    .pi(pi), .ci(ci[3:1]), .g(g),
    .p(p), .cout(cout));

assign v = vi[3];

endmodule


module claAddSub53
#(parameter M = 53)
(
    input logic sub,
    input logic cin, // arithmetic carry ignored if sub is 1
    input logic [M -1 : 0] x,
    input logic [M - 1 : 0] y,
    output logic [M - 1 : 0] out,
    output logic cout,
    output logic v,
    output logic g,
    output logic p
);

logic [4 : 0] ci;
logic [3 : 0] gi;
logic [3 : 0] pi;
logic gl;
logic pl;
logic gfa;
logic pfa;

logic [M - 1 : 0] yn;

logic icout;

assign ci[0] = sub | cin;
assign yn = y ^ {M{sub}};

localparam M1 = 16;
genvar i;
generate
for(i = 0; i <= 2; i = i + 1)
begin: claGen
    claAddSub16 aM1(
        .sub(1'b0), .cin(ci[i]),
        .x(x[M1 * i + M1 - 1 : M1 * i]),
        .y(yn[M1 * i + M1 - 1 : M1 * i]), 
        .out(out[M1 * i + M1 - 1 : M1 * i]),
        .cout(),
        .v(),
        .g(gi[i]),
        .p(pi[i])
    );  
end
endgenerate
claAddSub4 a4(
    .sub(1'b0), .cin(ci[3]),
    .x(x[M1 * 3 + 4 - 1 : M1 * 3]),
    .y(yn[M1 * 3 + 4 - 1 : M1 * 3]), 
    .out(out[M1 * 3 + 4 - 1 : M1 * 3]),
    .cout(),
    .v(),
    .g(gi[3]),
    .p(pi[3])
); 

claLogic4 cla(.cin(ci[0]), .gi(gi), 
    .pi(pi), .ci(ci[3 : 1]), .g(gl),
.p(pl), .cout(ci[4]));

fullAdderPG final_fa(.x(x[52]), .y(yn[52]), .cin(ci[4]), 
.sum(out[52]), .g(gfa), .p(pfa));

assign g = (gl & pfa) | gfa;
assign p = pl * pfa;

assign cout = icout ^ sub;
assign v = ci[4] ^ icout;

endmodule

// 106-bit Adder-Subtractor based on 4-bit Carry Look-Ahead Adder-Subtractor

module claAddSub106
#(parameter M = 106)
(
    input logic sub,
    input logic cin, // arithmetic carry ignored if sub is 1
    input logic [M -1 : 0] x,
    input logic [M - 1 : 0] y,
    output logic [M - 1 : 0] out,
    output logic cout,
    output logic v,
    output logic g,
    output logic p
);

logic [1 : 0] ci;
logic [1 : 0] gi;
logic [1 : 0] pi;
logic [1 : 0] vi;

logic [M - 1 : 0] yn;

logic icout;

assign ci[0] = sub | cin;
assign yn = y ^ {M{sub}};

localparam M2 = M / 2;
genvar i;
generate
for(i = 0; i <= 1; i = i + 1)
begin: cla53Adders
    claAddSub53 a53(
        .sub(1'b0), .cin(ci[i]),
        .x(x[M2 * i + M2 - 1 : M2 * i]),
        .y(yn[M2 * i + M2 - 1 : M2 * i]), 
        .out(out[M2 * i + M2 - 1 : M2 * i]),
        .cout(),
        .v(vi[i]),
        .g(gi[i]),
        .p(pi[i])
    );  
end
endgenerate
claLogic2 cla(.cin(ci[0]), .gi(gi), 
    .pi(pi), .c1(ci[1]), .g(g),
.p(p), .cout(icout));

assign cout = icout ^ sub;
assign v = vi[1];

endmodule


// 53-bit unsigned/signed Radix-4 Booth Wallace tree multiplier top level

module Radix4BoothWallace53
(
    input logic signedFlag, // 1 signed, 0 unsigned 
    input logic [52 : 0] multiplicand,
    input logic [52 : 0] multiplier,
    output logic [105 : 0] out
);

localparam M = 53;
localparam NPP = M / 2 + 1;
logic [M + 2 - 1 : 0] pprods [0 : NPP - 1]; //    - 2m <= pp <= 2m
logic [M + 4 - 1 : 0] pprodsExt [0 : NPP - 1];
logic [0 : NPP - 1] signsLow;
logic [2 * M - 1 : 0] sum_0 [0 : NPP / 4 + 1]; // + 1 for signed mul as M is odd (last pprod low sign)
logic [2 * M - 1  : 0] carry_0 [0 : NPP / 4];
logic [2 * M - 1 : 0] hor_cout_0 [0 : NPP / 4];
logic [2 * M - 1 : 0] sum_1 [0 : NPP / 8];
logic [2 * M - 1  : 0] carry_1 [0 : NPP / 8];
logic [2 * M - 1 : 0] hor_cout_1 [0 : NPP / 8];
logic [2 * M - 1 : 0] sum_2 [0 : NPP / 16];
logic [2 * M - 1  : 0] carry_2 [0 : NPP / 16];
logic [2 * M - 1 : 0] hor_cout_2 [0 : NPP / 16];
logic [2 * M - 1 : 0] sum_3 [0 : NPP / 32];
logic [2 * M - 1 : 0] carry_3 [0 : NPP / 32];
logic [2 * M - 1 : 0] hor_cout_3 [0 : NPP / 32];

pProdsGen #(.M(M), .N(M), .NPP(NPP)) pProdsGen(.signedFlag(signedFlag), .multiplicand(multiplicand), 
.multiplier(multiplier), .pprods(pprods), .signsLow(signsLow));

assign pprodsExt[0] = {~pprods[0][M + 1], pprods[0][M + 1], pprods[0][M + 1 : 0]};

// generate partial products and extend with sign compression values
genvar i;
generate
for(i = 1; i < NPP; i = i + 1)
begin: pprodsGenLoop
    assign pprodsExt[i] = {1'b1, ~pprods[i][M + 1], pprods[i][M : 0]}; 
end

////// tree


///**** level 0, rows 0 - NPP / 4 - 1****///

///PREAMBLE///

genvar row_0;

for (row_0 = 0; row_0 < NPP / 4; row_0 = row_0 + 1)
begin: row_0_for
    // y is low sign of pprod
    halfAdder ha_row0_0(.x(pprodsExt[row_0 * 4][0]), .y(signsLow[row_0 * 4]), 
        .sum(sum_0[row_0][row_0 * 8]), 
    .cout(carry_0[row_0][row_0 * 8]));

    assign sum_0[row_0][row_0 * 8 + 1] = pprodsExt[row_0 * 4][1];

    // x3 is low sign
    fullAdder fa0_2(.x(pprodsExt[row_0 * 4][2]), 
        .y(pprodsExt[row_0 * 4 + 1][0]), .cin(signsLow[row_0 * 4 + 1]), 
        .sum(sum_0[row_0][row_0 * 8 + 2]), 
    .cout(carry_0[row_0][row_0 * 8 + 2]));

    halfAdder ha_row0_3(.x(pprodsExt[row_0 * 4][3]), 
        .y(pprodsExt[row_0 * 4 + 1][1]), 
        .sum(sum_0[row_0][row_0 * 8 + 3]),
    .cout(carry_0[row_0][row_0 * 8 + 3]));

    // x4 is low sign
    compressor_42 comp_0_4(.x1(pprodsExt[row_0 * 4][4]), 
        .x2(pprodsExt[row_0 * 4 + 1][2]), 
        .x3(pprodsExt[row_0 * 4 + 2][0]), 
        .x4(signsLow[row_0 * 4 + 2]), .cin(1'b0), 
        .sum(sum_0[row_0][row_0 * 8 + 4]), 
        .carry(carry_0[row_0][row_0 * 8 + 4]), 
    .cout(hor_cout_0[row_0][row_0 * 8 + 4]));

    compressor_42 comp_0_5(.x1(pprodsExt[row_0 * 4][5]), 
        .x2(pprodsExt[row_0 * 4 + 1][3]),
        .x3(pprodsExt[row_0 * 4 + 2][1]), .x4(1'b0), 
        .cin(hor_cout_0[row_0][row_0 * 8 + 4]), 
        .sum(sum_0[row_0][row_0 * 8 + 5]),
        .carry(carry_0[row_0][row_0 * 8 + 5]), 
    .cout(hor_cout_0[row_0][row_0 * 8 + 5]));

    // MIDDLE

    genvar col;
    for (col = 6; col <= M + 3 - row_0 * 8; col = col + 1)
    begin: middle_0
        compressor_42 comp_mid_col(.x1(pprodsExt[row_0 * 4][col]), 
            .x2(pprodsExt[row_0 * 4 + 1][col - 2]),
            .x3(pprodsExt[row_0 * 4 + 2][col - 4]), 
            .x4(pprodsExt[row_0 * 4 + 3][col - 6]), 
            .cin(hor_cout_0[row_0][row_0 * 8 + col - 1]), 
            .sum(sum_0[row_0][row_0 * 8 + col]),
            .carry(carry_0[row_0][row_0 * 8 + col]), 
        .cout(hor_cout_0[row_0][row_0 * 8 + col]));
    end

    //TAIL

    compressor_42 comp_0_0_M_4(
        .x1(pprodsExt[row_0 * 4 + 1][M + 2 - row_0 * 8]), 
        .x2(pprodsExt[row_0 * 4 + 2][M + 2 - row_0 * 8 - 2]), 
        .x3(pprodsExt[row_0 * 4 + 3][M + 2 - row_0 * 8 - 4]), 
        .x4(pprodsExt[row_0 * 4 + 4][M + 2 - row_0 * 8 - 6]), 
        .cin(hor_cout_0[row_0][M + 3]), 
        .sum(sum_0[row_0][M + 4]), 
        .carry(carry_0[row_0][M + 4]),
    .cout(hor_cout_0[row_0][M + 4]));

    genvar j;

    for (j = row_0 * 4 + 2; j <= NPP - 4; j = j + 1)
    begin: comp_tail_0

        // x is 1's complement of sign 
        compressor_42 comp_0_2j(.x1(pprodsExt[j][M + 1 - row_0 * 8]), 
            .x2(pprodsExt[j + 1][M + 1 - row_0 * 8 - 2]),
            .x3(pprodsExt[j + 2][M + 1 - row_0 * 8 - 4]), 
            .x4(pprodsExt[j + 3][M + 1 - row_0 * 8 - 6]),
            .cin(hor_cout_0[row_0][M + 5 + ((j - (row_0 * 4 + 2)) * 2) - 1]), 
            .sum(sum_0[row_0][M + 5 + ((j - (row_0 * 4 + 2)) * 2)]), 
            .carry(carry_0[row_0][M + 5 + ((j - (row_0 * 4 + 2)) * 2)]), 
        .cout(hor_cout_0[row_0][M + 5 + ((j - (row_0 * 4 + 2)) * 2)]));

        compressor_42 comp_0_2j_1(.x1(pprodsExt[j][M + 1 - row_0 * 8 + 1]), 
            .x2(pprodsExt[j + 1][M + 1 - row_0 * 8 + 1 - 2]), 
            .x3(pprodsExt[j + 2][M + 1 - row_0 * 8 + 1 - 4]), 
            .x4(pprodsExt[j + 3][M + 1 - row_0 * 8 + 1 - 6]), 
            .cin(hor_cout_0[row_0][M + 5 + ((j - (row_0 * 4 + 2)) * 2)]), 
            .sum(sum_0[row_0][M + 5 + ((j - (row_0 * 4 + 2)) * 2) + 1]), 
            .carry(carry_0[row_0][M + 5 + ((j - (row_0 * 4 + 2)) * 2) + 1]), 
        .cout(hor_cout_0[row_0][M + 5 + ((j - (row_0 * 4 + 2)) * 2) + 1]));

    end

    // FINAL TAIL ADDERS
    compressor_42 comp_0_final_0(.x1(pprodsExt[NPP - 3][M + 1 - 8 * row_0]), 
        .x2(pprodsExt[NPP - 2][M + 1 - 8 * row_0 - 2]), 
        .x3(pprodsExt[NPP - 1][M + 1 - 8 * row_0 - 4]), 
        .x4(1'b0), .cin(hor_cout_0[row_0][2 * M - 5 - 8 * row_0]), 
        .sum(sum_0[row_0][2 * M - 4 - 8 * row_0]), 
        .carry(carry_0[row_0][2 * M - 4 - 8 * row_0]), 
    .cout(hor_cout_0[row_0][2 * M - 4 - 8 * row_0]));

    compressor_42 comp_0_final_1(.x1(pprodsExt[NPP - 3][M + 2 - 8 * row_0]), 
        .x2(pprodsExt[NPP - 2][M + 2 - 8 * row_0 - 2]), 
        .x3(pprodsExt[NPP - 1][M + 2 - 8 * row_0 - 4]), 
        .x4(1'b0), .cin(hor_cout_0[row_0][2 * M - 4 - 8 * row_0]), 
        .sum(sum_0[row_0][2 * M - 3 - 8 * row_0]), 
        .carry(carry_0[row_0][2 * M - 3 - 8 * row_0]), 
    .cout(hor_cout_0[row_0][2 * M - 3 - 8 * row_0]));

    fullAdder fa_0_final_0(.x(pprodsExt[NPP - 2][M + 1 - 8 * row_0]), 
        .y(pprodsExt[NPP - 1][M + 1 - 8 * row_0 - 2]), 
        .cin(hor_cout_0[row_0][2 * M - 3 - 8 * row_0]), 
        .sum(sum_0[row_0][2 * M - 2 - 8 * row_0]), 
    .cout(carry_0[row_0][2 * M - 2 - 8 * row_0])); 


    halfAdder ha_0_final_0(.x(pprodsExt[NPP - 2][M + 2 - 8 * row_0]), 
        .y(pprodsExt[NPP - 1][M - 8 * (row_0)]),  
        .sum(sum_0[row_0][2 * M - 1 - 8 * (row_0)]), 
    .cout(carry_0[row_0][2 * M - 1 - 8 * row_0]));
    for(j = 0; j < (row_0); j = j + NPP / 4) // skip row 0
    begin: row_0_g1_tail
        assign sum_0[row_0][2 * M - 8 * row_0] 
        = pprodsExt[NPP - 1][M - 7 - 8 * (row_0 - 1)] ;
        assign sum_0[row_0][2 * M + 1 - 8 * row_0] 
        = pprodsExt[NPP - 1][M - 6 - 8 * (row_0 - 1)];
        // signsLow
        assign sum_0[row_0][6 + 8 * (row_0 - 1)] = signsLow[4 * row_0 - 1];
    end 
end // end row_0 for

assign carry_0[0][1] = 1'b0; // needed for final addition

// level 6

// y is low sign of pprod
halfAdder ha_0_6_48(.x(pprodsExt[24][0]), .y(signsLow[24]), 
    .sum(sum_0[6][48]), 
.cout(carry_0[6][48]));

assign sum_0[6][49] = pprodsExt[24][1];

// x3 is low sign
fullAdder fa_0_6_50(.x(pprodsExt[24][2]), .y(pprodsExt[25][0]), 
    .cin(signsLow[25]), 
    .sum(sum_0[6][50]),
.cout(carry_0[6][50]));

halfAdder ha_0_6_51(.x(pprodsExt[24][3]), .y(pprodsExt[25][1]), 
    .sum(sum_0[6][51]), 
.cout(carry_0[6][51]));

for(i = 0; i <= 4; i++)
begin: fa_0_6_middle_loop
    fullAdder fa_0_6_middle(.x(pprodsExt[24][4 + i]), .y(pprodsExt[25][2 + i]), 
        .cin(pprodsExt[26][i]), 
        .sum(sum_0[6][52 + i]),
    .cout(carry_0[6][52 + i]));
end

halfAdder ha_0_6_57(.x(pprodsExt[25][7]), .y(pprodsExt[26][5]), 
    .sum(sum_0[6][57]), 
.cout(carry_0[6][57]));

assign sum_0[6][58] = pprodsExt[26][6];
assign sum_0[6][59] = pprodsExt[26][7];
// signsLow
assign sum_0[6][46] = signsLow[23];
assign sum_0[7][52] = signsLow[26];
///END **** level 0 - NPP / 4 - 1 ****///


///**** level 1: row 0 - NPP / 8 - 1 ****///

// PASS-THROUGHS
// sum and carry values for final addition
for(i = 0; i <= 5; i++)
begin: level_1_sumPassThroughs
    assign sum_1[0][i] = sum_0[0][i];
end
for(i = 0; i <= 4; i++)
begin: level_0_sumPassThroughs
    assign carry_1[0][i] = carry_0[0][i];
end
assign carry_1[0][5] = 1'b0;

genvar row_1;

// row >= 1 only, including 3

for(row_1 = 1; row_1 <= NPP / 8 ; row_1 = row_1 + 1)
begin: row_1_g1_pre

    halfAdder ha_pre_row_1_1(.x(sum_0[2 * row_1][16 * row_1 + 1]), 
        .y(carry_0[2 * row_1][16 * row_1]), 
    .sum(sum_1[row_1][16 * row_1 + 1]), .cout(carry_1[row_1][16 * row_1 + 1]));
    genvar j;
    for(j = 3; j <= 5 + 5 * (row_1 == 3); j = j + 1)
    begin: level_1_g1_pre_3
        if ((row_1 == NPP / 8) && (j == 4)) // signLow of last PP for signed mul. Needed because N is odd
        fullAdder fa_pre_row_1_3_last_signsLow(.x(sum_0[row_1 * 2][j + 16 * row_1]), 
            .y(carry_0[row_1 * 2][j - 1 + 16 * row_1]), .cin(sum_0[row_1 * 2 + 1][j + 16 * row_1]), 
        .sum(sum_1[row_1][j + 16 * row_1]), .cout(carry_1[row_1][j + 16 * row_1]));
        else
        halfAdder ha_pre_row_1_3(.x(sum_0[row_1 * 2][j + 16 * row_1]), 
            .y(carry_0[row_1 * 2][j - 1 + 16 * row_1]), 
        .sum(sum_1[row_1][j + 16 * row_1]), .cout(carry_1[row_1][j + 16 * row_1]));
    end
    assign sum_1[row_1][14 + 16 * (row_1 - 1)] = sum_0[2 * row_1][14 + 16 * (row_1 - 1)]; //signsLow
    assign sum_1[row_1][16 + 16 * (row_1 - 1)] = sum_0[2 * row_1][16 + 16 * (row_1 - 1)];
    assign sum_1[row_1][18 + 16 * (row_1 - 1)] = sum_0[2 * row_1][18 + 16 * (row_1 - 1)];
    assign sum_1[row_1][2 * M - 15 - 16 * (row_1 - 1)] = 
    sum_0[2 * row_1][2 * M - 15 - 16 * (row_1 - 1)];
end

// rows
for(row_1 = 0; row_1 < NPP / 8; row_1 = row_1 + 1)
begin: pre_1

    // PREAMBLE

    fullAdder fa_pre_row_1_6(.x(sum_0[row_1 * 2][6 + 16 * row_1]),
        .y(carry_0[row_1 * 2][6 - 1 + 16 * row_1]), 
        .cin(sum_0[row_1 * 2 + 1][6 + 16 * row_1]), 
        .sum(sum_1[row_1][6 + 16 * row_1]), 
    .cout(carry_1[row_1][6 + 16 * row_1]));
    halfAdder ha_pre_row_1_7(.x(sum_0[row_1 * 2][7 + 16 * row_1]),
        .y(carry_0[row_1 * 2][7 - 1 + 16 * row_1]), 
        .sum(sum_1[row_1][7 + 16 * row_1]), 
    .cout(carry_1[row_1][7 + 16 * row_1]));
    fullAdder fa_pre_row_1_8(.x(sum_0[row_1 * 2][8 + 16 * row_1]),
        .y(carry_0[row_1 * 2][8 - 1 + 16 * row_1]), 
        .cin(sum_0[row_1 * 2 + 1][8 + 16 * row_1]), 
        .sum(sum_1[row_1][8 + 16 * row_1]), 
    .cout(carry_1[row_1][8 + 16 * row_1]));
    compressor_42 ca_pre_row_1_9(.x1(sum_0[row_1 * 2][9 + 16 * row_1]), 
        .x2(carry_0[row_1 * 2][9 - 1 + 16 * row_1]), 
        .x3(sum_0[row_1 * 2 + 1][9 + 16 * row_1]),
        .x4(carry_0[row_1 * 2 + 1][9 - 1 + 16 * row_1]),
        .cin(1'b0),
        .sum(sum_1[row_1][9 + 16 * row_1]), 
        .carry(carry_1[row_1][9 + 16 * row_1]),
    .cout(hor_cout_1[row_1][9 + 16 * row_1]));
    compressor_42 ca_pre_row_1_10(.x1(sum_0[row_1 * 2][10 + 16 * row_1]), 
        .x2(carry_0[row_1 * 2][10 - 1 + 16 * row_1]), 
        .x3(sum_0[row_1 * 2 + 1][10 + 16 * row_1]),
        .x4(1'b0),
        .cin(hor_cout_1[row_1][10 - 1 + 16 * row_1]),
        .sum(sum_1[row_1][10 + 16 * row_1]), 
        .carry(carry_1[row_1][10 + 16 * row_1]),
    .cout(hor_cout_1[row_1][10 + 16 * row_1]));

    // MIDDLE
    genvar j;
    for(j = 11 + 16 * row_1; j <= 2 * M - 8 - 16 * row_1; j = j + 1)
    begin: row_1_comp_middle
        compressor_42 comp_1_middle(.x1(sum_0[row_1 * 2][j]),
            .x2(carry_0[row_1 * 2][j - 1]), 
            .x3(sum_0[row_1 * 2 + 1][j]), 
            .x4(carry_0[row_1 * 2 + 1][j - 1]), .cin(hor_cout_1[row_1][j - 1]), 
            .sum(sum_1[row_1][j]), 
        .carry(carry_1[row_1][j]), .cout(hor_cout_1[row_1][j]));
    end

    compressor_42 comp_1_middle_2_M_7(
        .x1(sum_0[row_1 * 2][2 * M - 7 - 16 * row_1]), 
        .x2(carry_0[row_1 * 2][2 * M - 8 - 16 * row_1]), 
        .x3(sum_0[row_1 * 2 + 1][2 * M - 7 - 16 * row_1]), 
        .x4(1'b0), .cin(hor_cout_1[row_1][2 * M - 8 - 16 * row_1]), 
        .sum(sum_1[row_1][2 * M - 7 - 16 * row_1]), 
        .carry(carry_1[row_1][2 * M - 7 - 16 * row_1]), 
    .cout(hor_cout_1[row_1][2 * M - 7 - 16 * row_1]));

    //TAIL
    fullAdder fa_1_tail_2_M_6(.x(sum_0[row_1 * 2][2 * M - 6 - 16 * row_1]), 
        .y(carry_0[row_1 * 2][2 * M - 7 - 16 * row_1]), 
        .cin(hor_cout_1[row_1][2 * M - 7 - 16 * row_1]), 
        .sum(sum_1[row_1][2 * M - 6 - 16 * row_1]), 
    .cout(carry_1[row_1][2 * M - 6 - 16 * row_1]));

    for(j = 2 * M - 5 - 16 * row_1; j <= 2 * M - 1 - 16 * row_1 + (row_1 > 0); j = j + 1)
    begin: tail_1
        halfAdder ha_1_tail(.x(sum_0[row_1 * 2][j]), .y(carry_0[row_1 * 2][j - 1]), 
            .sum(sum_1[row_1][j]), 
        .cout(carry_1[row_1][j]));
    end

end // end row_1 for 

///**** END level 1 ****///


///**** level 2 ****///

// PASS-THROUGHS
// sum and carry values for final addition
for(i = 0; i <= 13; i++)
begin: level_2_sumPassThroughs
    assign sum_2[0][i] = sum_1[0][i];
end
for(i = 0; i <= 12; i++)
begin: level_2_carryPassThroughs
    assign carry_2[0][i] = carry_1[0][i];
end
assign carry_2[0][13] = 1'b0;

genvar row_2;
for(row_2 = 1; row_2 <= NPP / 16 ; row_2 = row_2 + 1)
begin: pre_2_g1
    // row >= 1 only PREAMBLE halfAdder / assign
    halfAdder ha_pre_row_2_1(.x(sum_1[2 * row_2][32 * row_2 + 2]), 
        .y(carry_1[2 * row_2][32 * row_2 + 1]), 
    .sum(sum_2[row_2][32 * row_2 + 2]), .cout(carry_2[row_2][32 * row_2 + 2]));

    genvar j;
    for(j = 32 * row_2 + 4 ; j <= 32 * row_2 + 4 + 9; j = j + 1) // only row 1
    begin: ha_pre_row_2_10
        halfAdder ha_pre_row_2_3(.x(sum_1[row_2 * 2][j]), 
            .y(carry_1[row_2 * 2][j - 1]), 
        .sum(sum_2[row_2][j]), .cout(carry_2[row_2][j]));
    end
    assign sum_2[row_2][32 * row_2 - 2] = sum_1[2 * row_2][32 * row_2 - 2]; //signsLow
    assign sum_2[row_2][32 * row_2] = sum_1[2 * row_2][32 * row_2];
    assign sum_2[row_2][32 * row_2 + 1] = sum_1[2 * row_2][32 * row_2 + 1];
    assign sum_2[row_2][32 * row_2 + 3] = sum_1[2 * row_2][32 * row_2 + 3];
end

for(row_2 = 0; row_2 <= NPP / 16; row_2 = row_2 + 1)
begin: row_2_for

    // PREAMBLE

    fullAdder fa_pre_row_2_14(.x(sum_1[row_2 * 2][14 + 32 * row_2]),
        .y(carry_1[row_2 * 2][13 + 32 * row_2]), 
        .cin(sum_1[row_2 * 2 + 1][14 + 32 * row_2]), 
        .sum(sum_2[row_2][14 + 32 * row_2]), 
    .cout(carry_2[row_2][14 + 32 * row_2]));
    halfAdder ha_pre_row_2_15(.x(sum_1[row_2 * 2][15 + 32 * row_2]),
        .y(carry_1[row_2 * 2][14 + 32 * row_2]), 
        .sum(sum_2[row_2][15 + 32 * row_2]), 
    .cout(carry_2[row_2][15 + 32 * row_2]));
    fullAdder fa_pre_row_2_16(.x(sum_1[row_2 * 2][16 + 32 * row_2]),
        .y(carry_1[row_2 * 2][15 + 32 * row_2]), 
        .cin(sum_1[row_2 * 2 + 1][16 + 32 * row_2]), 
        .sum(sum_2[row_2][16 + 32 * row_2]), 
    .cout(carry_2[row_2][16 + 32 * row_2]));
    fullAdder fa_pre_row_2_17(.x(sum_1[row_2 * 2][17 + 32 * row_2]),
        .y(carry_1[row_2 * 2][16 + 32 * row_2]), 
        .cin(sum_1[row_2 * 2 + 1][17 + 32 * row_2]), 
        .sum(sum_2[row_2][17 + 32 * row_2]), 
    .cout(carry_2[row_2][17 + 32 * row_2]));
    compressor_42 ca_pre_row_2_18(.x1(sum_1[row_2 * 2][18 + 32 * row_2]), 
        .x2(carry_1[row_2 * 2][17 + 32 * row_2]), 
        .x3(sum_1[row_2 * 2 + 1][18 + 32 * row_2]),
        .x4(carry_1[row_2 * 2 + 1][17 + 32 * row_2]),
        .cin(1'b0),
        .sum(sum_2[row_2][18 + 32 * row_2]), 
        .carry(carry_2[row_2][18 + 32 * row_2]),
    .cout(hor_cout_2[row_2][18 + 32 * row_2]));
    compressor_42 ca_pre_row_2_19(.x1(sum_1[row_2 * 2][19 + 32 * row_2]), 
        .x2(carry_1[row_2 * 2][18 + 32 * row_2]), 
        .x3(sum_1[row_2 * 2 + 1][19 + 32 * row_2]),
        .x4(1'b0),
        .cin(hor_cout_2[row_2][18 + 32 * row_2]),
        .sum(sum_2[row_2][19 + 32 * row_2]), 
        .carry(carry_2[row_2][19 + 32 * row_2]),
    .cout(hor_cout_2[row_2][19 + 32 * row_2]));

    for(i = 20 + 32 * row_2; i <= 2 * M - 15 - 32 * row_2; i = i + 1)
    begin: row_2_middle
        compressor_42 comp_2(.x1(sum_1[2 * row_2][i]),
            .x2(carry_1[2 * row_2][i - 1]),
            .x3(sum_1[2 * row_2 + 1][i]), 
            .x4(carry_1[2 * row_2 + 1][i - 1]), 
            .cin(hor_cout_2[row_2][i - 1]),
            .sum(sum_2[row_2][i]), 
            .carry(carry_2[row_2][i]), 
        .cout(hor_cout_2[row_2][i]));
    end

    fullAdder fa_2_tail_2M_14(.x(sum_1[2 * row_2][2 * M - 14 - 32 * row_2]), 
        .y(carry_1[2 * row_2][2 * M - 15 - 32 * row_2]),
        .cin(hor_cout_2[row_2][2 * M - 15 - 32 * row_2]), 
        .sum(sum_2[row_2][2 * M - 14 - 32 * row_2]), 
    .cout(carry_2[row_2][2 * M - 14 - 32 * row_2]));

    for(i = 2 * M - 13 - 32 * row_2; i <= 2 * M - 1 - 32 * row_2 + 2 * (row_2 > 0); i = i + 1)
    begin: ha_2_final
        halfAdder ha_2_final(.x(sum_1[2 * row_2][i]), .y(carry_1[2 * row_2][i - 1]),
        .sum(sum_2[row_2][i]), .cout(carry_2[row_2][i]));
    end
end // end row_2 for

///END **** level 2 ****///


///*** level 3 ***///
// PASS-THROUGHS
// sum and carry values for final addition
for(i = 0; i <= 29; i++)
begin: level_3_sumPassThroughs
    assign sum_3[0][i] = sum_2[0][i];
end
for(i = 0; i <= 28; i++)
begin: level_3_carryPassThroughs
    assign carry_3[0][i] = carry_2[0][i];
end
assign carry_3[0][29] = 1'b0;


genvar row_3;

for(row_3 = 0; row_3 <= NPP / 32; row_3 = row_3 + 1)
begin: row_3_for
    fullAdder fa_3_30(.x(sum_2[row_3][30]), .y(carry_2[row_3][29]), 
        .cin(sum_2[row_3 + 1][30]),
    .sum(sum_3[row_3][30]), .cout(carry_3[row_3][30]));

    halfAdder ha_3_31(.x(sum_2[row_3][31]), .y(carry_2[row_3][30]),
    .sum(sum_3[row_3][31]), .cout(carry_3[row_3][31]));

    for(i = 32; i <= 34; i = i + 1)
    begin: pre_3
        fullAdder fa_3_pre(.x(sum_2[row_3][i]), .y(carry_2[row_3][i - 1]), 
            .cin(sum_2[row_3 + 1][i]),
        .sum(sum_3[row_3][i]), .cout(carry_3[row_3][i]));
    end
    compressor_42 comp_3_pre_35(.x1(sum_2[row_3][35]), 
        .x2(carry_2[row_3][34]),
        .x3(sum_2[row_3 + 1][35]), .x4(carry_2[row_3 + 1][34]), .cin(1'b0),
        .sum(sum_3[row_3][35]), .carry(carry_3[row_3][35]), 
    .cout(hor_cout_3[row_3][35]));
    compressor_42 comp_3_pre_36(.x1(sum_2[row_3][36]), 
        .x2(carry_2[row_3][35]),
        .x3(sum_2[row_3 + 1][36]), .x4(1'b0), .cin(hor_cout_3[row_3][35]),
        .sum(sum_3[row_3][36]), .carry(carry_3[row_3][36]), 
    .cout(hor_cout_3[row_3][36]));
    for(i = 37; i <= 2 * M - 31; i = i + 1)
    begin: comp_3_middle
        compressor_42 comp_3_pre(.x1(sum_2[row_3][i]), .x2(carry_2[row_3][i - 1]),
            .x3(sum_2[row_3 + 1][i]), .x4(carry_2[row_3 + 1][i - 1]), 
            .cin(hor_cout_3[row_3][i - 1]),
        .sum(sum_3[row_3][i]), .carry(carry_3[row_3][i]), .cout(hor_cout_3[row_3][i]));
    end

    compressor_42 comp_3_pre_last(.x1(sum_2[row_3][2 * M - 30]), 
        .x2(carry_2[row_3][2 * M - 31]),
        .x3(carry_2[row_3 + 1][2 * M - 31]),  .x4(1'b0), 
        .cin(hor_cout_3[row_3][2 * M - 31]),
        .sum(sum_3[row_3][2 * M - 30]), .carry(carry_3[row_3][2 * M - 30]), 
    .cout(hor_cout_3[row_3][2 * M - 30]));

    fullAdder fa_3_tail_M_29(.x(sum_2[row_3][2 * M - 29]),
        .y(carry_2[row_3][2 * M - 30]), 
        .cin(hor_cout_3[row_3][2 * M - 30]),
    .sum(sum_3[row_3][2 * M - 29]), .cout(carry_3[row_3][2 * M - 29]));

    for(i = 2 * M - 28; i <= 2 * M - 1; i = i + 1)
    begin: ha_3_tail
        halfAdder ha_3_tail(.x(sum_2[row_3][i]), .y(carry_2[row_3][i - 1]),
        .sum(sum_3[row_3][i]), .cout(carry_3[row_3][i]));
    end

end // end row_3 for

///***end level 3 ***///
endgenerate
//**** Final addition ****//
claAddSub106 finalCLAadder106(.sub(1'b0), .cin(1'b0),
    .x({sum_3[0][105 : 0]}), 
    .y({carry_3[0][104 : 0], 1'b0}), 
    .out(out[105 : 0]), .cout(), .v(),
.g(), .p());
endmodule


// main module
module fp_mul
#(parameter BITS = 32, parameter MANTISSA_BITS = 23, parameter EXPONENT_BITS = 8) // MANTISSA_BITS + EXPONENT_BITS must be equal to BITS - 1 (1 bit is for sign)
(
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

logic [MANTISSA_BITS - 1 : 0] xM;
logic [MANTISSA_BITS + 1 - 1 : 0] xMantissa; // includes hidden bit
logic [MANTISSA_BITS - 1 : 0] yM;
logic [MANTISSA_BITS + 1 - 1 : 0] yMantissa; // includes hidden bit
logic [MANTISSA_BITS + 1 - 1 : 0] normalizedMantissa; // includes hidden bit
logic [MANTISSA_BITS + 1 - 1 : 0] normalizedMantissa2; // includes hidden bit
logic [MANTISSA_BITS + 1 - 1 : 0] zMantissa; // includes hidden bit
logic [2 * (MANTISSA_BITS + 1) - 1 : 0] prod; // includes hidden bit * 2
logic [EXPONENT_BITS - 1 : 0] xE; 
logic [EXPONENT_BITS - 1 : 0] xExponent; 
logic [EXPONENT_BITS - 1 : 0] yE; 
logic [EXPONENT_BITS - 1 : 0] yExponent; 
logic [EXPONENT_BITS + 1 : 0] tentativeExponent; // includes carry bit and sign bit to handle overflow and underflow
logic [EXPONENT_BITS + 1 : 0] tentativeExponent2; // includes carry bit and sign bit to handle overflow and underflow
logic [EXPONENT_BITS - 1 : 0] zExponent; 
logic [$clog2((MANTISSA_BITS + 1) * 2) - 1 : 0] normalizeShiftAmount;
logic [EXPONENT_BITS + 1 : 0] rightShiftAmount;
logic xS;
logic yS;

logic zSign;

// extra bits for round to nearest
// normalization
logic guardBit;
logic roundBit;
logic stickyBit;
// underflow recovery / right shift
logic guardBit2;
logic roundBit2;
logic stickyBit2;
logic roundFlag;

logic shiftUnderflowFlag;

// input unpacking
assign xM = x[MANTISSA_BITS - 1 : 0];
assign yM = y[MANTISSA_BITS - 1 : 0];
assign xE = x[BITS - 2 : BITS - 1 - EXPONENT_BITS];
assign yE = y[BITS - 2 : BITS - 1 - EXPONENT_BITS];
assign xS = x[BITS - 1];
assign yS = y[BITS - 1];

// output
assign out[BITS - 1] = zSign;
assign out[BITS - 2 : BITS - 1 - EXPONENT_BITS] = zExponent;
assign out[BITS - 1 - EXPONENT_BITS - 1 : 0] = zMantissa[MANTISSA_BITS + 1 - 2 : 0];

// assign prod = xMantissa * yMantissa;
Radix4BoothWallace53 mult(.signedFlag(1'b0), .multiplicand(xMantissa), .multiplier(yMantissa), .out(prod));

// Handle regular and denormal numbers
always_comb
begin: denormOrRegular
	xMantissa[MANTISSA_BITS - 1 : 0] = {xM};
	yMantissa[MANTISSA_BITS - 1 : 0] = {yM};

	if (xE == zeroOrDenormBiasedExponent) // x is denormal, set exponent to min
	begin: xDenorm
		xExponent = minBiasedExponent;
		xMantissa[MANTISSA_BITS] = 1'b0;					
	end
	else // x is regular, set hidden bit to 1
	begin: xRegular
		xExponent = xE;
		xMantissa[MANTISSA_BITS] = 1'b1;					
	end
	if (yE == zeroOrDenormBiasedExponent) // y is denormal, set exponent to min
	begin: yDenorm
		yExponent = minBiasedExponent;
		yMantissa[MANTISSA_BITS] = 1'b0;					
	end
	else // y is regular, set hidden bit to 1
	begin: yRegular
		yExponent = yE;
		yMantissa[MANTISSA_BITS] = 1'b1;					
	end
end

// shift amount for normalization
zeroMSBCounter #(.N(((MANTISSA_BITS + 1) * 2))) msbZerosSum(prod[(MANTISSA_BITS + 1) * 2 - 1 : 0], normalizeShiftAmount);

// round-to-nearest extra bits
//assign guardBit = (normalizeShiftAmount != 0) ? ((normalizeShiftAmount > 1) ? 1'b0 : prod[MANTISSA_BITS - 1]) : prod[MANTISSA_BITS];
assign guardBit = (normalizeShiftAmount <= MANTISSA_BITS) ? prod[MANTISSA_BITS - normalizeShiftAmount] : 1'b0;
assign roundBit = (normalizeShiftAmount <= MANTISSA_BITS - 1) ? prod[MANTISSA_BITS - 1 - normalizeShiftAmount] : 1'b0;
assign stickyBit = prod[MANTISSA_BITS - 2 : 0] != 0;

// normalized mantissa
assign normalizedMantissa = (prod[((MANTISSA_BITS + 1) * 2) - 1 : 0] << normalizeShiftAmount) >> (MANTISSA_BITS + 1);

// tentative exponent, add 1 to exponent to "move decimal point one digit to the left" as prod has form DD.ddd....d and will be interpreted as D.Dddd....d
assign tentativeExponent = {2'b00, xExponent} + {2'b00, yExponent} - exponentBias + 1 - normalizeShiftAmount;

assign shiftUnderflowFlag = $signed(tentativeExponent) < $signed(minBiasedExponent); 

assign rightShiftAmount = minBiasedExponent - tentativeExponent;

assign tentativeExponent2 = shiftUnderflowFlag ? tentativeExponent + rightShiftAmount : tentativeExponent;

assign guardBit2 = (shiftUnderflowFlag) ? (normalizedMantissa >> (rightShiftAmount - 1)) & 1 : guardBit;
assign roundBit2 = (shiftUnderflowFlag) ? rightShiftAmount > 1 ? (normalizedMantissa >> rightShiftAmount - 2) & 1 : guardBit : roundBit;
assign stickyBit2 = stickyBit | (shiftUnderflowFlag ? ((rightShiftAmount > 2) ? (normalizedMantissa >> rightShiftAmount - 3) & 1 : ((rightShiftAmount > 1) ? guardBit : roundBit)) : 0);

// normalized mantissa
assign normalizedMantissa2 = shiftUnderflowFlag ? normalizedMantissa >> rightShiftAmount : normalizedMantissa;

assign roundFlag = guardBit2 && (normalizedMantissa2[0] | roundBit2 | stickyBit2);

always_comb
begin: handleCases
	if (((xE == infBiasedExponent) && (xM != 0)) ||  ((yE == infBiasedExponent) && (yM != 0)))
	begin: NaN
		zSign = 1'b0; 
		zExponent = infBiasedExponent;
		zMantissa = {1'b0, nanMantissa};
	end
	// if x is infinity
	else if (xE == infBiasedExponent) // xM == 0
	begin: xInf
		if ((yE == zeroOrDenormBiasedExponent) && (yM == 0)) // if y is zero return NaN
		begin: infTimesZero
			zSign = 1'b0; 
			zExponent = infBiasedExponent;	
			zMantissa = {1'b0, nanMantissa};
		end
		else
		begin: xInfRes
			zSign = xS ^ yS;
			zExponent = infBiasedExponent;
			zMantissa = 0;
		end
	end
	else if (yE == infBiasedExponent) // if y is infinity
	begin: yInf
		if ((xE == zeroOrDenormBiasedExponent) && (xM == 0)) // if x is zero return NaN
		begin: ZeroTimesInf
			zSign = 1'b0;
			zExponent = infBiasedExponent;
			zMantissa = {1'b0, nanMantissa};
		end
		else
		begin: yInfRes
			zSign = xS ^ yS; 
			zExponent = infBiasedExponent;	
			zMantissa = 0;
		end
	end
	else if (((xE == zeroOrDenormBiasedExponent) && (xM == 0)) || ((yE == zeroOrDenormBiasedExponent) && (yM == 0))) // either x or y are zero
	begin: xZeroOryZero 
		zSign = xS ^ yS;
		zExponent = zeroOrDenormBiasedExponent;
		zMantissa = 0;
	end
	else // denormal number or regular number
	begin: denormOrRegularAdd
		if(roundFlag == 1'b1)
		begin: doRounding
			zMantissa = (tentativeExponent2 < infBiasedExponent) ? normalizedMantissa2 + 1 : {(MANTISSA_BITS + 1){1'b0}};
			if(normalizedMantissa2 == {(MANTISSA_BITS + 1){1'b1}}) // if carry out after rounding
			begin: roundingCarry
				if(!(tentativeExponent2 == maxBiasedExponent || tentativeExponent2 == infBiasedExponent)) // if not overflow or infinity
				begin: roundingExpPlus1
					zExponent = tentativeExponent2[EXPONENT_BITS - 1 : 0] + 1;
				end
				else
				begin: roundingInf
					zExponent = infBiasedExponent;
				end
			end
			else
			begin: roundingNoCarry
				if((tentativeExponent2 == minBiasedExponent) && (normalizedMantissa2[MANTISSA_BITS + 1 - 1] == 1'b0)) // denorm or zero
				begin: roundingDenorm
					zExponent = zeroOrDenormBiasedExponent;
				end
				else
				begin: roundingNumber
					zExponent = (tentativeExponent2 < infBiasedExponent) ? tentativeExponent2[EXPONENT_BITS - 1 : 0] : infBiasedExponent;
				end
			end
		end
		else
		begin: noRounding
			zMantissa = (tentativeExponent2 < infBiasedExponent) ? normalizedMantissa2 : {(MANTISSA_BITS + 1){1'b0}};
			if((tentativeExponent2 == minBiasedExponent) && (normalizedMantissa2[MANTISSA_BITS + 1 - 1] == 1'b0)) // denorm or zero
			begin: noRoundingDenorm
				zExponent = zeroOrDenormBiasedExponent;	
			end
			else
			begin: noRoundingNumber
				zExponent = (tentativeExponent2 < infBiasedExponent) ? tentativeExponent2[EXPONENT_BITS - 1 : 0] : infBiasedExponent;
			end
		end

		zSign = xS ^ yS;
	end
end

endmodule