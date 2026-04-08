`timescale 1ns/1ps

module tb;
    localparam integer NUM_SYMBOLS = 10;
    localparam integer SYMBOL_W    = 5;
    localparam integer TOTAL_W     = NUM_SYMBOLS * SYMBOL_W;

    reg  [TOTAL_W-1:0] in;
    reg  [2:0]         shift;
    reg  [SYMBOL_W-1:0] fill;
    wire               out_valid;
    wire [TOTAL_W-1:0] out;

    integer errors = 0;
    integer test_num = 0;

    shift_right dut (
        .out_valid(out_valid),
        .in(in),
        .shift(shift),
        .fill(fill),
        .out(out)
    );

    function [TOTAL_W-1:0] pack_syms;
        input integer ms9;
        input integer ms8;
        input integer ms7;
        input integer ms6;
        input integer ms5;
        input integer ms4;
        input integer ms3;
        input integer ms2;
        input integer ms1;
        input integer ls0;
    begin
        pack_syms = {
            ms9[SYMBOL_W-1:0],
            ms8[SYMBOL_W-1:0],
            ms7[SYMBOL_W-1:0],
            ms6[SYMBOL_W-1:0],
            ms5[SYMBOL_W-1:0],
            ms4[SYMBOL_W-1:0],
            ms3[SYMBOL_W-1:0],
            ms2[SYMBOL_W-1:0],
            ms1[SYMBOL_W-1:0],
            ls0[SYMBOL_W-1:0]
        };
    end
    endfunction

    function [SYMBOL_W-1:0] get_symbol;
        input [TOTAL_W-1:0] vec;
        input integer idx; // 0 = most-significant symbol
        integer msb;
        integer lsb;
    begin
        msb = TOTAL_W-1 - idx*SYMBOL_W;
        lsb = msb - (SYMBOL_W-1);
        get_symbol = vec[msb:lsb];
    end
    endfunction

    function [TOTAL_W-1:0] put_symbol;
        input [TOTAL_W-1:0] vec;
        input integer idx;
        input [SYMBOL_W-1:0] sym;
        integer msb;
        integer lsb;
        reg [TOTAL_W-1:0] temp;
    begin
        temp = vec;
        msb = TOTAL_W-1 - idx*SYMBOL_W;
        lsb = msb - (SYMBOL_W-1);
        temp[msb:lsb] = sym;
        put_symbol = temp;
    end
    endfunction

    function [TOTAL_W-1:0] model_shift;
        input [TOTAL_W-1:0] in_vec;
        input [2:0] shift_val;
        input [SYMBOL_W-1:0] fill_val;
        integer idx;
        integer shift_int;
        reg [TOTAL_W-1:0] result;
    begin
        result = {TOTAL_W{1'b0}};
        shift_int = shift_val;
        if (shift_int <= 4) begin
            for (idx = 0; idx < NUM_SYMBOLS; idx = idx + 1) begin
                if (idx < shift_int)
                    result = put_symbol(result, idx, fill_val);
                else
                    result = put_symbol(result, idx, get_symbol(in_vec, idx - shift_int));
            end
        end else begin
            result = {TOTAL_W{1'bx}};
        end
        model_shift = result;
    end
    endfunction

    task run_scenario;
        input [TOTAL_W-1:0] in_vec;
        input [2:0] shift_val;
        input [SYMBOL_W-1:0] fill_val;
        input integer expect_valid;
        input integer compare_data;
        input [TOTAL_W-1:0] expected_vec;
        input [8*64-1:0] label;
        reg expected_valid_bit;
    begin
        in = in_vec;
        shift = shift_val;
        fill = fill_val;
        #1;
        test_num = test_num + 1;
        expected_valid_bit = (expect_valid != 0) ? 1'b1 : 1'b0;

        if (out_valid !== expected_valid_bit) begin
            $display("FAIL: %0s (Test %0d) - out_valid expected %0b, got %0b", label, test_num, expected_valid_bit, out_valid);
            errors = errors + 1;
        end
        if ((compare_data != 0) && (out !== expected_vec)) begin
            $display("FAIL: %0s (Test %0d) - data expected %050b, got %050b", label, test_num, expected_vec, out);
            errors = errors + 1;
        end
    end
    endtask

    integer idx;
    integer sym_idx;
    reg [TOTAL_W-1:0] rand_in;
    reg [TOTAL_W-1:0] rand_expected;
    reg [SYMBOL_W-1:0] rand_fill;
    reg [2:0] rand_shift;
    reg [SYMBOL_W-1:0] rand_sym;

    initial begin
        in = {TOTAL_W{1'b0}};
        shift = 3'd0;
        fill = {SYMBOL_W{1'b0}};

        run_scenario(pack_syms(0,1,2,3,4,5,6,7,8,9), 3'd0, 5'd0, 1, 1, pack_syms(0,1,2,3,4,5,6,7,8,9), "Power-up mirror");
        run_scenario(pack_syms(0,1,2,3,4,5,6,7,8,9), 3'd0, 5'd3, 1, 1, pack_syms(0,1,2,3,4,5,6,7,8,9), "Zero shift baseline");
        run_scenario(pack_syms(31,30,29,28,27,26,25,24,23,22), 3'd1, 5'd17, 1, 1, pack_syms(17,31,30,29,28,27,26,25,24,23), "Single-symbol shift fill");
        run_scenario(pack_syms(5,10,15,20,25,30,0,7,14,21), 3'd4, 5'd1, 1, 1, pack_syms(1,1,1,1,5,10,15,20,25,30), "Max shift in range");
        run_scenario(pack_syms(0,0,0,0,0,0,0,0,0,0), 3'd4, 5'd31, 1, 1, pack_syms(31,31,31,31,0,0,0,0,0,0), "Fill replication");
        run_scenario(pack_syms(0,31,0,31,0,31,0,31,0,31), 3'd2, 5'd0, 1, 1, pack_syms(0,0,31,0,31,0,31,0,31,0), "Alternating pattern shift2");
        run_scenario(pack_syms(31,0,31,0,31,0,31,0,31,0), 3'd3, 5'd31, 1, 1, pack_syms(31,31,31,31,31,0,31,0,31,0), "Alternating pattern shift3");
        run_scenario(pack_syms(9,9,9,9,9,9,9,9,9,9), 3'd5, 5'd12, 0, 0, {TOTAL_W{1'bx}}, "Invalid shift=5 suppress valid");
        run_scenario(pack_syms(1,2,3,4,5,6,7,8,9,10), 3'd7, 5'd0, 0, 0, {TOTAL_W{1'bx}}, "Invalid shift=7 suppress valid");

        run_scenario(pack_syms(4,8,12,16,20,24,28,0,1,2), 3'd0, 5'd5, 1, 1, pack_syms(4,8,12,16,20,24,28,0,1,2), "Seq burst cycle1");
        run_scenario(pack_syms(4,8,12,16,20,24,28,0,1,2), 3'd2, 5'd7, 1, 1, pack_syms(7,7,4,8,12,16,20,24,28,0), "Seq burst cycle2");
        run_scenario(pack_syms(4,8,12,16,20,24,28,0,1,2), 3'd5, 5'd0, 0, 0, {TOTAL_W{1'bx}}, "Seq burst invalid shift");

        run_scenario(pack_syms(0,1,2,3,4,5,6,7,8,9), 3'd1, 5'd2, 1, 1, model_shift(pack_syms(0,1,2,3,4,5,6,7,8,9), 3'd1, 5'd2), "Toggle seq 1");
        run_scenario(pack_syms(10,11,12,13,14,15,16,17,18,19), 3'd4, 5'd30, 1, 1, model_shift(pack_syms(10,11,12,13,14,15,16,17,18,19), 3'd4, 5'd30), "Toggle seq 2");
        run_scenario(pack_syms(20,21,22,23,24,25,26,27,28,29), 3'd6, 5'd31, 0, 0, {TOTAL_W{1'bx}}, "Toggle seq invalid");
        run_scenario(pack_syms(30,31,0,1,2,3,4,5,6,7), 3'd0, 5'd5, 1, 1, model_shift(pack_syms(30,31,0,1,2,3,4,5,6,7), 3'd0, 5'd5), "Toggle seq 4");

        for (idx = 0; idx < 300; idx = idx + 1) begin
            rand_in = {TOTAL_W{1'b0}};
            for (sym_idx = 0; sym_idx < NUM_SYMBOLS; sym_idx = sym_idx + 1) begin
                rand_sym = $random;
                rand_in = put_symbol(rand_in, sym_idx, rand_sym);
            end
            rand_fill = $random;
            rand_shift = $random;
            rand_shift = rand_shift & 3'b111;
            rand_expected = model_shift(rand_in, rand_shift, rand_fill);
            run_scenario(rand_in, rand_shift, rand_fill, (rand_shift <= 3'd4), (rand_shift <= 3'd4), rand_expected, "Random sweep");
        end

        if (errors == 0)
            $display("PASS");
        else
            $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule