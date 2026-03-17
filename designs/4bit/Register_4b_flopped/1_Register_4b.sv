`default_nettype none

module Register_4b (
    input wire [3:0] D,
    input wire reset, 
    input wire clk,         
    output reg [3:0] Q
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
