// Floating point exponent. Exponent is implemented based on identity a^b = e^(b*ln(a)).
// Exponential (e^x) is implemented as nested polynomial approximation; from https://github.com/OmarFaseeh/Verilog-CNN/blob/master/exponential.v
// Logarithm (ln(x)) is implemented using LUTs; based on https://github.com/UT-LCA/LogGen# - using EXPONENT=5 MANTISSA=10 ACCURACY=8 BASE=e
// Other operations are as implemented in specific functional units (eg fp_mul)


// exponential helper + main modules
module fpMul(flp_a,
flp_b,
sign,
exponent,
prod,
clk
);

parameter EXPONENT_WIDTH = 5;
parameter MANTISSA_WIDTH = 10;

//I/O, variables
input wire [EXPONENT_WIDTH+MANTISSA_WIDTH:0] flp_a, flp_b;
input wire clk;

output reg sign;
output reg [EXPONENT_WIDTH-1:0] exponent;
reg [EXPONENT_WIDTH:0] exp_sum;
output reg [MANTISSA_WIDTH-1:0] prod;
reg [2*(MANTISSA_WIDTH+1):0] product;

//reg cat_a,cat_b;

always @ (posedge clk) 
begin  
    //extra accurate but might cause issues?
    /*if(flp_a[EXPONENT_WIDTH+MANTISSA_WIDTH-1:MANTISSA_WIDTH]>0) cat_a=1;
    else cat_a=0;
    if(flp_b[EXPONENT_WIDTH+MANTISSA_WIDTH-1:MANTISSA_WIDTH]>0) cat_b=1;
    else cat_b=0;
    product = {cat_a ,flp_a[MANTISSA_WIDTH-1:0]}*{cat_b ,flp_b[MANTISSA_WIDTH-1:0]};*/
    product = {1'b1 ,flp_a[MANTISSA_WIDTH-1:0]}*{1'b1 ,flp_b[MANTISSA_WIDTH-1:0]};
    prod = 0;
    exp_sum = flp_a[EXPONENT_WIDTH+MANTISSA_WIDTH-1:MANTISSA_WIDTH]+flp_b[EXPONENT_WIDTH+MANTISSA_WIDTH-1:MANTISSA_WIDTH];
    if (product[2*MANTISSA_WIDTH+1]==1) exp_sum=exp_sum+1; //If we had a carry, then increment exponent
    sign = flp_a[EXPONENT_WIDTH+MANTISSA_WIDTH] ^ flp_b[EXPONENT_WIDTH+MANTISSA_WIDTH];
    if(product[2*MANTISSA_WIDTH+1] ==1) begin
        prod = product[2*MANTISSA_WIDTH:MANTISSA_WIDTH+1];
    end else begin
        prod = product[2*MANTISSA_WIDTH-1:MANTISSA_WIDTH];
    end
    //underflow case
    if(exp_sum<(2**(EXPONENT_WIDTH-1)-1))begin
            //prod = {1'b1 ,prod } >> (2**(EXPONENT_WIDTH-1)-1)-exp_sum; //extra unneeded accuracy
            exp_sum=0;
     end else
            exp_sum=exp_sum-(2**(EXPONENT_WIDTH-1)-1);
     exponent = exp_sum[EXPONENT_WIDTH-1:0];
    
    //handle case of multiplying by zero
    if(flp_a[MANTISSA_WIDTH+EXPONENT_WIDTH-1:0]==0 || flp_b[MANTISSA_WIDTH+EXPONENT_WIDTH-1:0]==0) begin
        exponent = 0;
        prod = 0;
        sign = 0;
    end        
end
endmodule

module fp_add (A_FP, B_FP, sign, exponent, mantissa, clk, done
);

parameter EXPONENT_WIDTH = 5;
parameter MANTISSA_WIDTH = 10;

input wire [EXPONENT_WIDTH+MANTISSA_WIDTH:0] A_FP; 
input wire [EXPONENT_WIDTH+MANTISSA_WIDTH:0] B_FP;
input wire clk;
output reg       sign; 
output reg       done; 
output reg [EXPONENT_WIDTH-1:0] exponent; 
output reg [MANTISSA_WIDTH-1:0] mantissa;

//variables used in an always block
//are declared as registers
reg sign_a, sign_b,sign_c;
reg [EXPONENT_WIDTH-1:0] e_A, e_B;
reg [MANTISSA_WIDTH:0] fract_a, fract_b,fract_c, mantissa;//frac = 1 . mantissa 
reg [EXPONENT_WIDTH-1:0] shift_cnt;
reg cout;
reg [5:0] i;

always @ (negedge clk)
begin
	sign_a  = A_FP [EXPONENT_WIDTH+MANTISSA_WIDTH]; 
	sign_b  = B_FP [EXPONENT_WIDTH+MANTISSA_WIDTH];
	e_A      = A_FP [EXPONENT_WIDTH+MANTISSA_WIDTH-1:EXPONENT_WIDTH];
	e_B      = B_FP [EXPONENT_WIDTH+MANTISSA_WIDTH-1:EXPONENT_WIDTH];
	fract_a  = {1'b1,A_FP [EXPONENT_WIDTH-1:0]};
	fract_b  = {1'b1,B_FP [EXPONENT_WIDTH-1:0]};
	//align fractions
	if (e_A < e_B)
    begin
	 shift_cnt  = e_B - e_A;
     fract_a   = fract_a >> shift_cnt;
     e_A  = e_A + shift_cnt;  
    end 
    
	if (e_B < e_A)
    begin
		shift_cnt  = e_A - e_B;
    	fract_b  = fract_b >> shift_cnt;
	   e_B  = e_B + shift_cnt;
   end 
	//add fractions
	if(sign_a==sign_b) begin    //if both numbers have the same sign add them
           sign  = sign_a;      //sign = any sign doesn't matter
	       {cout, fract_c}  = fract_a + fract_b;
	       if (cout)            //if there is carry shift and increment the exp
               begin
                   {cout, fract_c}  = {cout, fract_c} >> 1;
                   e_B  = e_B + 1;
               end
         mantissa  = fract_c[MANTISSA_WIDTH-1:0];
	 end else if(sign_a) begin  //if a is negative 
           {cout, fract_c}  =fract_b - fract_a;
           if(fract_a > fract_b) begin
                sign = 1'b1;
                fract_c = -fract_c;
           end else 
                sign =1'b0;
	 end else begin             //if b is negative
	         {cout, fract_c}  =fract_a - fract_b;
             if(fract_b > fract_a) begin
                     sign = 1'b1;
                     fract_c = -fract_c;
                 end else
                     sign =1'b0;
                 
	 end
	
    if(fract_a == fract_b && sign_a != sign_b) begin // handel the case of zero 
        sign= 1'b0;
        e_B = 0;
        fract_c[MANTISSA_WIDTH] = 1; //the one will be removed
        fract_c[MANTISSA_WIDTH-1:0] = {MANTISSA_WIDTH{1'b0}};
    end
    //normalize result
    for(i = 0; i < MANTISSA_WIDTH && fract_c[MANTISSA_WIDTH]==0; i=i+1) begin
        fract_c = fract_c << 1;
        e_B = e_B-1'b1; 
    end
    mantissa = fract_c[MANTISSA_WIDTH-1:0];
    exponent = e_B; 
	done = 1;
end

always@(posedge clk)
    done = 0; 

endmodule

module exponential ( input_exp,clk,output_exp,done_exp, reset_exp);
parameter EXPONENT_WIDTH = 5;
parameter MANTISSA_WIDTH = 10;
parameter DATA_WIDTH = EXPONENT_WIDTH+MANTISSA_WIDTH+1;
input [DATA_WIDTH-1:0]       input_exp ;
input clk ,reset_exp;
output reg[DATA_WIDTH-1:0] output_exp ;
output reg done_exp ;

wire [DATA_WIDTH-1:0] output_tmp_mul;
wire [DATA_WIDTH-1:0] output_tmp_add;
wire done;

reg [4:0] i;
/*
reg [(DATA_WIDTH-1):0] const_OneSix=32'b00111110001010101010101010101011;
reg [(DATA_WIDTH-1):0] const_OneFifths=32'b00111110010011001100110011001101;
reg [(DATA_WIDTH-1):0] const_OneQuarter=32'b00111110100000000000000000000000;
reg [(DATA_WIDTH-1):0] const_OneThird=32'b00111110101010101010101010101011;
reg [(DATA_WIDTH-1):0] const_Half=32'b00111111000000000000000000000000;
reg [(DATA_WIDTH-1):0] const_One=32'b00111111100000000000000000000000;*/

// I simlified the equation taking many common factors to just multiply by x^1
// The equation is:
// 1+X(1+(X/2)(1+(X/3)(1+(X/4)(1+(X/5)(1+(X/6))))))

// Constants of the equation
reg [(DATA_WIDTH-1):0] const_OneSix=16'b0011000101010110;
reg [(DATA_WIDTH-1):0] const_OneFifths=16'b0011001001100110;
reg [(DATA_WIDTH-1):0] const_OneQuarter=16'b0011010000000000;
reg [(DATA_WIDTH-1):0] const_OneThird=16'b0011010101010101;
reg [(DATA_WIDTH-1):0] const_Half=16'b0011100000000000;
reg [(DATA_WIDTH-1):0] const_One=16'b0011110000000000;

// adders input
reg [DATA_WIDTH-1:0] input_one;
reg [DATA_WIDTH-1:0] input_two;

wire [DATA_WIDTH-1:0] output_const;
reg [DATA_WIDTH-1:0] input_adder;


initial
begin
    i=0;
    done_exp=0;
end

// Calculating equation from inner bracket to the outer one using counters
// Clock cycles steps will be shown in the report
always@ (posedge clk)
begin
    if(reset_exp==0)
    begin
        if(i==0)
        begin
            input_one=const_OneSix;  
            input_two=input_exp;
        end
        else if(i%2==1)
        begin
            input_one=output_tmp_add;  
            input_two=input_exp;
        end
        else
        begin
            input_one=output_tmp_add;  
            if(i==2)
            begin
                 input_two=const_OneFifths;
            end
            else if(i==4)
            begin
                 input_two=const_OneQuarter;
            end
            else if(i==6)
            begin
                 input_two=const_OneThird;
            end
            else if(i==8)
            begin
                 input_two=const_Half;
            end
            else
            begin
            end
        end
    end
    else
    begin
    end 
end

always@ (negedge clk)
begin
    if(reset_exp==0)
    begin
                if(i==0 || i==9)
                begin
                     input_adder=const_One;  
                end
                else if(i%2==0)
                begin
                   input_adder=const_One;  
                end
                else
                   //input_adder=32'h00000000000000000000000000000000;
                   input_adder=16'h0000000000000000;
                begin
                end
                
                if(i!=10)
                begin
                  i=i+1;
                end
                else
                begin
                end
    end
    else
    begin
    end    
end

always@ (posedge done)
begin
    if (i==10)
    begin
        output_exp=output_tmp_add;
        i=0;
        done_exp=1;
    end
end

always@ (posedge reset_exp)
begin
        i=0;
        done_exp=0;
        input_one=0;
        input_two=0;
        input_adder=0;
end


fpMul #(.EXPONENT_WIDTH(EXPONENT_WIDTH), .MANTISSA_WIDTH(MANTISSA_WIDTH)) fmul(
.flp_a(input_one),
.flp_b(input_two),
.sign(output_tmp_mul[EXPONENT_WIDTH+MANTISSA_WIDTH]),
.exponent(output_tmp_mul[EXPONENT_WIDTH+MANTISSA_WIDTH-1:MANTISSA_WIDTH]),
.prod(output_tmp_mul[MANTISSA_WIDTH-1:0]),
.clk(clk)
);


fp_add #(.EXPONENT_WIDTH(EXPONENT_WIDTH), .MANTISSA_WIDTH(MANTISSA_WIDTH)) fadd(
.A_FP(input_adder),
.B_FP(output_tmp_mul),
.sign(output_tmp_add[EXPONENT_WIDTH+MANTISSA_WIDTH]),
.exponent(output_tmp_add[EXPONENT_WIDTH+MANTISSA_WIDTH-1:MANTISSA_WIDTH]),
.mantissa(output_tmp_add[MANTISSA_WIDTH-1:0]),
.clk(clk),
.done(done)
);
endmodule

// log helper + main modules

module LUT1(addr, log);
    input [7:0] addr;
    output reg [15:0] log;

    always @(addr) begin
        case (addr)
			8'b0		: log = 16'b1111110000000000;
			8'b1		: log = 16'b1100001010101110101;
			8'b10		: log = 16'b1100001010101101010;
			8'b11		: log = 16'b1100001010101011111;
			8'b100		: log = 16'b1100001010101010100;
			8'b101		: log = 16'b1100001010101001001;
			8'b110		: log = 16'b1100001010100111101;
			8'b111		: log = 16'b1100001010100110010;
			8'b1000		: log = 16'b1100001010100100111;
			8'b1001		: log = 16'b1100001010100011100;
			8'b1010		: log = 16'b1100001010100010001;
			8'b1011		: log = 16'b1100001010100000110;
			8'b1100		: log = 16'b1100001010011111011;
			8'b1101		: log = 16'b1100001010011110000;
			8'b1110		: log = 16'b1100001010011100101;
			8'b1111		: log = 16'b1100001010011011010;
			8'b10000		: log = 16'b1100001010011001111;
			8'b10001		: log = 16'b1100001010011000011;
			8'b10010		: log = 16'b1100001010010111000;
			8'b10011		: log = 16'b1100001010010101101;
			8'b10100		: log = 16'b1100001010010100010;
			8'b10101		: log = 16'b1100001010010010111;
			8'b10110		: log = 16'b1100001010010001100;
			8'b10111		: log = 16'b1100001010010000001;
			8'b11000		: log = 16'b1100001010001110110;
			8'b11001		: log = 16'b1100001010001101011;
			8'b11010		: log = 16'b1100001010001100000;
			8'b11011		: log = 16'b1100001010001010101;
			8'b11100		: log = 16'b1100001010001001001;
			8'b11101		: log = 16'b1100001010000111110;
			8'b11110		: log = 16'b1100001010000110011;
			8'b11111		: log = 16'b1100001010000101000;
			8'b100000		: log = 16'b1100001010000011101;
			8'b100001		: log = 16'b1100001010000010010;
			8'b100010		: log = 16'b1100001010000000111;
			8'b100011		: log = 16'b1100001001111111000;
			8'b100100		: log = 16'b1100001001111100010;
			8'b100101		: log = 16'b1100001001111001100;
			8'b100110		: log = 16'b1100001001110110110;
			8'b100111		: log = 16'b1100001001110011111;
			8'b101000		: log = 16'b1100001001110001001;
			8'b101001		: log = 16'b1100001001101110011;
			8'b101010		: log = 16'b1100001001101011101;
			8'b101011		: log = 16'b1100001001101000111;
			8'b101100		: log = 16'b1100001001100110000;
			8'b101101		: log = 16'b1100001001100011010;
			8'b101110		: log = 16'b1100001001100000100;
			8'b101111		: log = 16'b1100001001011101110;
			8'b110000		: log = 16'b1100001001011011000;
			8'b110001		: log = 16'b1100001001011000010;
			8'b110010		: log = 16'b1100001001010101011;
			8'b110011		: log = 16'b1100001001010010101;
			8'b110100		: log = 16'b1100001001001111111;
			8'b110101		: log = 16'b1100001001001101001;
			8'b110110		: log = 16'b1100001001001010011;
			8'b110111		: log = 16'b1100001001000111101;
			8'b111000		: log = 16'b1100001001000100110;
			8'b111001		: log = 16'b1100001001000010000;
			8'b111010		: log = 16'b1100001000111111010;
			8'b111011		: log = 16'b1100001000111100100;
			8'b111100		: log = 16'b1100001000111001110;
			8'b111101		: log = 16'b1100001000110110111;
			8'b111110		: log = 16'b1100001000110100001;
			8'b111111		: log = 16'b1100001000110001011;
			8'b1000000		: log = 16'b1100001000101110101;
			8'b1000001		: log = 16'b1100001000101011111;
			8'b1000010		: log = 16'b1100001000101001001;
			8'b1000011		: log = 16'b1100001000100110010;
			8'b1000100		: log = 16'b1100001000100011100;
			8'b1000101		: log = 16'b1100001000100000110;
			8'b1000110		: log = 16'b1100001000011110000;
			8'b1000111		: log = 16'b1100001000011011010;
			8'b1001000		: log = 16'b1100001000011000011;
			8'b1001001		: log = 16'b1100001000010101101;
			8'b1001010		: log = 16'b1100001000010010111;
			8'b1001011		: log = 16'b1100001000010000001;
			8'b1001100		: log = 16'b1100001000001101011;
			8'b1001101		: log = 16'b1100001000001010101;
			8'b1001110		: log = 16'b1100001000000111110;
			8'b1001111		: log = 16'b1100001000000101000;
			8'b1010000		: log = 16'b1100001000000010010;
			8'b1010001		: log = 16'b1100000111111111000;
			8'b1010010		: log = 16'b1100000111111001100;
			8'b1010011		: log = 16'b1100000111110011111;
			8'b1010100		: log = 16'b1100000111101110011;
			8'b1010101		: log = 16'b1100000111101000111;
			8'b1010110		: log = 16'b1100000111100011010;
			8'b1010111		: log = 16'b1100000111011101110;
			8'b1011000		: log = 16'b1100000111011000010;
			8'b1011001		: log = 16'b1100000111010010101;
			8'b1011010		: log = 16'b1100000111001101001;
			8'b1011011		: log = 16'b1100000111000111101;
			8'b1011100		: log = 16'b1100000111000010000;
			8'b1011101		: log = 16'b1100000110111100100;
			8'b1011110		: log = 16'b1100000110110110111;
			8'b1011111		: log = 16'b1100000110110001011;
			8'b1100000		: log = 16'b1100000110101011111;
			8'b1100001		: log = 16'b1100000110100110010;
			8'b1100010		: log = 16'b1100000110100000110;
			8'b1100011		: log = 16'b1100000110011011010;
			8'b1100100		: log = 16'b1100000110010101101;
			8'b1100101		: log = 16'b1100000110010000001;
			8'b1100110		: log = 16'b1100000110001010101;
			8'b1100111		: log = 16'b1100000110000101000;
			8'b1101000		: log = 16'b1100000101111111000;
			8'b1101001		: log = 16'b1100000101110011111;
			8'b1101010		: log = 16'b1100000101101000111;
			8'b1101011		: log = 16'b1100000101011101110;
			8'b1101100		: log = 16'b1100000101010010101;
			8'b1101101		: log = 16'b1100000101000111101;
			8'b1101110		: log = 16'b1100000100111100100;
			8'b1101111		: log = 16'b1100000100110001011;
			8'b1110000		: log = 16'b1100000100100110010;
			8'b1110001		: log = 16'b1100000100011011010;
			8'b1110010		: log = 16'b1100000100010000001;
			8'b1110011		: log = 16'b1100000100000101000;
			8'b1110100		: log = 16'b1100000011110011111;
			8'b1110101		: log = 16'b1100000011011101110;
			8'b1110110		: log = 16'b1100000011000111101;
			8'b1110111		: log = 16'b1100000010110001011;
			8'b1111000		: log = 16'b1100000010011011010;
			8'b1111001		: log = 16'b1100000010000101000;
			8'b1111010		: log = 16'b1100000001011101110;
			8'b1111011		: log = 16'b1100000000110001011;
			8'b1111100		: log = 16'b1100000000000101000;
			8'b1111101		: log = 16'b1011111110110001011;
			8'b1111110		: log = 16'b1011111100110001011;
			8'b1111111		: log = 16'b0000000000000000000;
			8'b10000000		: log = 16'b0011111100110001011;
			8'b10000001		: log = 16'b0011111110110001011;
			8'b10000010		: log = 16'b0100000000000101000;
			8'b10000011		: log = 16'b0100000000110001011;
			8'b10000100		: log = 16'b0100000001011101110;
			8'b10000101		: log = 16'b0100000010000101000;
			8'b10000110		: log = 16'b0100000010011011010;
			8'b10000111		: log = 16'b0100000010110001011;
			8'b10001000		: log = 16'b0100000011000111101;
			8'b10001001		: log = 16'b0100000011011101110;
			8'b10001010		: log = 16'b0100000011110011111;
			8'b10001011		: log = 16'b0100000100000101000;
			8'b10001100		: log = 16'b0100000100010000001;
			8'b10001101		: log = 16'b0100000100011011010;
			8'b10001110		: log = 16'b0100000100100110010;
			8'b10001111		: log = 16'b0100000100110001011;
			8'b10010000		: log = 16'b0100000100111100100;
			8'b10010001		: log = 16'b0100000101000111101;
			8'b10010010		: log = 16'b0100000101010010101;
			8'b10010011		: log = 16'b0100000101011101110;
			8'b10010100		: log = 16'b0100000101101000111;
			8'b10010101		: log = 16'b0100000101110011111;
			8'b10010110		: log = 16'b0100000101111111000;
			8'b10010111		: log = 16'b0100000110000101000;
			8'b10011000		: log = 16'b0100000110001010101;
			8'b10011001		: log = 16'b0100000110010000001;
			8'b10011010		: log = 16'b0100000110010101101;
			8'b10011011		: log = 16'b0100000110011011010;
			8'b10011100		: log = 16'b0100000110100000110;
			8'b10011101		: log = 16'b0100000110100110010;
			8'b10011110		: log = 16'b0100000110101011111;
			8'b10011111		: log = 16'b0100000110110001011;
			8'b10100000		: log = 16'b0100000110110110111;
			8'b10100001		: log = 16'b0100000110111100100;
			8'b10100010		: log = 16'b0100000111000010000;
			8'b10100011		: log = 16'b0100000111000111101;
			8'b10100100		: log = 16'b0100000111001101001;
			8'b10100101		: log = 16'b0100000111010010101;
			8'b10100110		: log = 16'b0100000111011000010;
			8'b10100111		: log = 16'b0100000111011101110;
			8'b10101000		: log = 16'b0100000111100011010;
			8'b10101001		: log = 16'b0100000111101000111;
			8'b10101010		: log = 16'b0100000111101110011;
			8'b10101011		: log = 16'b0100000111110011111;
			8'b10101100		: log = 16'b0100000111111001100;
			8'b10101101		: log = 16'b0100000111111111000;
			8'b10101110		: log = 16'b0100001000000010010;
			8'b10101111		: log = 16'b0100001000000101000;
			8'b10110000		: log = 16'b0100001000000111110;
			8'b10110001		: log = 16'b0100001000001010101;
			8'b10110010		: log = 16'b0100001000001101011;
			8'b10110011		: log = 16'b0100001000010000001;
			8'b10110100		: log = 16'b0100001000010010111;
			8'b10110101		: log = 16'b0100001000010101101;
			8'b10110110		: log = 16'b0100001000011000011;
			8'b10110111		: log = 16'b0100001000011011010;
			8'b10111000		: log = 16'b0100001000011110000;
			8'b10111001		: log = 16'b0100001000100000110;
			8'b10111010		: log = 16'b0100001000100011100;
			8'b10111011		: log = 16'b0100001000100110010;
			8'b10111100		: log = 16'b0100001000101001001;
			8'b10111101		: log = 16'b0100001000101011111;
			8'b10111110		: log = 16'b0100001000101110101;
			8'b10111111		: log = 16'b0100001000110001011;
			8'b11000000		: log = 16'b0100001000110100001;
			8'b11000001		: log = 16'b0100001000110110111;
			8'b11000010		: log = 16'b0100001000111001110;
			8'b11000011		: log = 16'b0100001000111100100;
			8'b11000100		: log = 16'b0100001000111111010;
			8'b11000101		: log = 16'b0100001001000010000;
			8'b11000110		: log = 16'b0100001001000100110;
			8'b11000111		: log = 16'b0100001001000111101;
			8'b11001000		: log = 16'b0100001001001010011;
			8'b11001001		: log = 16'b0100001001001101001;
			8'b11001010		: log = 16'b0100001001001111111;
			8'b11001011		: log = 16'b0100001001010010101;
			8'b11001100		: log = 16'b0100001001010101011;
			8'b11001101		: log = 16'b0100001001011000010;
			8'b11001110		: log = 16'b0100001001011011000;
			8'b11001111		: log = 16'b0100001001011101110;
			8'b11010000		: log = 16'b0100001001100000100;
			8'b11010001		: log = 16'b0100001001100011010;
			8'b11010010		: log = 16'b0100001001100110000;
			8'b11010011		: log = 16'b0100001001101000111;
			8'b11010100		: log = 16'b0100001001101011101;
			8'b11010101		: log = 16'b0100001001101110011;
			8'b11010110		: log = 16'b0100001001110001001;
			8'b11010111		: log = 16'b0100001001110011111;
			8'b11011000		: log = 16'b0100001001110110110;
			8'b11011001		: log = 16'b0100001001111001100;
			8'b11011010		: log = 16'b0100001001111100010;
			8'b11011011		: log = 16'b0100001001111111000;
			8'b11011100		: log = 16'b0100001010000000111;
			8'b11011101		: log = 16'b0100001010000010010;
			8'b11011110		: log = 16'b0100001010000011101;
			8'b11011111		: log = 16'b0100001010000101000;
			8'b11100000		: log = 16'b0100001010000110011;
			8'b11100001		: log = 16'b0100001010000111110;
			8'b11100010		: log = 16'b0100001010001001001;
			8'b11100011		: log = 16'b0100001010001010101;
			8'b11100100		: log = 16'b0100001010001100000;
			8'b11100101		: log = 16'b0100001010001101011;
			8'b11100110		: log = 16'b0100001010001110110;
			8'b11100111		: log = 16'b0100001010010000001;
			8'b11101000		: log = 16'b0100001010010001100;
			8'b11101001		: log = 16'b0100001010010010111;
			8'b11101010		: log = 16'b0100001010010100010;
			8'b11101011		: log = 16'b0100001010010101101;
			8'b11101100		: log = 16'b0100001010010111000;
			8'b11101101		: log = 16'b0100001010011000011;
			8'b11101110		: log = 16'b0100001010011001111;
			8'b11101111		: log = 16'b0100001010011011010;
			8'b11110000		: log = 16'b0100001010011100101;
			8'b11110001		: log = 16'b0100001010011110000;
			8'b11110010		: log = 16'b0100001010011111011;
			8'b11110011		: log = 16'b0100001010100000110;
			8'b11110100		: log = 16'b0100001010100010001;
			8'b11110101		: log = 16'b0100001010100011100;
			8'b11110110		: log = 16'b0100001010100100111;
			8'b11110111		: log = 16'b0100001010100110010;
			8'b11111000		: log = 16'b0100001010100111101;
			8'b11111001		: log = 16'b0100001010101001001;
			8'b11111010		: log = 16'b0100001010101010100;
			8'b11111011		: log = 16'b0100001010101011111;
			8'b11111100		: log = 16'b0100001010101101010;
			8'b11111101		: log = 16'b0100001010101110101;
			8'b11111110		: log = 16'b0100001010110000000;
			8'b11111111		: log = 16'b0111110000000000;
        endcase
    end
endmodule

module LUT2(addr, log);
    input [7:0] addr;
    output reg [15:0] log;

    always @(addr) begin
        case (addr)
			8'b0		: log = 16'b0000000000000000000;
			8'b1		: log = 16'b0011101101111111100;
			8'b10		: log = 16'b0011101111111111000;
			8'b11		: log = 16'b0011110000111110111;
			8'b100		: log = 16'b0011110001111110000;
			8'b101		: log = 16'b0011110010011110011;
			8'b110		: log = 16'b0011110010111101110;
			8'b111		: log = 16'b0011110011011100111;
			8'b1000		: log = 16'b0011110011111100000;
			8'b1001		: log = 16'b0011110100001101100;
			8'b1010		: log = 16'b0011110100011100111;
			8'b1011		: log = 16'b0011110100101100010;
			8'b1100		: log = 16'b0011110100111011101;
			8'b1101		: log = 16'b0011110101001010111;
			8'b1110		: log = 16'b0011110101011010000;
			8'b1111		: log = 16'b0011110101101001001;
			8'b10000		: log = 16'b0011110101111000010;
			8'b10001		: log = 16'b0011110110000011101;
			8'b10010		: log = 16'b0011110110001011001;
			8'b10011		: log = 16'b0011110110010010100;
			8'b10100		: log = 16'b0011110110011010000;
			8'b10101		: log = 16'b0011110110100001011;
			8'b10110		: log = 16'b0011110110101000110;
			8'b10111		: log = 16'b0011110110110000001;
			8'b11000		: log = 16'b0011110110110111100;
			8'b11001		: log = 16'b0011110110111110110;
			8'b11010		: log = 16'b0011110111000110000;
			8'b11011		: log = 16'b0011110111001101010;
			8'b11100		: log = 16'b0011110111010100100;
			8'b11101		: log = 16'b0011110111011011110;
			8'b11110		: log = 16'b0011110111100010111;
			8'b11111		: log = 16'b0011110111101010000;
			8'b100000		: log = 16'b0011110111110001001;
			8'b100001		: log = 16'b0011110111111000010;
			8'b100010		: log = 16'b0011110111111111011;
			8'b100011		: log = 16'b0011111000000011001;
			8'b100100		: log = 16'b0011111000000110101;
			8'b100101		: log = 16'b0011111000001010001;
			8'b100110		: log = 16'b0011111000001101101;
			8'b100111		: log = 16'b0011111000010001001;
			8'b101000		: log = 16'b0011111000010100101;
			8'b101001		: log = 16'b0011111000011000000;
			8'b101010		: log = 16'b0011111000011011100;
			8'b101011		: log = 16'b0011111000011110111;
			8'b101100		: log = 16'b0011111000100010011;
			8'b101101		: log = 16'b0011111000100101110;
			8'b101110		: log = 16'b0011111000101001001;
			8'b101111		: log = 16'b0011111000101100100;
			8'b110000		: log = 16'b0011111000101111111;
			8'b110001		: log = 16'b0011111000110011010;
			8'b110010		: log = 16'b0011111000110110101;
			8'b110011		: log = 16'b0011111000111010000;
			8'b110100		: log = 16'b0011111000111101010;
			8'b110101		: log = 16'b0011111001000000101;
			8'b110110		: log = 16'b0011111001000011111;
			8'b110111		: log = 16'b0011111001000111010;
			8'b111000		: log = 16'b0011111001001010100;
			8'b111001		: log = 16'b0011111001001101110;
			8'b111010		: log = 16'b0011111001010001000;
			8'b111011		: log = 16'b0011111001010100010;
			8'b111100		: log = 16'b0011111001010111100;
			8'b111101		: log = 16'b0011111001011010110;
			8'b111110		: log = 16'b0011111001011110000;
			8'b111111		: log = 16'b0011111001100001010;
			8'b1000000		: log = 16'b0011111001100100011;
			8'b1000001		: log = 16'b0011111001100111101;
			8'b1000010		: log = 16'b0011111001101010111;
			8'b1000011		: log = 16'b0011111001101110000;
			8'b1000100		: log = 16'b0011111001110001001;
			8'b1000101		: log = 16'b0011111001110100011;
			8'b1000110		: log = 16'b0011111001110111100;
			8'b1000111		: log = 16'b0011111001111010101;
			8'b1001000		: log = 16'b0011111001111101110;
			8'b1001001		: log = 16'b0011111010000000011;
			8'b1001010		: log = 16'b0011111010000010000;
			8'b1001011		: log = 16'b0011111010000011100;
			8'b1001100		: log = 16'b0011111010000101000;
			8'b1001101		: log = 16'b0011111010000110101;
			8'b1001110		: log = 16'b0011111010001000001;
			8'b1001111		: log = 16'b0011111010001001101;
			8'b1010000		: log = 16'b0011111010001011001;
			8'b1010001		: log = 16'b0011111010001100110;
			8'b1010010		: log = 16'b0011111010001110010;
			8'b1010011		: log = 16'b0011111010001111110;
			8'b1010100		: log = 16'b0011111010010001010;
			8'b1010101		: log = 16'b0011111010010010110;
			8'b1010110		: log = 16'b0011111010010100010;
			8'b1010111		: log = 16'b0011111010010101110;
			8'b1011000		: log = 16'b0011111010010111010;
			8'b1011001		: log = 16'b0011111010011000110;
			8'b1011010		: log = 16'b0011111010011010001;
			8'b1011011		: log = 16'b0011111010011011101;
			8'b1011100		: log = 16'b0011111010011101001;
			8'b1011101		: log = 16'b0011111010011110101;
			8'b1011110		: log = 16'b0011111010100000001;
			8'b1011111		: log = 16'b0011111010100001100;
			8'b1100000		: log = 16'b0011111010100011000;
			8'b1100001		: log = 16'b0011111010100100100;
			8'b1100010		: log = 16'b0011111010100101111;
			8'b1100011		: log = 16'b0011111010100111011;
			8'b1100100		: log = 16'b0011111010101000110;
			8'b1100101		: log = 16'b0011111010101010010;
			8'b1100110		: log = 16'b0011111010101011101;
			8'b1100111		: log = 16'b0011111010101101001;
			8'b1101000		: log = 16'b0011111010101110100;
			8'b1101001		: log = 16'b0011111010101111111;
			8'b1101010		: log = 16'b0011111010110001011;
			8'b1101011		: log = 16'b0011111010110010110;
			8'b1101100		: log = 16'b0011111010110100001;
			8'b1101101		: log = 16'b0011111010110101100;
			8'b1101110		: log = 16'b0011111010110111000;
			8'b1101111		: log = 16'b0011111010111000011;
			8'b1110000		: log = 16'b0011111010111001110;
			8'b1110001		: log = 16'b0011111010111011001;
			8'b1110010		: log = 16'b0011111010111100100;
			8'b1110011		: log = 16'b0011111010111101111;
			8'b1110100		: log = 16'b0011111010111111010;
			8'b1110101		: log = 16'b0011111011000000101;
			8'b1110110		: log = 16'b0011111011000010000;
			8'b1110111		: log = 16'b0011111011000011011;
			8'b1111000		: log = 16'b0011111011000100110;
			8'b1111001		: log = 16'b0011111011000110001;
			8'b1111010		: log = 16'b0011111011000111100;
			8'b1111011		: log = 16'b0011111011001000111;
			8'b1111100		: log = 16'b0011111011001010001;
			8'b1111101		: log = 16'b0011111011001011100;
			8'b1111110		: log = 16'b0011111011001100111;
			8'b1111111		: log = 16'b0011111011001110010;
			8'b10000000		: log = 16'b0011111011001111100;
			8'b10000001		: log = 16'b0011111011010000111;
			8'b10000010		: log = 16'b0011111011010010010;
			8'b10000011		: log = 16'b0011111011010011100;
			8'b10000100		: log = 16'b0011111011010100111;
			8'b10000101		: log = 16'b0011111011010110001;
			8'b10000110		: log = 16'b0011111011010111100;
			8'b10000111		: log = 16'b0011111011011000110;
			8'b10001000		: log = 16'b0011111011011010001;
			8'b10001001		: log = 16'b0011111011011011011;
			8'b10001010		: log = 16'b0011111011011100110;
			8'b10001011		: log = 16'b0011111011011110000;
			8'b10001100		: log = 16'b0011111011011111010;
			8'b10001101		: log = 16'b0011111011100000101;
			8'b10001110		: log = 16'b0011111011100001111;
			8'b10001111		: log = 16'b0011111011100011001;
			8'b10010000		: log = 16'b0011111011100100011;
			8'b10010001		: log = 16'b0011111011100101110;
			8'b10010010		: log = 16'b0011111011100111000;
			8'b10010011		: log = 16'b0011111011101000010;
			8'b10010100		: log = 16'b0011111011101001100;
			8'b10010101		: log = 16'b0011111011101010110;
			8'b10010110		: log = 16'b0011111011101100000;
			8'b10010111		: log = 16'b0011111011101101011;
			8'b10011000		: log = 16'b0011111011101110101;
			8'b10011001		: log = 16'b0011111011101111111;
			8'b10011010		: log = 16'b0011111011110001001;
			8'b10011011		: log = 16'b0011111011110010011;
			8'b10011100		: log = 16'b0011111011110011101;
			8'b10011101		: log = 16'b0011111011110100110;
			8'b10011110		: log = 16'b0011111011110110000;
			8'b10011111		: log = 16'b0011111011110111010;
			8'b10100000		: log = 16'b0011111011111000100;
			8'b10100001		: log = 16'b0011111011111001110;
			8'b10100010		: log = 16'b0011111011111011000;
			8'b10100011		: log = 16'b0011111011111100010;
			8'b10100100		: log = 16'b0011111011111101011;
			8'b10100101		: log = 16'b0011111011111110101;
			8'b10100110		: log = 16'b0011111011111111111;
			8'b10100111		: log = 16'b0011111100000000100;
			8'b10101000		: log = 16'b0011111100000001001;
			8'b10101001		: log = 16'b0011111100000001110;
			8'b10101010		: log = 16'b0011111100000010010;
			8'b10101011		: log = 16'b0011111100000010111;
			8'b10101100		: log = 16'b0011111100000011100;
			8'b10101101		: log = 16'b0011111100000100001;
			8'b10101110		: log = 16'b0011111100000100110;
			8'b10101111		: log = 16'b0011111100000101010;
			8'b10110000		: log = 16'b0011111100000101111;
			8'b10110001		: log = 16'b0011111100000110100;
			8'b10110010		: log = 16'b0011111100000111001;
			8'b10110011		: log = 16'b0011111100000111101;
			8'b10110100		: log = 16'b0011111100001000010;
			8'b10110101		: log = 16'b0011111100001000111;
			8'b10110110		: log = 16'b0011111100001001011;
			8'b10110111		: log = 16'b0011111100001010000;
			8'b10111000		: log = 16'b0011111100001010101;
			8'b10111001		: log = 16'b0011111100001011001;
			8'b10111010		: log = 16'b0011111100001011110;
			8'b10111011		: log = 16'b0011111100001100011;
			8'b10111100		: log = 16'b0011111100001100111;
			8'b10111101		: log = 16'b0011111100001101100;
			8'b10111110		: log = 16'b0011111100001110000;
			8'b10111111		: log = 16'b0011111100001110101;
			8'b11000000		: log = 16'b0011111100001111010;
			8'b11000001		: log = 16'b0011111100001111110;
			8'b11000010		: log = 16'b0011111100010000011;
			8'b11000011		: log = 16'b0011111100010000111;
			8'b11000100		: log = 16'b0011111100010001100;
			8'b11000101		: log = 16'b0011111100010010000;
			8'b11000110		: log = 16'b0011111100010010101;
			8'b11000111		: log = 16'b0011111100010011001;
			8'b11001000		: log = 16'b0011111100010011110;
			8'b11001001		: log = 16'b0011111100010100010;
			8'b11001010		: log = 16'b0011111100010100111;
			8'b11001011		: log = 16'b0011111100010101011;
			8'b11001100		: log = 16'b0011111100010110000;
			8'b11001101		: log = 16'b0011111100010110100;
			8'b11001110		: log = 16'b0011111100010111001;
			8'b11001111		: log = 16'b0011111100010111101;
			8'b11010000		: log = 16'b0011111100011000001;
			8'b11010001		: log = 16'b0011111100011000110;
			8'b11010010		: log = 16'b0011111100011001010;
			8'b11010011		: log = 16'b0011111100011001111;
			8'b11010100		: log = 16'b0011111100011010011;
			8'b11010101		: log = 16'b0011111100011010111;
			8'b11010110		: log = 16'b0011111100011011100;
			8'b11010111		: log = 16'b0011111100011100000;
			8'b11011000		: log = 16'b0011111100011100100;
			8'b11011001		: log = 16'b0011111100011101001;
			8'b11011010		: log = 16'b0011111100011101101;
			8'b11011011		: log = 16'b0011111100011110001;
			8'b11011100		: log = 16'b0011111100011110110;
			8'b11011101		: log = 16'b0011111100011111010;
			8'b11011110		: log = 16'b0011111100011111110;
			8'b11011111		: log = 16'b0011111100100000011;
			8'b11100000		: log = 16'b0011111100100000111;
			8'b11100001		: log = 16'b0011111100100001011;
			8'b11100010		: log = 16'b0011111100100001111;
			8'b11100011		: log = 16'b0011111100100010100;
			8'b11100100		: log = 16'b0011111100100011000;
			8'b11100101		: log = 16'b0011111100100011100;
			8'b11100110		: log = 16'b0011111100100100000;
			8'b11100111		: log = 16'b0011111100100100101;
			8'b11101000		: log = 16'b0011111100100101001;
			8'b11101001		: log = 16'b0011111100100101101;
			8'b11101010		: log = 16'b0011111100100110001;
			8'b11101011		: log = 16'b0011111100100110101;
			8'b11101100		: log = 16'b0011111100100111001;
			8'b11101101		: log = 16'b0011111100100111110;
			8'b11101110		: log = 16'b0011111100101000010;
			8'b11101111		: log = 16'b0011111100101000110;
			8'b11110000		: log = 16'b0011111100101001010;
			8'b11110001		: log = 16'b0011111100101001110;
			8'b11110010		: log = 16'b0011111100101010010;
			8'b11110011		: log = 16'b0011111100101010110;
			8'b11110100		: log = 16'b0011111100101011010;
			8'b11110101		: log = 16'b0011111100101011111;
			8'b11110110		: log = 16'b0011111100101100011;
			8'b11110111		: log = 16'b0011111100101100111;
			8'b11111000		: log = 16'b0011111100101101011;
			8'b11111001		: log = 16'b0011111100101101111;
			8'b11111010		: log = 16'b0011111100101110011;
			8'b11111011		: log = 16'b0011111100101110111;
			8'b11111100		: log = 16'b0011111100101111011;
			8'b11111101		: log = 16'b0011111100101111111;
			8'b11111110		: log = 16'b0011111100110000011;
			8'b11111111		: log = 16'b0011111100110000111;
        endcase
    end
endmodule

`timescale 1ns / 1ps


module logunit (fpin, fpout); // clk, rst


	input [15:0] fpin;
	output [15:0] fpout;

	//input clk,rst;


	wire [15: 0] fxout1;
	wire [15: 0] fxout2;

	// reg [15: 0] pipe1;
	// reg [15: 0] pipe2;

	LUT1 lut1 (.addr(fpin[14:10]),.log(fxout1)); // LUT for exponent

	LUT2 lut2 (.addr(fpin[9:2]),.log(fxout2));  // LUT for mantissa

	DW_fp_addsub add(.a(fxout1), .b(fxout2), .rnd(3'b0), .op(1'b0), .z(fpout), .status());

// ignoring pipelining in the module

// always @(posedge clk or negedge rst)
// begin
// 	if (!rst) begin
// 		pipe1 <= 0;
// 		pipe2 <= 0;
// 	end
// 	else begin
// 		pipe1 <= fxout1;
// 		pipe2 <= fxout2;
// 	end
// end
endmodule

// top module for fp exp - computes a^b (= e^(b*ln(a)))
module fp_exp (a, b, clk, out);     
    parameter EXPONENT_WIDTH = 5;
    parameter MANTISSA_WIDTH = 10;
    localparam FloatBitWidth = EXPONENT_WIDTH + MANTISSA_WIDTH + 1;

    input [FloatBitWidth-1:0] a;
	input clk;
	input [FloatBitWidth-1:0] b;
	output reg [FloatBitWidth-1:0] out;
    
    wire [FloatBitWidth-1:0] b_ln_a;
	

	wire [FloatBitWidth-1:0] ln_a;

	// logunit for ln(a)
	logunit log_a_inst (
		.fpin(a),
		.fpout(ln_a)
	);

    // fpMul for b * ln(a)
    fpMul #(.EXPONENT_WIDTH(EXPONENT_WIDTH), .MANTISSA_WIDTH(MANTISSA_WIDTH)) mul_b_ln_a_inst (
        .flp_a(b),
        .flp_b(ln_a),
        .sign(),
        .exponent(),
        .prod(b_ln_a),
        .clk(clk)
    );

    wire [FloatBitWidth-1:0] exp_out;
    wire done_exp;
    wire reset_exp = 1'b0; // connect actual reset if needed

    // exponential for e^(b*ln(a))
    exponential #(.EXPONENT_WIDTH(EXPONENT_WIDTH), .MANTISSA_WIDTH(MANTISSA_WIDTH)) exp_inst (
        .input_exp(b_ln_a),
        .clk(clk),
        .output_exp(exp_out),
        .done_exp(done_exp),
        .reset_exp(reset_exp)
    );

    assign out = exp_out; 

endmodule