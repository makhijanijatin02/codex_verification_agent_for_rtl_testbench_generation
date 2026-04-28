`timescale 1ns/1ps

module tb;

reg clk;
reg rst;
reg push_sender_in_reset;
wire push_receiver_in_reset;
reg push_credit_stall;
wire push_credit;
reg push_valid;
reg pop_credit;
wire pop_valid;
reg credit_initial;
reg credit_withhold;
wire credit_count;
wire credit_available;
reg [7:0] push_data;
wire [7:0] pop_data;

integer failures;
reg sampled_push_credit;

credit_receiver dut (
    .clk(clk),
    .rst(rst),
    .push_sender_in_reset(push_sender_in_reset),
    .push_receiver_in_reset(push_receiver_in_reset),
    .push_credit_stall(push_credit_stall),
    .push_credit(push_credit),
    .push_valid(push_valid),
    .pop_credit(pop_credit),
    .pop_valid(pop_valid),
    .credit_initial(credit_initial),
    .credit_withhold(credit_withhold),
    .credit_count(credit_count),
    .credit_available(credit_available),
    .push_data(push_data),
    .pop_data(pop_data)
);

always #5 clk = ~clk;

task fail;
    input [8*160-1:0] msg;
    begin
        failures = failures + 1;
        $display("FAIL: %0s at time %0t", msg, $time);
    end
endtask

task check_core;
    input [8*160-1:0] msg;
    reg exp_pop_valid;
    begin
        exp_pop_valid = push_valid && !rst && !push_sender_in_reset;

        if (pop_data !== push_data)
            fail({msg, " pop_data mismatch"});

        if (push_receiver_in_reset !== rst)
            fail({msg, " push_receiver_in_reset must equal rst"});

        if (pop_valid !== exp_pop_valid)
            fail({msg, " pop_valid mismatch"});

        if ((rst || push_sender_in_reset) && (push_credit !== 1'b0))
            fail({msg, " push_credit must be low in reset state"});
    end
endtask

task check_count;
    input expected;
    input [8*160-1:0] msg;
    begin
        if (credit_count !== expected)
            fail({msg, " credit_count mismatch"});
    end
endtask

task settle_and_check;
    input [8*160-1:0] msg;
    begin
        #1;
        check_core(msg);
    end
endtask

task sample_cycle_push_credit;
    input [8*160-1:0] msg;
    begin
        #1;
        check_core(msg);
        sampled_push_credit = push_credit;
    end
endtask

task step_posedge_and_check_count;
    input expected;
    input [8*160-1:0] msg;
    begin
        @(posedge clk);
        #1;
        check_core(msg);
        check_count(expected, msg);
    end
endtask

task drive_defaults;
    begin
        rst = 1'b0;
        push_sender_in_reset = 1'b0;
        push_credit_stall = 1'b0;
        push_valid = 1'b0;
        pop_credit = 1'b0;
        credit_initial = 1'b0;
        credit_withhold = 1'b0;
        push_data = 8'h00;
    end
endtask

initial begin
    clk = 1'b0;
    failures = 0;
    sampled_push_credit = 1'b0;
    drive_defaults;

    settle_and_check("initial idle");

    rst = 1'b1;
    push_valid = 1'b1;
    push_data = 8'h3c;
    credit_initial = 1'b0;
    pop_credit = 1'b1;
    credit_withhold = 1'b1;
    settle_and_check("rst immediate block init0");
    if (push_receiver_in_reset !== 1'b1)
        fail("rst immediate block init0 push_receiver_in_reset");
    step_posedge_and_check_count(1'b0, "rst reload init0");

    @(negedge clk);
    credit_initial = 1'b1;
    push_data = 8'ha5;
    push_valid = 1'b1;
    pop_credit = 1'b0;
    credit_withhold = 1'b0;
    settle_and_check("rst immediate block init1");
    step_posedge_and_check_count(1'b1, "rst reload init1");

    @(negedge clk);
    rst = 1'b0;
    push_sender_in_reset = 1'b1;
    credit_initial = 1'b0;
    push_valid = 1'b1;
    push_data = 8'h55;
    pop_credit = 1'b1;
    settle_and_check("sender reset immediate block");
    if (push_receiver_in_reset !== 1'b0)
        fail("sender reset must not drive push_receiver_in_reset");
    step_posedge_and_check_count(1'b0, "sender reset reload init0");

    @(negedge clk);
    push_sender_in_reset = 1'b0;
    push_valid = 1'b0;
    push_data = 8'h00;
    pop_credit = 1'b0;
    credit_initial = 1'b0;
    settle_and_check("leave sender reset");

    push_data = 8'h00;
    push_valid = 1'b0;
    settle_and_check("active data valid 00");
    if (pop_valid !== 1'b0)
        fail("pop_valid should follow push_valid low");

    push_data = 8'h5a;
    push_valid = 1'b1;
    settle_and_check("active data valid 5a");
    if (pop_valid !== 1'b1)
        fail("pop_valid should follow push_valid high");

    push_data = 8'ha5;
    settle_and_check("active data valid a5");

    push_data = 8'hff;
    settle_and_check("active data valid ff");

    @(negedge clk);
    rst = 1'b1;
    push_valid = 1'b1;
    push_data = 8'hc3;
    settle_and_check("data path still passes during rst");
    if (pop_data !== 8'hc3)
        fail("pop_data must pass through during rst");
    @(negedge clk);
    rst = 1'b0;
    push_sender_in_reset = 1'b1;
    push_data = 8'h3c;
    settle_and_check("data path still passes during sender reset");
    if (pop_data !== 8'h3c)
        fail("pop_data must pass through during sender reset");

    @(negedge clk);
    push_sender_in_reset = 1'b0;
    rst = 1'b1;
    credit_initial = 1'b1;
    push_credit_stall = 1'b0;
    credit_withhold = 1'b0;
    settle_and_check("prepare push_credit priority reset");
    step_posedge_and_check_count(1'b1, "reload count for push_credit priority");
    @(negedge clk);
    rst = 1'b0;
    settle_and_check("active with credit available");
    if (push_credit !== 1'b1)
        fail("push_credit should assert when count=1, withhold=0, stall=0");
    push_credit_stall = 1'b1;
    settle_and_check("stall suppresses push_credit");
    if (push_credit !== 1'b0)
        fail("push_credit should be low when stalled");

    @(negedge clk);
    rst = 1'b1;
    credit_initial = 1'b0;
    push_credit_stall = 1'b1;
    pop_credit = 1'b0;
    settle_and_check("prepare count zero");
    step_posedge_and_check_count(1'b0, "reload count zero");
    @(negedge clk);
    rst = 1'b0;
    push_credit_stall = 1'b0;
    credit_withhold = 1'b0;
    settle_and_check("count zero no push_credit");
    if (push_credit !== 1'b0)
        fail("push_credit should be low when count=0 and withhold=0");

    @(negedge clk);
    pop_credit = 1'b1;
    settle_and_check("no count change before posedge on pop_credit rise");
    check_count(1'b0, "no posedge yet after pop_credit rise");
    @(negedge clk);
    pop_credit = 1'b0;
    settle_and_check("no count change before posedge on pop_credit fall");
    check_count(1'b0, "no posedge yet after pop_credit fall");

    @(negedge clk);
    rst = 1'b1;
    credit_initial = 1'b0;
    push_credit_stall = 1'b1;
    pop_credit = 1'b0;
    credit_withhold = 1'b0;
    settle_and_check("prep increment from zero");
    step_posedge_and_check_count(1'b0, "reload zero before increment");

    @(negedge clk);
    rst = 1'b0;
    push_credit_stall = 1'b1;
    pop_credit = 1'b1;
    sample_cycle_push_credit("increment cycle sample");
    if (sampled_push_credit !== 1'b0)
        fail("sampled push_credit should be low during stalled increment setup");
    step_posedge_and_check_count(1'b1, "increment from pop_credit only");

    @(negedge clk);
    rst = 1'b1;
    credit_initial = 1'b1;
    push_credit_stall = 1'b0;
    pop_credit = 1'b0;
    credit_withhold = 1'b0;
    settle_and_check("prep previous-cycle decrement");
    step_posedge_and_check_count(1'b1, "reload one before decrement");

    @(negedge clk);
    rst = 1'b0;
    push_credit_stall = 1'b0;
    pop_credit = 1'b0;
    sample_cycle_push_credit("sample cycle with push_credit high");
    if (sampled_push_credit !== 1'b1)
        fail("push_credit should be high before previous-cycle decrement test");

    @(negedge clk);
    push_credit_stall = 1'b1;
    pop_credit = 1'b0;
    settle_and_check("current push_credit forced low before decrement edge");
    if (push_credit !== 1'b0)
        fail("current push_credit should be low when stalled");
    step_posedge_and_check_count(1'b0, "previous-cycle push_credit must decrement");

    @(negedge clk);
    rst = 1'b1;
    credit_initial = 1'b1;
    push_credit_stall = 1'b0;
    pop_credit = 1'b0;
    credit_withhold = 1'b0;
    settle_and_check("prep simultaneous inc dec");
    step_posedge_and_check_count(1'b1, "reload one before simultaneous inc dec");

    @(negedge clk);
    rst = 1'b0;
    push_credit_stall = 1'b0;
    pop_credit = 1'b0;
    sample_cycle_push_credit("sample prev push_credit for simultaneous inc dec");
    if (sampled_push_credit !== 1'b1)
        fail("push_credit should be high before simultaneous inc dec");

    @(negedge clk);
    pop_credit = 1'b1;
    push_credit_stall = 1'b1;
    settle_and_check("set simultaneous inc dec edge");
    step_posedge_and_check_count(1'b1, "simultaneous pop_credit and prev push_credit");

    @(negedge clk);
    rst = 1'b1;
    credit_initial = 1'b1;
    push_credit_stall = 1'b0;
    pop_credit = 1'b1;
    settle_and_check("reset priority over update with rst");
    step_posedge_and_check_count(1'b1, "rst priority reload");

    @(negedge clk);
    rst = 1'b0;
    push_sender_in_reset = 1'b1;
    credit_initial = 1'b0;
    push_credit_stall = 1'b0;
    pop_credit = 1'b1;
    settle_and_check("reset priority over update with sender reset");
    step_posedge_and_check_count(1'b0, "sender reset priority reload");

    @(negedge clk);
    push_sender_in_reset = 1'b0;
    rst = 1'b0;
    push_credit_stall = 1'b0;
    pop_credit = 1'b0;
    push_valid = 1'b1;
    credit_withhold = 1'b1;
    push_data = 8'h96;
    settle_and_check("final active sanity");
    if (pop_data !== 8'h96)
        fail("final active sanity pop_data");
    if (pop_valid !== 1'b1)
        fail("final active sanity pop_valid");

    if (failures == 0) begin
        $display("PASS");
    end else begin
        $display("FAILURES: %0d", failures);
    end
    $finish;
end

endmodule