`timescale 1ns/1ps

module tb;
    reg clk;
    reg rst;
    reg in_valid;
    reg [3:0] in;
    wire [14:0] out;

    integer errors;
    integer test_num;
    integer i;
    reg [31:0] rand_word;

    enc_bin2onehot dut (
        .clk(clk),
        .rst(rst),
        .in_valid(in_valid),
        .in(in),
        .out(out)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function [14:0] expected_onehot;
        input [3:0] value;
        begin
            expected_onehot = 15'b0;
            if (value < 4'd15)
                expected_onehot[value] = 1'b1;
        end
    endfunction

    function integer count_ones;
        input [14:0] value;
        integer idx;
        begin
            count_ones = 0;
            for (idx = 0; idx < 15; idx = idx + 1)
                count_ones = count_ones + value[idx];
        end
    endfunction

    task check_exact;
        input [14:0] expected;
        begin
            test_num = test_num + 1;
            if (out !== expected) begin
                $display("FAIL: Test %0d time=%0t in_valid=%0b in=%0d expected=%015b got=%015b", test_num, $time, in_valid, in, expected, out);
                errors = errors + 1;
            end
        end
    endtask

    task check_onehot_or_zero;
        integer ones;
        begin
            test_num = test_num + 1;
            if (^out === 1'bx) begin
                $display("FAIL: Test %0d time=%0t invalid output contains X/Z: %015b", test_num, $time, out);
                errors = errors + 1;
            end else begin
                ones = count_ones(out);
                if (ones > 1) begin
                    $display("FAIL: Test %0d time=%0t invalid input drove %0d hot bits: %015b", test_num, $time, ones, out);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        errors = 0;
        test_num = 0;
        rst = 1'b1;
        in_valid = 1'b0;
        in = 4'b0000;

        repeat (3) @(negedge clk);
        rst = 1'b0;

        @(negedge clk);
        #1 check_exact(15'b0);

        for (i = 0; i < 15; i = i + 1) begin
            @(negedge clk);
            in_valid = 1'b0;
            in = i[3:0];
            #1 check_exact(15'b0);
        end

        rst = 1'b1;
        @(negedge clk);
        in_valid = 1'b1;
        in = 4'd5;
        #1 check_exact(expected_onehot(in));
        rst = 1'b0;

        @(negedge clk);
        rst = 1'b1;
        in_valid = 1'b0;
        in = 4'd9;
        #1 check_exact(15'b0);
        @(negedge clk);
        rst = 1'b0;
        in_valid = 1'b1;
        #1 check_exact(expected_onehot(in));

        for (i = 0; i < 15; i = i + 1) begin
            @(negedge clk);
            in_valid = 1'b1;
            in = i[3:0];
            #1 check_exact(expected_onehot(in));
        end

        @(negedge clk);
        in_valid = 1'b1;
        in = 4'd0;
        #1 check_exact(expected_onehot(in));
        @(negedge clk);
        in = 4'd10;
        #1 check_exact(expected_onehot(in));

        for (i = 0; i < 16; i = i + 1) begin
            @(negedge clk);
            in = (i + 3) & 4'hF;
            in_valid = i[0];
            #1;
            if (in_valid)
                check_exact(expected_onehot(in));
            else
                check_exact(15'b0);
        end

        @(negedge clk);
        in_valid = 1'b1;
        in = 4'd15;
        #1 check_onehot_or_zero();

        @(negedge clk);
        in_valid = 1'b0;
        in = 4'd7;
        #1 check_exact(15'b0);

        @(negedge clk);
        in_valid = 1'b1;
        #1 check_exact(expected_onehot(in));

        rst = 1'b1;
        @(negedge clk);
        in_valid = 1'b1;
        in = 4'd2;
        #1 check_exact(expected_onehot(in));
        rst = 1'b0;
        @(negedge clk);
        in_valid = 1'b0;
        in = 4'd11;
        #1 check_exact(15'b0);

        for (i = 0; i < 200; i = i + 1) begin
            @(negedge clk);
            rand_word = $random;
            in = rand_word[3:0];
            if (rand_word[7:4] == 4'hF)
                in = 4'd15;
            in_valid = ((rand_word & 8'hFF) < 8'd153);
            #1;
            if (in_valid && in < 4'd15)
                check_exact(expected_onehot(in));
            else if (!in_valid)
                check_exact(15'b0);
            else
                check_onehot_or_zero();
        end

        if (errors == 0)
            $display("PASS");
        else
            $display("FAIL (%0d errors)", errors);
        $finish;
    end
endmodule