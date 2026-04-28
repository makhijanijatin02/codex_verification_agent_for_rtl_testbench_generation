`timescale 1ns/1ps

module tb;

reg clk;
reg rst;
reg reinit;
reg incr_valid;
reg decr_valid;
reg [3:0] initial_value;
reg [1:0] incr;
reg [1:0] decr;
wire [3:0] value;
wire [3:0] value_next;

integer errors;
integer seed;
integer i;
integer r;
reg [3:0] model_value;
reg [3:0] expected_tmp;

counter dut (
    .clk(clk),
    .rst(rst),
    .reinit(reinit),
    .incr_valid(incr_valid),
    .decr_valid(decr_valid),
    .initial_value(initial_value),
    .incr(incr),
    .decr(decr),
    .value(value),
    .value_next(value_next)
);

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

function [3:0] mod11;
    input integer x;
    integer t;
    begin
        t = x % 11;
        if (t < 0)
            t = t + 11;
        mod11 = t[3:0];
    end
endfunction

function [3:0] calc_next_no_rst;
    input [3:0] cur;
    input reinit_i;
    input incr_valid_i;
    input decr_valid_i;
    input [3:0] initv_i;
    input [1:0] incr_i;
    input [1:0] decr_i;
    integer delta;
    begin
        if (reinit_i) begin
            calc_next_no_rst = initv_i;
        end else begin
            delta = 0;
            if (incr_valid_i)
                delta = delta + incr_i;
            if (decr_valid_i)
                delta = delta - decr_i;
            calc_next_no_rst = mod11(cur + delta);
        end
    end
endfunction

function [3:0] calc_edge_next;
    input [3:0] cur;
    input rst_i;
    input reinit_i;
    input incr_valid_i;
    input decr_valid_i;
    input [3:0] initv_i;
    input [1:0] incr_i;
    input [1:0] decr_i;
    begin
        if (rst_i)
            calc_edge_next = initv_i;
        else
            calc_edge_next = calc_next_no_rst(cur, reinit_i, incr_valid_i, decr_valid_i, initv_i, incr_i, decr_i);
    end
endfunction

task fail_value;
    input integer code;
    input [3:0] expected;
    input [3:0] got;
    begin
        errors = errors + 1;
        $display("FAIL code=%0d time=%0t expected=%0d got=%0d model=%0d rst=%0b reinit=%0b incr_valid=%0b incr=%0d decr_valid=%0b decr=%0d initial_value=%0d",
                 code, $time, expected, got, model_value, rst, reinit, incr_valid, incr, decr_valid, decr, initial_value);
    end
endtask

task apply_inputs;
    input rst_i;
    input reinit_i;
    input incr_valid_i;
    input decr_valid_i;
    input [3:0] initv_i;
    input [1:0] incr_i;
    input [1:0] decr_i;
    begin
        rst = rst_i;
        reinit = reinit_i;
        incr_valid = incr_valid_i;
        decr_valid = decr_valid_i;
        initial_value = initv_i;
        incr = incr_i;
        decr = decr_i;
    end
endtask

task poke_and_check;
    input rst_i;
    input reinit_i;
    input incr_valid_i;
    input decr_valid_i;
    input [3:0] initv_i;
    input [1:0] incr_i;
    input [1:0] decr_i;
    input integer code_base;
    reg [3:0] expected_next_local;
    begin
        apply_inputs(rst_i, reinit_i, incr_valid_i, decr_valid_i, initv_i, incr_i, decr_i);
        #1;
        if (value !== model_value)
            fail_value(code_base, model_value, value);
        if (!rst_i) begin
            expected_next_local = calc_next_no_rst(model_value, reinit_i, incr_valid_i, decr_valid_i, initv_i, incr_i, decr_i);
            if (value_next !== expected_next_local)
                fail_value(code_base + 1, expected_next_local, value_next);
        end
    end
endtask

task cycle_step;
    input rst_i;
    input reinit_i;
    input incr_valid_i;
    input decr_valid_i;
    input [3:0] initv_i;
    input [1:0] incr_i;
    input [1:0] decr_i;
    input integer code_base;
    reg [3:0] edge_expected;
    begin
        edge_expected = calc_edge_next(model_value, rst_i, reinit_i, incr_valid_i, decr_valid_i, initv_i, incr_i, decr_i);
        poke_and_check(rst_i, reinit_i, incr_valid_i, decr_valid_i, initv_i, incr_i, decr_i, code_base);
        @(posedge clk);
        #1;
        model_value = edge_expected;
        if (value !== model_value)
            fail_value(code_base + 2, model_value, value);
    end
endtask

task force_state;
    input [3:0] target;
    input integer code_base;
    begin
        cycle_step(1'b0, 1'b1, 1'b0, 1'b0, target, 2'd0, 2'd0, code_base);
    end
endtask

task check_reset_between_edges;
    input [3:0] start_state;
    input [3:0] load_value;
    input integer code_base;
    begin
        force_state(start_state, code_base);
        apply_inputs(1'b1, 1'b0, 1'b1, 1'b1, load_value, 2'd3, 2'd2);
        #1;
        if (value !== start_state)
            fail_value(code_base + 1, start_state, value);
        @(posedge clk);
        #1;
        model_value = load_value;
        if (value !== model_value)
            fail_value(code_base + 2, model_value, value);
    end
endtask

task repeated_reset_loads;
    input [3:0] first_value;
    input [3:0] second_value;
    input integer code_base;
    begin
        apply_inputs(1'b1, 1'b0, 1'b0, 1'b0, first_value, 2'd0, 2'd0);
        #1;
        if (value !== model_value)
            fail_value(code_base, model_value, value);
        @(posedge clk);
        #1;
        model_value = first_value;
        if (value !== model_value)
            fail_value(code_base + 1, model_value, value);

        apply_inputs(1'b1, 1'b0, 1'b0, 1'b0, second_value, 2'd0, 2'd0);
        #1;
        if (value !== model_value)
            fail_value(code_base + 2, model_value, value);
        @(posedge clk);
        #1;
        model_value = second_value;
        if (value !== model_value)
            fail_value(code_base + 3, model_value, value);
    end
endtask

function integer rand_nonneg;
    input integer raw;
    begin
        if (raw < 0)
            rand_nonneg = -raw;
        else
            rand_nonneg = raw;
    end
endfunction

task choose_biased_init;
    output [3:0] out_init;
    integer raw_local;
    integer sel;
    begin
        raw_local = rand_nonneg($random(seed));
        sel = raw_local % 8;
        case (sel)
            0: out_init = 4'd0;
            1: out_init = 4'd1;
            2: out_init = 4'd9;
            3: out_init = 4'd10;
            default: out_init = rand_nonneg($random(seed)) % 11;
        endcase
    end
endtask

task choose_legal_2b;
    output [1:0] out_v;
    begin
        out_v = rand_nonneg($random(seed)) % 4;
    end
endtask

initial begin
    errors = 0;
    seed = 32'h1a2b3c4d;
    rst = 1'b0;
    reinit = 1'b0;
    incr_valid = 1'b0;
    decr_valid = 1'b0;
    initial_value = 4'd0;
    incr = 2'd0;
    decr = 2'd0;
    model_value = 4'd0;

    apply_inputs(1'b1, 1'b0, 1'b0, 1'b0, 4'd0, 2'd0, 2'd0);
    @(posedge clk);
    #1;
    model_value = 4'd0;
    if (value !== model_value)
        fail_value(1, model_value, value);

    cycle_step(1'b0, 1'b0, 1'b0, 1'b0, 4'd3, 2'd2, 2'd1, 100);
    cycle_step(1'b0, 1'b0, 1'b1, 1'b0, 4'd0, 2'd2, 2'd0, 110);
    cycle_step(1'b0, 1'b0, 1'b0, 1'b1, 4'd0, 2'd0, 2'd3, 120);
    cycle_step(1'b0, 1'b0, 1'b1, 1'b1, 4'd0, 2'd3, 2'd1, 130);

    cycle_step(1'b0, 1'b1, 1'b1, 1'b1, 4'd3, 2'd3, 2'd0, 200);

    force_state(4'd6, 300);
    poke_and_check(1'b0, 1'b0, 1'b1, 1'b0, 4'd0, 2'd1, 2'd0, 310);
    poke_and_check(1'b0, 1'b0, 1'b0, 1'b1, 4'd0, 2'd0, 2'd2, 320);
    @(posedge clk);
    #1;
    model_value = 4'd4;
    if (value !== model_value)
        fail_value(330, model_value, value);

    force_state(4'd9, 400);
    cycle_step(1'b0, 1'b0, 1'b1, 1'b0, 4'd0, 2'd3, 2'd0, 410);
    force_state(4'd10, 420);
    cycle_step(1'b0, 1'b0, 1'b1, 1'b0, 4'd0, 2'd1, 2'd0, 430);

    force_state(4'd1, 500);
    cycle_step(1'b0, 1'b0, 1'b0, 1'b1, 4'd0, 2'd0, 2'd3, 510);
    force_state(4'd0, 520);
    cycle_step(1'b0, 1'b0, 1'b0, 1'b1, 4'd0, 2'd0, 2'd1, 530);

    force_state(4'd6, 600);
    cycle_step(1'b0, 1'b0, 1'b1, 1'b1, 4'd0, 2'd2, 2'd2, 610);
    force_state(4'd10, 620);
    cycle_step(1'b0, 1'b0, 1'b1, 1'b1, 4'd0, 2'd3, 2'd3, 630);

    force_state(4'd0, 700);
    cycle_step(1'b0, 1'b0, 1'b1, 1'b0, 4'd10, 2'd3, 2'd0, 710);
    force_state(4'd10, 720);
    cycle_step(1'b0, 1'b0, 1'b0, 1'b1, 4'd0, 2'd0, 2'd2, 730);
    force_state(4'd5, 740);
    cycle_step(1'b0, 1'b0, 1'b1, 1'b1, 4'd0, 2'd1, 2'd2, 750);

    force_state(4'd3, 800);
    poke_and_check(1'b0, 1'b0, 1'b1, 1'b0, 4'd0, 2'd3, 2'd0, 810);
    @(negedge clk);
    poke_and_check(1'b0, 1'b0, 1'b0, 1'b1, 4'd0, 2'd0, 2'd1, 820);
    @(posedge clk);
    #1;
    model_value = 4'd2;
    if (value !== model_value)
        fail_value(830, model_value, value);

    check_reset_between_edges(4'd6, 4'd4, 900);
    force_state(4'd9, 950);
    cycle_step(1'b1, 1'b1, 1'b1, 1'b1, 4'd7, 2'd3, 2'd1, 960);
    repeated_reset_loads(4'd2, 4'd10, 1000);

    cycle_step(1'b1, 1'b0, 1'b0, 1'b0, 4'd0, 2'd0, 2'd0, 1100);
    cycle_step(1'b0, 1'b0, 1'b1, 1'b0, 4'd0, 2'd3, 2'd0, 1110);
    cycle_step(1'b0, 1'b0, 1'b1, 1'b1, 4'd0, 2'd1, 2'd1, 1120);
    cycle_step(1'b0, 1'b0, 1'b0, 1'b1, 4'd0, 2'd0, 2'd3, 1130);
    cycle_step(1'b0, 1'b0, 1'b0, 1'b1, 4'd0, 2'd0, 2'd1, 1140);
    cycle_step(1'b0, 1'b0, 1'b1, 1'b0, 4'd0, 2'd3, 2'd0, 1150);
    cycle_step(1'b0, 1'b1, 1'b1, 1'b1, 4'd8, 2'd3, 2'd2, 1160);
    cycle_step(1'b0, 1'b0, 1'b0, 1'b0, 4'd0, 2'd0, 2'd0, 1170);
    cycle_step(1'b1, 1'b1, 1'b1, 1'b0, 4'd5, 2'd3, 2'd0, 1180);

    cycle_step(1'b1, 1'b0, 1'b0, 1'b0, 4'd0, 2'd0, 2'd0, 1200);
    cycle_step(1'b0, 1'b0, 1'b1, 1'b0, 4'd0, 2'd3, 2'd0, 1210);
    cycle_step(1'b0, 1'b0, 1'b1, 1'b0, 4'd0, 2'd3, 2'd0, 1220);
    cycle_step(1'b0, 1'b0, 1'b1, 1'b0, 4'd0, 2'd3, 2'd0, 1230);
    cycle_step(1'b0, 1'b0, 1'b1, 1'b0, 4'd0, 2'd3, 2'd0, 1240);
    cycle_step(1'b0, 1'b0, 1'b0, 1'b1, 4'd0, 2'd0, 2'd3, 1250);
    cycle_step(1'b0, 1'b0, 1'b0, 1'b1, 4'd0, 2'd0, 2'd3, 1260);
    cycle_step(1'b0, 1'b0, 1'b0, 1'b1, 4'd0, 2'd0, 2'd3, 1270);
    cycle_step(1'b0, 1'b0, 1'b0, 1'b1, 4'd0, 2'd0, 2'd3, 1280);

    cycle_step(1'b0, 1'b0, 1'b0, 1'b0, 4'd0, 2'd0, 2'd0, 1300);
    cycle_step(1'b0, 1'b0, 1'b1, 1'b0, 4'd0, 2'd2, 2'd0, 1310);
    cycle_step(1'b0, 1'b0, 1'b1, 1'b1, 4'd0, 2'd0, 2'd1, 1320);
    cycle_step(1'b0, 1'b1, 1'b1, 1'b0, 4'd4, 2'd3, 2'd0, 1330);
    cycle_step(1'b0, 1'b0, 1'b1, 1'b0, 4'd0, 2'd3, 2'd0, 1340);

    for (i = 0; i < 200; i = i + 1) begin
        reg [3:0] rand_init;
        reg [1:0] rand_incr;
        reg [1:0] rand_decr;
        reg rand_rst;
        reg rand_reinit;
        reg rand_incr_valid;
        reg rand_decr_valid;
        reg [3:0] tmp_init;
        reg [1:0] tmp_incr;
        reg [1:0] tmp_decr;
        reg tmp_rst;
        reg tmp_reinit;
        reg tmp_incr_valid;
        reg tmp_decr_valid;

        choose_biased_init(rand_init);
        choose_legal_2b(rand_incr);
        choose_legal_2b(rand_decr);
        r = rand_nonneg($random(seed)) % 100;

        rand_rst = 1'b0;
        rand_reinit = 1'b0;
        rand_incr_valid = 1'b0;
        rand_decr_valid = 1'b0;

        if (r < 15) begin
            rand_rst = 1'b1;
        end else if (r < 30) begin
            rand_reinit = 1'b1;
        end else if (r < 55) begin
            rand_incr_valid = 1'b1;
            rand_decr_valid = 1'b1;
            if ((rand_nonneg($random(seed)) % 4) == 0)
                rand_decr = rand_incr;
        end else if (r < 70) begin
            rand_incr_valid = 1'b0;
            rand_decr_valid = 1'b0;
        end else if (r < 85) begin
            rand_incr_valid = 1'b1;
        end else begin
            rand_decr_valid = 1'b1;
        end

        if ((rand_nonneg($random(seed)) % 4) == 0) begin
            choose_biased_init(tmp_init);
            choose_legal_2b(tmp_incr);
            choose_legal_2b(tmp_decr);
            tmp_rst = 1'b0;
            tmp_reinit = 1'b0;
            r = rand_nonneg($random(seed)) % 4;
            case (r)
                0: begin tmp_incr_valid = 1'b0; tmp_decr_valid = 1'b0; end
                1: begin tmp_incr_valid = 1'b1; tmp_decr_valid = 1'b0; end
                2: begin tmp_incr_valid = 1'b0; tmp_decr_valid = 1'b1; end
                default: begin tmp_incr_valid = 1'b1; tmp_decr_valid = 1'b1; end
            endcase
            poke_and_check(tmp_rst, tmp_reinit, tmp_incr_valid, tmp_decr_valid, tmp_init, tmp_incr, tmp_decr, 2000 + (i * 10));

            if ((rand_nonneg($random(seed)) % 2) == 0) begin
                @(negedge clk);
                choose_biased_init(tmp_init);
                choose_legal_2b(tmp_incr);
                choose_legal_2b(tmp_decr);
                tmp_rst = 1'b0;
                tmp_reinit = 1'b0;
                r = rand_nonneg($random(seed)) % 4;
                case (r)
                    0: begin tmp_incr_valid = 1'b0; tmp_decr_valid = 1'b0; end
                    1: begin tmp_incr_valid = 1'b1; tmp_decr_valid = 1'b0; end
                    2: begin tmp_incr_valid = 1'b0; tmp_decr_valid = 1'b1; end
                    default: begin tmp_incr_valid = 1'b1; tmp_decr_valid = 1'b1; end
                endcase
                poke_and_check(tmp_rst, tmp_reinit, tmp_incr_valid, tmp_decr_valid, tmp_init, tmp_incr, tmp_decr, 2001 + (i * 10));
            end
        end

        cycle_step(rand_rst, rand_reinit, rand_incr_valid, rand_decr_valid, rand_init, rand_incr, rand_decr, 2002 + (i * 10));
    end

    if (errors == 0)
        $display("PASS");
    else
        $display("FAIL errors=%0d", errors);

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

    always @(posedge rst) begin
        if (($time - tb_sync_reset_last_clock_edge) > 0) begin
            tb_sync_reset_snapshot = value;
            #1;
            if (value !== tb_sync_reset_snapshot) begin
                $display("FAIL: synchronous reset changed registered outputs before clock edge at %0t", $time);
                $finish;
            end
        end
    end

endmodule