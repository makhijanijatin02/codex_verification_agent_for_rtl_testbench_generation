`timescale 1ns/1ps

module tb;

reg clk;
reg reset;
reg enable;
wire [3:0] count;

integer errors;
integer rand_i;
reg [3:0] exp_count;
reg [3:0] sampled_count;
reg [3:0] next_expected;

counter_4bit dut (
    .clk(clk),
    .reset(reset),
    .enable(enable),
    .count(count)
);

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

task fail;
    input [255:0] msg;
    begin
        errors = errors + 1;
        $display("FAIL: %0s at time %0t, reset=%b enable=%b expected=%h got=%h",
                 msg, $time, reset, enable, exp_count, count);
    end
endtask

task check_count;
    input [3:0] expected;
    input [255:0] msg;
    begin
        if (count !== expected) begin
            exp_count = expected;
            fail(msg);
        end
    end
endtask

task step;
    input step_reset;
    input step_enable;
    input [255:0] msg;
    begin
        reset = step_reset;
        enable = step_enable;

        next_expected = exp_count;
        if (step_reset)
            next_expected = 4'h0;
        else if (step_enable)
            next_expected = exp_count + 4'h1;

        @(posedge clk);
        #1;
        if (count !== next_expected) begin
            exp_count = next_expected;
            fail(msg);
        end else begin
            exp_count = next_expected;
        end
    end
endtask

task check_no_negedge_change;
    input [255:0] msg;
    begin
        sampled_count = count;
        @(negedge clk);
        #1;
        if (count !== sampled_count) begin
            exp_count = sampled_count;
            fail(msg);
        end
    end
endtask

task check_midcycle_stable;
    input [255:0] msg;
    begin
        sampled_count = count;
        #1;
        if (count !== sampled_count) begin
            exp_count = sampled_count;
            fail(msg);
        end
    end
endtask

initial begin
    errors = 0;
    reset = 1'b0;
    enable = 1'b0;
    exp_count = 4'h0;
    sampled_count = 4'h0;
    next_expected = 4'h0;

    step(1'b1, 1'b0, "initial synchronous reset");
    check_count(4'h0, "count must be 0 after initial reset");

    step(1'b0, 1'b1, "increment to 1");
    step(1'b0, 1'b1, "increment to 2");
    step(1'b0, 1'b1, "increment to 3");
    step(1'b0, 1'b1, "increment to 4");

    step(1'b0, 1'b0, "hold at 4, cycle 1");
    step(1'b0, 1'b0, "hold at 4, cycle 2");
    step(1'b0, 1'b0, "hold at 4, cycle 3");

    step(1'b1, 1'b0, "reset before alternating pattern");
    step(1'b0, 1'b1, "alternating pattern count=1");
    step(1'b0, 1'b0, "alternating pattern hold=1");
    step(1'b0, 1'b1, "alternating pattern count=2");
    step(1'b0, 1'b0, "alternating pattern hold=2");

    step(1'b1, 1'b0, "reset before modulo traversal");
    for (rand_i = 0; rand_i < 16; rand_i = rand_i + 1) begin
        step(1'b0, 1'b1, "modulo traversal increment");
    end
    check_count(4'h0, "full modulo-16 traversal must wrap to 0");

    step(1'b1, 1'b0, "reset before 14->15->0 boundary");
    for (rand_i = 0; rand_i < 14; rand_i = rand_i + 1) begin
        step(1'b0, 1'b1, "drive count toward 14");
    end
    check_count(4'he, "count should be 14 before boundary test");
    step(1'b0, 1'b1, "boundary 14->15");
    check_count(4'hf, "count should be 15 after 14->15");
    step(1'b0, 1'b1, "boundary 15->0 wrap");
    check_count(4'h0, "count should wrap 15->0");

    step(1'b1, 1'b0, "reset before hold-at-0 test");
    step(1'b0, 1'b0, "hold at 0");
    check_count(4'h0, "count must hold at 0 with enable low");

    step(1'b1, 1'b0, "reset before hold-at-15 test");
    for (rand_i = 0; rand_i < 15; rand_i = rand_i + 1) begin
        step(1'b0, 1'b1, "drive count toward 15");
    end
    check_count(4'hf, "count should be 15 before hold-at-15 test");
    step(1'b0, 1'b0, "hold at 15");
    step(1'b0, 1'b0, "hold at 15 again");
    check_count(4'hf, "count must hold at 15 with enable low");

    step(1'b0, 1'b1, "prepare nonzero state for synchronous reset check");
    step(1'b0, 1'b1, "prepare nonzero state for synchronous reset check");
    check_count(4'h1, "count should be 1 after wrapping and incrementing twice from 15-hold sequence");
    reset = 1'b1;
    enable = 1'b0;
    #2;
    check_count(4'h1, "asserting reset between posedges must not change count immediately");
    @(negedge clk);
    #1;
    check_count(4'h1, "count must not change on negedge while reset asserted");
    @(posedge clk);
    #1;
    exp_count = 4'h0;
    check_count(4'h0, "synchronous reset must take effect on next posedge only");

    step(1'b1, 1'b0, "reset before reset-priority test");
    for (rand_i = 0; rand_i < 15; rand_i = rand_i + 1) begin
        step(1'b0, 1'b1, "drive to 15 for reset-priority test");
    end
    check_count(4'hf, "count should be 15 before reset-priority test");
    step(1'b1, 1'b1, "reset and enable high together, reset must win");
    check_count(4'h0, "reset must have priority over enable");

    step(1'b1, 1'b0, "reset before wrong-edge test");
    for (rand_i = 0; rand_i < 5; rand_i = rand_i + 1) begin
        step(1'b0, 1'b1, "drive to count 5");
    end
    check_count(4'h5, "count should be 5 before wrong-edge test");
    reset = 1'b0;
    enable = 1'b1;
    sampled_count = count;
    @(negedge clk);
    #1;
    if (count !== 4'h5) begin
        exp_count = 4'h5;
        fail("count changed on negedge");
    end
    @(posedge clk);
    #1;
    exp_count = 4'h6;
    check_count(4'h6, "count must increment on following posedge only");

    step(1'b1, 1'b0, "reset before mixed sequence");
    step(1'b0, 1'b1, "mixed seq increment 1");
    step(1'b0, 1'b1, "mixed seq increment 2");
    step(1'b0, 1'b1, "mixed seq increment 3");
    step(1'b0, 1'b0, "mixed seq hold 3 cycle 1");
    step(1'b0, 1'b0, "mixed seq hold 3 cycle 2");
    step(1'b0, 1'b1, "mixed seq increment 4");
    step(1'b0, 1'b1, "mixed seq increment 5");
    step(1'b1, 1'b1, "mixed seq reset+enable priority");
    step(1'b0, 1'b1, "mixed seq increment after reset");
    check_count(4'h1, "mixed sequence final count");

    step(1'b1, 1'b0, "reset before one-cycle timing sequence");
    step(1'b0, 1'b1, "timing seq expect 1");
    check_count(4'h1, "timing seq count 1");
    step(1'b0, 1'b0, "timing seq expect hold 1");
    check_count(4'h1, "timing seq hold at 1");
    step(1'b0, 1'b1, "timing seq expect 2");
    check_count(4'h2, "timing seq count 2");
    step(1'b0, 1'b1, "timing seq expect 3");
    check_count(4'h3, "timing seq count 3");
    step(1'b0, 1'b0, "timing seq expect hold 3");
    check_count(4'h3, "timing seq final hold at 3");

    step(1'b1, 1'b0, "reset before nonzero reset recovery");
    for (rand_i = 0; rand_i < 9; rand_i = rand_i + 1) begin
        step(1'b0, 1'b1, "drive to 9");
    end
    check_count(4'h9, "count should be 9 before recovery sequence");
    step(1'b0, 1'b0, "hold at 9");
    check_count(4'h9, "count should hold at 9");
    step(1'b1, 1'b0, "reset from nonzero state");
    check_count(4'h0, "count should reset to 0 from nonzero state");
    step(1'b0, 1'b0, "hold at 0 after reset");
    check_count(4'h0, "count should stay 0 after reset when enable low");
    step(1'b0, 1'b1, "increment to 1 after reset");
    step(1'b0, 1'b1, "increment to 2 after reset");
    check_count(4'h2, "count should be 2 after recovery sequence");

    step(1'b1, 1'b0, "reset before active-low reset discrimination");
    for (rand_i = 0; rand_i < 3; rand_i = rand_i + 1) begin
        step(1'b0, 1'b1, "drive to 3");
    end
    check_count(4'h3, "count should be 3 before active-low reset discrimination");
    step(1'b0, 1'b0, "with reset low, state must hold and not reset");
    check_count(4'h3, "reset low must not reset the DUT");

    step(1'b1, 1'b0, "reset before registered-output stability checks");
    step(1'b0, 1'b1, "increment to 1 for stability check");
    reset = 1'b0;
    enable = 1'b0;
    check_midcycle_stable("count changed within cycle without clock edge");
    check_no_negedge_change("count changed on negedge during hold");
    reset = 1'b1;
    enable = 1'b0;
    #2;
    check_count(4'h1, "mid-cycle reset assertion must not immediately affect output");
    @(posedge clk);
    #1;
    exp_count = 4'h0;
    check_count(4'h0, "reset must apply at posedge after mid-cycle assertion");

    step(1'b1, 1'b0, "reset before random reference-model test");
    for (rand_i = 0; rand_i < 100; rand_i = rand_i + 1) begin
        case ($random % 5)
            0: begin reset = 1'b1; enable = 1'b0; end
            1: begin reset = 1'b1; enable = 1'b1; end
            2: begin reset = 1'b0; enable = 1'b1; end
            3: begin reset = 1'b0; enable = 1'b0; end
            default: begin reset = $random; enable = $random; end
        endcase

        sampled_count = count;
        #1;
        if (count !== sampled_count) begin
            exp_count = sampled_count;
            fail("count changed in mid-cycle during random test");
        end

        if (($random & 1'b1) == 1'b1) begin
            reset = ~reset;
            enable = ~enable;
            #1;
            if (count !== sampled_count) begin
                exp_count = sampled_count;
                fail("count responded immediately to mid-cycle control toggle");
            end
        end

        next_expected = exp_count;
        if (reset)
            next_expected = 4'h0;
        else if (enable)
            next_expected = exp_count + 4'h1;

        @(negedge clk);
        #1;
        if (count !== exp_count) begin
            fail("count changed on negedge during random test");
        end

        @(posedge clk);
        #1;
        if (count !== next_expected) begin
            exp_count = next_expected;
            fail("random reference-model mismatch");
        end else begin
            exp_count = next_expected;
        end
    end

    if (errors == 0)
        $display("PASS");
    else
        $display("FAIL: %0d mismatches detected", errors);

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