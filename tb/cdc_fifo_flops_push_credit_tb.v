`timescale 1ns/1ps

module tb;

  reg         push_clk;
  reg         push_rst;
  reg         pop_clk;
  reg         pop_rst;
  reg         push_sender_in_reset;
  wire        push_receiver_in_reset;
  reg         push_credit_stall;
  wire        push_credit;
  reg         push_valid;
  reg         pop_ready;
  wire        pop_valid;
  wire        push_full;
  wire        pop_empty;
  reg  [7:0]  push_data;
  wire [7:0]  pop_data;
  wire [4:0]  push_slots;
  reg  [4:0]  credit_initial_push;
  reg  [4:0]  credit_withhold_push;
  wire [4:0]  credit_count_push;
  wire [4:0]  credit_available_push;
  wire [4:0]  pop_items;

  integer errors;
  integer q_head;
  integer q_tail;
  integer q_count;
  integer i;
  integer seen_pops;
  integer hold_seen;
  reg [7:0] ref_queue [0:255];
  reg [7:0] fill_vec  [0:16];
  reg [7:0] held_data;

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

  always #5 push_clk = ~push_clk;
  always #7 pop_clk  = ~pop_clk;

  task fail;
    input [255:0] msg;
    begin
      errors = errors + 1;
      $display("FAIL: %0s @ t=%0t", msg, $time);
    end
  endtask

  task clear_inputs;
    begin
      push_rst             = 1'b0;
      pop_rst              = 1'b0;
      push_sender_in_reset = 1'b0;
      push_credit_stall    = 1'b0;
      push_valid           = 1'b0;
      pop_ready            = 1'b0;
      push_data            = 8'h00;
      credit_initial_push  = 5'd17;
      credit_withhold_push = 5'd0;
    end
  endtask

  task queue_clear;
    begin
      q_head  = 0;
      q_tail  = 0;
      q_count = 0;
    end
  endtask

  task queue_push_ref;
    input [7:0] data;
    begin
      ref_queue[q_tail] = data;
      q_tail = q_tail + 1;
      q_count = q_count + 1;
    end
  endtask

  task step_push_edges;
    input integer n;
    integer idx;
    begin
      for (idx = 0; idx < n; idx = idx + 1)
        @(posedge push_clk);
    end
  endtask

  task step_pop_edges;
    input integer n;
    integer idx;
    begin
      for (idx = 0; idx < n; idx = idx + 1)
        @(posedge pop_clk);
    end
  endtask

  task settle_both;
    input integer push_edges;
    input integer pop_edges;
    begin
      fork
        step_push_edges(push_edges);
        step_pop_edges(pop_edges);
      join
    end
  endtask

  task cold_reset_all;
    begin
      clear_inputs;
      queue_clear;
      push_rst = 1'b1;
      pop_rst  = 1'b1;
      settle_both(4, 4);
      push_rst = 1'b0;
      pop_rst  = 1'b0;
      settle_both(8, 8);
      clear_inputs;
      queue_clear;
    end
  endtask

  task push_pulse;
    input [7:0] data;
    input integer record_it;
    begin
      push_data  = data;
      push_valid = 1'b1;
      @(posedge push_clk);
      if (record_it != 0)
        queue_push_ref(data);
      push_valid = 1'b0;
      push_data  = 8'h00;
    end
  endtask

  task drain_expected;
    input integer expected_n;
    input integer max_pop_edges;
    integer idx;
    integer target;
    reg [7:0] expected_data;
    begin
      target = seen_pops + expected_n;
      pop_ready = 1'b1;
      for (idx = 0; idx < max_pop_edges; idx = idx + 1) begin
        @(posedge pop_clk);
        if (pop_valid === 1'b1) begin
          if (q_count <= 0) begin
            fail("pop occurred without queued reference data");
          end else begin
            expected_data = ref_queue[q_head];
            if (pop_data !== expected_data)
              fail("FIFO pop data/order mismatch");
            q_head = q_head + 1;
            q_count = q_count - 1;
            seen_pops = seen_pops + 1;
          end
          if (seen_pops >= target)
            idx = max_pop_edges;
        end
      end
      pop_ready = 1'b0;
      if (seen_pops < target)
        fail("missing expected pop handshakes");
    end
  endtask

  task observe_no_credit;
    input integer max_push_edges;
    input [255:0] msg;
    integer idx;
    begin
      for (idx = 0; idx < max_push_edges; idx = idx + 1) begin
        @(posedge push_clk);
        if (push_credit === 1'b1)
          fail(msg);
      end
    end
  endtask

  task observe_some_credit;
    input integer max_push_edges;
    input [255:0] msg;
    integer idx;
    integer got_one;
    begin
      got_one = 0;
      for (idx = 0; idx < max_push_edges; idx = idx + 1) begin
        @(posedge push_clk);
        if (push_credit === 1'b1)
          got_one = 1;
      end
      if (got_one == 0)
        fail(msg);
    end
  endtask

  initial begin
    push_clk = 1'b0;
    pop_clk  = 1'b0;
    errors   = 0;
    seen_pops = 0;
    hold_seen = 0;
    held_data = 8'h00;

    fill_vec[0]  = 8'h00;
    fill_vec[1]  = 8'hFF;
    fill_vec[2]  = 8'hAA;
    fill_vec[3]  = 8'h55;
    fill_vec[4]  = 8'h01;
    fill_vec[5]  = 8'h80;
    fill_vec[6]  = 8'h7F;
    fill_vec[7]  = 8'hFE;
    fill_vec[8]  = 8'h12;
    fill_vec[9]  = 8'h34;
    fill_vec[10] = 8'h56;
    fill_vec[11] = 8'h78;
    fill_vec[12] = 8'h9A;
    fill_vec[13] = 8'hBC;
    fill_vec[14] = 8'hDE;
    fill_vec[15] = 8'hE1;
    fill_vec[16] = 8'hE2;

    clear_inputs;
    queue_clear;
    settle_both(2, 2);

    // PUSH_RESET_IDLE_CHECKS
    cold_reset_all();
    push_rst = 1'b1;
    step_push_edges(2);
    push_pulse(8'h91, 0);
    push_pulse(8'h92, 0);
    observe_no_credit(20, "push_credit pulsed without any prior pop while push_rst held");
    push_rst = 1'b0;
    step_push_edges(6);
    push_pulse(8'h93, 1);
    drain_expected(1, 320);
    settle_both(12, 12);
    queue_clear;
    seen_pops = 0;

    // POP_RESET_IDLE_CHECKS
    cold_reset_all();
    for (i = 0; i < 6; i = i + 1) begin
      pop_ready = (i[0] == 1'b0);
      @(posedge pop_clk);
      if (pop_valid === 1'b1)
        fail("pop_valid asserted in long-settled empty state");
    end
    pop_ready = 1'b0;
    observe_no_credit(20, "push_credit pulsed without any prior pop during empty-side activity");
    pop_rst = 1'b1;
    step_pop_edges(3);
    pop_rst = 1'b0;
    step_pop_edges(6);
    push_pulse(8'hA5, 1);
    drain_expected(1, 320);
    settle_both(12, 12);
    queue_clear;
    seen_pops = 0;

    // PUSH_SENDER_RESET_HANDSHAKE_CHECKS
    cold_reset_all();
    push_sender_in_reset = 1'b1;
    step_push_edges(2);
    push_pulse(8'h31, 0);
    push_pulse(8'h32, 0);
    observe_no_credit(20, "push_credit pulsed without any prior pop while push_sender_in_reset held");
    push_sender_in_reset = 1'b0;
    step_push_edges(6);
    push_pulse(8'h33, 1);
    drain_expected(1, 320);
    settle_both(12, 12);
    queue_clear;
    seen_pops = 0;

    // SINGLE_TRANSFER_CHECKS
    cold_reset_all();
    push_pulse(8'hA5, 1);
    drain_expected(1, 320);
    settle_both(12, 12);
    queue_clear;
    seen_pops = 0;

    // BACKPRESSURE_HOLD_CHECKS
    cold_reset_all();
    push_pulse(8'h11, 1);
    push_pulse(8'h22, 1);
    settle_both(8, 20);
    pop_ready = 1'b0;
    push_pulse(8'h33, 1);
    push_pulse(8'h44, 1);
    hold_seen = 0;
    held_data = 8'h00;
    for (i = 0; i < 12; i = i + 1) begin
      @(posedge pop_clk);
      if (pop_valid === 1'b1) begin
        if (hold_seen == 0) begin
          held_data = pop_data;
          hold_seen = 1;
        end else if (pop_data !== held_data) begin
          fail("pop_data changed while pop_ready was low");
        end
      end
    end
    if (hold_seen == 0)
      fail("expected a held head item during backpressure window");
    drain_expected(4, 480);
    settle_both(12, 12);
    queue_clear;
    seen_pops = 0;

    // FIFO_ORDERING_CHECKS
    cold_reset_all();
    push_pulse(8'h10, 1);
    push_pulse(8'h20, 1);
    push_pulse(8'h30, 1);
    push_pulse(8'h40, 1);
    drain_expected(2, 320);
    push_pulse(8'h50, 1);
    push_pulse(8'h60, 1);
    drain_expected(4, 480);
    settle_both(12, 12);
    queue_clear;
    seen_pops = 0;

    // FILL_AND_DRAIN_CHECKS
    cold_reset_all();
    for (i = 0; i < 17; i = i + 1)
      push_pulse(fill_vec[i], 1);
    settle_both(40, 40);
    if (push_full !== 1'b1)
      fail("push_full not asserted in stable filled state");
    drain_expected(17, 1200);
    settle_both(40, 40);
    if (pop_empty !== 1'b1)
      fail("pop_empty not asserted after full drain and settle");
    for (i = 0; i < 4; i = i + 1) begin
      pop_ready = 1'b1;
      @(posedge pop_clk);
      if (pop_valid === 1'b1)
        fail("extra pop_valid observed after full drain");
    end
    pop_ready = 1'b0;
    queue_clear;
    seen_pops = 0;

    // STALL_BLOCKING_CHECKS
    cold_reset_all();
    observe_no_credit(20, "push_credit pulsed before any pop completed");
    push_pulse(8'hC1, 1);
    push_pulse(8'hC2, 1);
    push_credit_stall = 1'b1;
    drain_expected(1, 320);
    observe_no_credit(60, "push_credit pulsed while push_credit_stall was asserted");
    push_credit_stall = 1'b0;
    observe_some_credit(160, "no push_credit pulse observed after releasing stall following a completed pop");
    drain_expected(1, 320);
    observe_some_credit(160, "no push_credit pulse observed after an unstalled completed pop");
    settle_both(20, 20);

    if (errors == 0) begin
      $display("PASS");
    end else begin
      $display("FAIL with %0d errors", errors);
    end

    $finish;
  end



    // Injected guard: synchronous reset must not change registered outputs
    // until the next active clock edge.
    reg [22:0] tb_sync_reset_snapshot;
    time tb_sync_reset_last_clock_edge;

    initial tb_sync_reset_last_clock_edge = 0;

    always @(posedge push_clk or posedge pop_clk) begin
        tb_sync_reset_last_clock_edge = $time;
    end

    always @(posedge push_rst or posedge pop_rst) begin
        if (($time - tb_sync_reset_last_clock_edge) > 0) begin
            tb_sync_reset_snapshot = {push_receiver_in_reset, push_full, pop_empty, push_slots, credit_count_push, credit_available_push, pop_items};
            #1;
            if ({push_receiver_in_reset, push_full, pop_empty, push_slots, credit_count_push, credit_available_push, pop_items} !== tb_sync_reset_snapshot) begin
                $display("FAIL: synchronous reset changed registered outputs before clock edge at %0t", $time);
                $finish;
            end
        end
    end

endmodule