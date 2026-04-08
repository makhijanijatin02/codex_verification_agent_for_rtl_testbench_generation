`timescale 1ns/1ps

module tb;
    reg clk;
    reg reset;
    reg enable;
    wire [3:0] count;

    integer errors;
    integer test_num;
    reg [3:0] exp_count;
    integer i;
    reg [31:0] rand_val;

    counter_4bit dut (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .count(count)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task drive_and_check;
        input rst;
        input en;
        reg [3:0] next_exp;
        begin
            reset = rst;
            enable = en;
            @(posedge clk);
            if (rst)
                next_exp = 4'd0;
            else if (en)
                next_exp = (exp_count + 4'd1) & 4'hF;
            else
                next_exp = exp_count;
            exp_count = next_exp;
            #1;
            test_num = test_num + 1;
            if (count !== exp_count) begin
                errors = errors + 1;
                $display("FAIL: Test %0d at time %0t reset=%0b enable=%0b expected=%0h got=%0h",
                         test_num, $time, rst, en, exp_count, count);
            end
        end
    endtask

    initial begin
        errors = 0;
        test_num = 0;
        exp_count = 4'd0;
        reset = 0;
        enable = 0;

        // Synchronous reset behavior
        drive_and_check(1'b1, 1'b0);
        drive_and_check(1'b1, 1'b1); // reset must dominate enable
        drive_and_check(1'b0, 1'b0); // release reset, hold at zero
        drive_and_check(1'b0, 1'b0); // hold again

        // Increment while enabled
        drive_and_check(1'b0, 1'b1);
        drive_and_check(1'b0, 1'b1);
        drive_and_check(1'b0, 1'b0); // hold after increment

        // Force wrap-around with sustained enable
        for (i = 0; i < 20; i = i + 1) begin
            drive_and_check(1'b0, 1'b1);
        end

        // Hold checks around wrap region
        drive_and_check(1'b0, 1'b0);
        drive_and_check(1'b0, 1'b0);

        // Reset and enable asserted together
        drive_and_check(1'b1, 1'b1);
        drive_and_check(1'b0, 1'b1);
        drive_and_check(1'b0, 1'b0);

        // Pseudo-random stress
        for (i = 0; i < 30; i = i + 1) begin
            rand_val = $random;
            drive_and_check((rand_val[1:0] == 2'b00), rand_val[2]);
        end

        if (errors == 0)
            $display("PASS");
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end


    // Injected guard: synchronous reset must not change registered outputs
    // until the next active clock edge.
    reg [3:0] tb_sync_reset_snapshot;
    time tb_sync_reset_last_clock_edge;

    initial tb_sync_reset_last_clock_edge = 0;

    always @(posedge clk) begin
        tb_sync_reset_last_clock_edge = $time;
    end

    always @(posedge reset) begin
        if (($time - tb_sync_reset_last_clock_edge) > 0) begin
            tb_sync_reset_snapshot = count;
            #1;
            if (count !== tb_sync_reset_snapshot) begin
                $display("FAIL: synchronous reset changed registered outputs before clock edge at %0t", $time);
                $finish;
            end
        end
    end

endmodule