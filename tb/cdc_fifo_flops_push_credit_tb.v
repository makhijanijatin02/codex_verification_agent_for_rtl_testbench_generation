`timescale 1ns/1ps

module tb;

  reg        push_clk;
  reg        push_rst;
  reg        pop_clk;
  reg        pop_rst;
  reg        push_sender_in_reset;
  reg        push_credit_stall;
  reg        push_valid;
  reg        pop_ready;
  reg [7:0]  push_data;
  reg [4:0]  credit_initial_push;
  reg [4:0]  credit_withhold_push;

  wire       push_receiver_in_reset;
  wire       push_credit;
  wire       pop_valid;
  wire       push_full;
  wire       pop_empty;
  wire [7:0] pop_data;
  wire [4:0] push_slots;
  wire [4:0] credit_count_push;
  wire [4:0] credit_available_push;
  wire [4:0] pop_items;

  reg [7:0] expected_q [0:255];
  integer expected_head;
  integer expected_tail;
  integer expected_count;

  integer completed_pops;
  integer credit_edges;

  reg prev_push_credit;
  reg [7:0] hold_sample;
  reg [7:0] seq_data;

  integer i;
  integer start_credit_edges;
  integer start_pops;

  cdc_fifo_flops_push_credit dut (
    .push_clk(push_clk),
    .push_rst(push_rst),
    .pop_clk(pop_clk),
    .pop_rst(pop_rst),
    .push_sender_in_reset(push_sender_in_reset),
    .push_receiver_in_reset(push_receiver_in_reset),
    .push_credit_stall(push_credit_stall),
    .push_credit(push_credit),
    .push_valid(push_valid),
    .pop_ready(pop_ready),
    .pop_valid(pop_valid),
    .push_full(push_full),
    .pop_empty(pop_empty),
    .push_data(push_data),
    .pop_data(pop_data),
    .push_slots(push_slots),
    .credit_initial_push(credit_initial_push),
    .credit_withhold_push(credit_withhold_push),
    .credit_count_push(credit_count_push),
    .credit_available_push(credit_available_push),
    .pop_items(pop_items)
  );

  initial begin
    push_clk = 1'b0;
    forever #5 push_clk = ~push_clk;
  end

  initial begin
    pop_clk = 1'b0;
    forever #7 pop_clk = ~pop_clk;
  end

  initial begin
    #200000;
    fail("simulation timeout");
  end

  always @(posedge push_clk) begin
    #1;
    if ((push_credit_stall === 1'b1) && (push_credit === 1'b1))
      fail("push_credit asserted while push_credit_stall was high");
    if ((prev_push_credit === 1'b0) && (push_credit === 1'b1))
      credit_edges = credit_edges + 1;
    prev_push_credit = push_credit;
  end

  always @(posedge pop_clk) begin
    #1;
    if ((pop_ready === 1'b1) && (pop_valid === 1'b1)) begin
      if (expected_count <= 0)
        fail("unexpected pop handshake");
      if (pop_data !== expected_q[expected_head])
        fail("pop_data did not match expected FIFO order");
      expected_head  = (expected_head + 1) % 256;
      expected_count = expected_count - 1;
      completed_pops = completed_pops + 1;
    end
  end

  task fail;
    input [1023:0] msg;
    begin
      $display("FAIL: %0s at time %0t", msg, $time);
      $finish;
    end
  endtask

  task clear_model;
    begin
      expected_head  = 0;
      expected_tail  = 0;
      expected_count = 0;
    end
  endtask

  task enqueue_model;
    input [7:0] data;
    begin
      expected_q[expected_tail] = data;
      expected_tail = (expected_tail + 1) % 256;
      expected_count = expected_count + 1;
    end
  endtask

  task wait_push_cycles;
    input integer cycles;
    integer n;
    begin
      for (n = 0; n < cycles; n = n + 1) begin
        @(posedge push_clk);
        #1;
      end
    end
  endtask

  task wait_pop_cycles;
    input integer cycles;
    integer n;
    begin
      for (n = 0; n < cycles; n = n + 1) begin
        @(posedge pop_clk);
        #1;
      end
    end
  endtask

  task pulse_push_raw;
    input [7:0] data;
    begin
      @(negedge push_clk);
      push_data  = data;
      push_valid = 1'b1;
      @(posedge push_clk);
      #1;
      @(negedge push_clk);
      push_valid = 1'b0;
      push_data  = 8'h00;
    end
  endtask

  task pulse_push_expected;
    input [7:0] data;
    begin
      pulse_push_raw(data);
      enqueue_model(data);
    end
  endtask

  task wait_until_expected_empty;
    input integer max_cycles;
    integer n;
    begin : wait_block
      for (n = 0; n < max_cycles; n = n + 1) begin
        @(posedge pop_clk);
        #1;
        if (expected_count == 0)
          disable wait_block;
      end
      fail("timed out waiting for expected queue to drain");
    end
  endtask

  task drain_expected_queue;
    begin
      @(negedge pop_clk);
      pop_ready = 1'b1;
      wait_until_expected_empty(2000);
      @(negedge pop_clk);
      pop_ready = 1'b0;
    end
  endtask

  task wait_for_new_credit_edge;
    input integer old_edges;
    input integer max_cycles;
    integer n;
    begin : wait_credit_block
      for (n = 0; n < max_cycles; n = n + 1) begin
        @(posedge push_clk);
        #1;
        if (credit_edges > old_edges)
          disable wait_credit_block;
      end
      fail("timed out waiting for push_credit activity");
    end
  endtask

  task wait_until_front_visible;
    input [7:0] expected_data;
    integer n;
    begin : visible_block
      for (n = 0; n < 2000; n = n + 1) begin
        @(posedge pop_clk);
        #1;
        if ((pop_valid === 1'b1) && (pop_data === expected_data))
          disable visible_block;
      end
      fail("timed out waiting for expected front item");
    end
  endtask

  task pop_one_expected;
    begin : pop_block
      start_pops = completed_pops;
      @(negedge pop_clk);
      pop_ready = 1'b1;
      begin : wait_pop_block
        while (completed_pops == start_pops) begin
          @(posedge pop_clk);
          #1;
        end
      end
      @(negedge pop_clk);
      pop_ready = 1'b0;
    end
  endtask

  task hold_front_then_pop;
    input [7:0] expected_data;
    input integer hold_cycles;
    integer n;
    begin
      wait_until_front_visible(expected_data);
      hold_sample = pop_data;
      if (hold_sample !== expected_data)
        fail("unexpected data visible before backpressure hold");
      @(negedge pop_clk);
      pop_ready = 1'b0;
      for (n = 0; n < hold_cycles; n = n + 1) begin
        @(posedge pop_clk);
        #1;
        if (pop_valid !== 1'b1)
          fail("pop_valid dropped while pop_ready was low");
        if (pop_data !== hold_sample)
          fail("pop_data changed while pop_ready was low");
      end
      pop_one_expected();
    end
  endtask

  task check_stable_empty;
    begin
      wait_pop_cycles(4);
      if (pop_empty !== 1'b1)
        fail("pop_empty not asserted in stable drained state");
    end
  endtask

  task check_no_extra_pop;
    input integer cycles;
    integer n;
    integer prior_pops_local;
    begin
      prior_pops_local = completed_pops;
      @(negedge pop_clk);
      pop_ready = 1'b1;
      for (n = 0; n < cycles; n = n + 1) begin
        @(posedge pop_clk);
        #1;
        if (completed_pops != prior_pops_local)
          fail("unexpected pop occurred after drain");
      end
      @(negedge pop_clk);
      pop_ready = 1'b0;
    end
  endtask

  task reset_both_idle;
    begin
      @(negedge push_clk);
      push_valid = 1'b0;
      push_data  = 8'h00;
      push_rst   = 1'b1;
      push_sender_in_reset = 1'b0;
      push_credit_stall    = 1'b0;

      @(negedge pop_clk);
      pop_ready = 1'b0;
      pop_rst   = 1'b1;

      wait_push_cycles(3);
      wait_pop_cycles(3);

      @(negedge push_clk);
      push_rst = 1'b0;

      @(negedge pop_clk);
      pop_rst = 1'b0;

      wait_push_cycles(5);
      wait_pop_cycles(5);

      clear_model();
    end
  endtask

  initial begin
    push_rst              = 1'b0;
    pop_rst               = 1'b0;
    push_sender_in_reset  = 1'b0;
    push_credit_stall     = 1'b0;
    push_valid            = 1'b0;
    pop_ready             = 1'b0;
    push_data             = 8'h00;
    credit_initial_push   = 5'd17;
    credit_withhold_push  = 5'd0;
    prev_push_credit      = 1'b0;
    completed_pops        = 0;
    credit_edges          = 0;
    clear_model();

    wait_push_cycles(2);
    wait_pop_cycles(2);

    // PUSH_RESET_IDLE_CHECKS
    reset_both_idle();
    @(negedge push_clk);
    push_rst = 1'b1;
    wait_push_cycles(2);
    pulse_push_raw(8'hE1);
    wait_push_cycles(1);
    @(negedge push_clk);
    push_rst = 1'b0;
    wait_push_cycles(5);
    pulse_push_expected(8'h21);
    pop_one_expected();
    check_no_extra_pop(4);
    check_stable_empty();

    // POP_RESET_IDLE_CHECKS
    reset_both_idle();
    @(negedge pop_clk);
    pop_rst = 1'b1;
    wait_pop_cycles(2);
    @(negedge pop_clk);
    pop_rst = 1'b0;
    wait_pop_cycles(5);
    pulse_push_expected(8'h22);
    pop_one_expected();
    check_no_extra_pop(4);
    check_stable_empty();

    // PUSH_SENDER_RESET_HANDSHAKE_CHECKS
    reset_both_idle();
    @(negedge push_clk);
    push_sender_in_reset = 1'b1;
    wait_push_cycles(2);
    pulse_push_raw(8'hE2);
    wait_push_cycles(1);
    @(negedge push_clk);
    push_sender_in_reset = 1'b0;
    wait_push_cycles(5);
    pulse_push_expected(8'h23);
    pop_one_expected();
    check_no_extra_pop(4);
    check_stable_empty();

    // SINGLE_TRANSFER_CHECKS
    reset_both_idle();
    start_credit_edges = credit_edges;
    pulse_push_expected(8'h3C);
    wait_push_cycles(12);
    if (credit_edges != start_credit_edges)
      fail("push_credit changed before any successful pop");
    pop_one_expected();
    wait_for_new_credit_edge(start_credit_edges, 600);
    check_stable_empty();

    // BACKPRESSURE_HOLD_CHECKS
    reset_both_idle();
    pulse_push_expected(8'hA5);
    hold_front_then_pop(8'hA5, 3);
    check_no_extra_pop(4);
    check_stable_empty();

    // FIFO_ORDERING_CHECKS
    reset_both_idle();
    pulse_push_expected(8'h00);
    pulse_push_expected(8'hFF);
    @(negedge pop_clk);
    pop_ready = 1'b1;
    pulse_push_expected(8'hAA);
    pulse_push_expected(8'h55);
    pulse_push_expected(8'h80);
    pulse_push_expected(8'h01);
    wait_until_expected_empty(2500);
    @(negedge pop_clk);
    pop_ready = 1'b0;
    check_no_extra_pop(4);
    check_stable_empty();

    // FILL_AND_DRAIN_CHECKS
    reset_both_idle();
    for (i = 0; i < 17; i = i + 1) begin
      seq_data = i[7:0];
      pulse_push_expected(seq_data);
    end
    wait_push_cycles(4);
    if (push_full !== 1'b1)
      fail("push_full not asserted after stable fill to 17 entries");
    pulse_push_raw(8'hEE);
    wait_push_cycles(2);
    drain_expected_queue();
    check_no_extra_pop(8);
    check_stable_empty();

    // STALL_BLOCKING_CHECKS
    reset_both_idle();
    pulse_push_expected(8'h91);
    pulse_push_expected(8'h92);
    pulse_push_expected(8'h93);
    wait_push_cycles(6);
    start_credit_edges = credit_edges;
    @(negedge push_clk);
    push_credit_stall = 1'b1;
    drain_expected_queue();
    wait_push_cycles(20);
    @(negedge push_clk);
    push_credit_stall = 1'b0;
    wait_for_new_credit_edge(start_credit_edges, 800);
    check_no_extra_pop(4);
    check_stable_empty();

    $display("PASS");
    $finish;
  end

endmodule