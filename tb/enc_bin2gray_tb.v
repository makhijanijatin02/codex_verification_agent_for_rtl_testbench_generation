`timescale 1ns/1ps

module tb;
    reg [9:0] bin;
    wire [9:0] gray;

    integer errors;
    integer test_num;
    integer idx;
    reg [9:0] rand_val;

    enc_bin2gray dut (
        .bin(bin),
        .gray(gray)
    );

    function [9:0] expected_gray;
        input [9:0] value;
        begin
            expected_gray = value ^ (value >> 1);
        end
    endfunction

    task automatic do_check;
        input [9:0] exp;
        input [8*32-1:0] tag;
        input [8*16-1:0] phase;
        begin
            test_num = test_num + 1;
            if (gray !== exp) begin
                errors = errors + 1;
                $display("FAIL (%0s @%0s) Test %0d: bin=%010b expected=%010b got=%010b time=%0t",
                         tag, phase, test_num, bin, exp, gray, $time);
            end
        end
    endtask

    task automatic apply_and_check;
        input [9:0] value;
        input [8*32-1:0] tag;
        reg [9:0] exp;
        begin
            bin = value;
            exp = expected_gray(value);
            #0;
            do_check(exp, tag, "delta");
            #1;
            do_check(exp, tag, "settle");
        end
    endtask

    initial begin
        errors = 0;
        test_num = 0;
        bin = 10'b0;
        #1;

        // Reset/power-up behavior
        apply_and_check(10'b0000000000, "power_up_zero");

        // Boundary extremes
        apply_and_check(10'b0000000000, "boundary_zero");
        apply_and_check(10'b1111111111, "boundary_all_ones");

        // Alternating-bit patterns
        apply_and_check(10'b1010101010, "alternating_A");
        apply_and_check(10'b0101010101, "alternating_B");

        // Single-bit walks
        apply_and_check(10'b1000000000, "walk_bit9");
        apply_and_check(10'b0100000000, "walk_bit8");
        apply_and_check(10'b0010000000, "walk_bit7");
        apply_and_check(10'b0001000000, "walk_bit6");
        apply_and_check(10'b0000100000, "walk_bit5");
        apply_and_check(10'b0000010000, "walk_bit4");
        apply_and_check(10'b0000001000, "walk_bit3");
        apply_and_check(10'b0000000100, "walk_bit2");
        apply_and_check(10'b0000000010, "walk_bit1");
        apply_and_check(10'b0000000001, "walk_bit0");

        // Basic incremental sweep
        apply_and_check(10'b0000000000, "increment_0");
        apply_and_check(10'b0000000001, "increment_1");
        apply_and_check(10'b0000000010, "increment_2");
        apply_and_check(10'b0000000011, "increment_3");
        apply_and_check(10'b0000000100, "increment_4");
        apply_and_check(10'b0000011111, "increment_31");

        // Glitch-hunting transition sequence
        apply_and_check(10'h155, "transition_155");
        apply_and_check(10'h2AA, "transition_2AA");
        apply_and_check(10'h3FF, "transition_3FF");
        apply_and_check(10'h000, "transition_000");

        // Randomized vectors
        for (idx = 0; idx < 200; idx = idx + 1) begin
            rand_val = $random;
            apply_and_check(rand_val, "random");
        end

        // Exhaustive sweep over all 10-bit values
        for (idx = 0; idx < 1024; idx = idx + 1) begin
            apply_and_check(idx[9:0], "exhaustive");
        end

        if (errors == 0)
            $display("PASS");
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule