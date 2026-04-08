// BUG: Resets to 1 instead of 0
module counter_4bit (
    input clk,
    input reset,
    input enable,
    output reg [3:0] count
);
    always @(posedge clk) begin
        if (reset)
            count <= 4'b0001;
        else if (enable)
            count <= count + 1;
    end
endmodule
