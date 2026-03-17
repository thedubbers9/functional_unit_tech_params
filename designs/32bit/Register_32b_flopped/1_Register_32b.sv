`default_nettype none

module Register_32b (
    input wire [31:0] D,
    input wire reset, 
    input wire clk,         
    output reg [31:0] Q
);

    always_ff @(posedge clk) begin
        if (reset) begin
            Q <= '0;
        end else begin
            Q <= D;
        end
    end

endmodule

`default_nettype wire
