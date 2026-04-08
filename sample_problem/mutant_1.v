// BUG: enable has priority over reset (wrong priority)
module counter_4bit (
    input clk,
    input reset,
    input enable,
    output reg [3:0] count
);
    always @(posedge clk) begin
        if (enable)
            count <= count + 1;
        else if (reset)
            count <= 4'b0000;
    end
endmodule
