`timescale 1ns/1ps

module tb;

  reg        clk;
  reg        rst;
  reg        push_valid;
  wire       push_ready;
  reg  [7:0] push_data;
  reg        pop_ready;
  wire       pop_valid;
  wire [7:0] pop_data;
  wire       full;
  wire       full_next;
  wire       empty;
  wire       empty_next;
  wire [3:0] slots;
  wire [3:0] slots_next;
  wire [3:0] items;
  wire [3:0] items_next;

  integer errors;
  integer i;
  integer j;
  integer model_count;
  reg [7:0] model_q [0:15];

  fifo_flops dut (
    .clk(clk),
    .rst(rst),
    .push_ready(push_ready),
    .push_valid(push_valid),
    .pop_ready(pop_ready),
    .pop_valid(pop_valid),
    .full(full),
    .full_next(full_next),
    .empty(empty),
    .empty_next(empty_next),
    .push_data(push_data),
    .pop_data(pop_data),
    .slots(slots),
    .slots_next(slots_next),
    .items(items),
    .items_next(items_next)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task fail;
    input [255:0] msg;
    begin
      errors = errors + 1;
      $display("FAIL: %0s", msg);
    end
  endtask

  task check1;
    input actual;
    input expected;
    input [255:0] msg;
    begin
      if (actual !== expected) begin
        fail(msg);
        $display("  expected=%0b actual=%0b", expected, actual);
      end
    end
  endtask

  task check4;
    input [3:0] actual;
    input [3:0] expected;
    input [255:0] msg;
    begin
      if (actual !== expected) begin
        fail(msg);
        $display("  expected=%0d actual=%0d", expected, actual);
      end
    end
  endtask

  task check8;
    input [7:0] actual;
    input [7:0] expected;
    input [255:0] msg;
    begin
      if (actual !== expected) begin
        fail(msg);
        $display("  expected=0x%02x actual=0x%02x", expected, actual);
      end
    end
  endtask

  task model_reset;
    begin
      model_count = 0;
      for (j = 0; j < 16; j = j + 1)
        model_q[j] = 8'h00;
    end
  endtask

  task model_push;
    input [7:0] d;
    begin
      model_q[model_count] = d;
      model_count = model_count + 1;
    end
  endtask

  task model_pop;
    begin
      for (j = 0; j < 15; j = j + 1)
        model_q[j] = model_q[j + 1];
      model_q[15] = 8'h00;
      model_count = model_count - 1;
    end
  endtask

  task store_byte;
    input [7:0] d;
    input       update_model;
    begin
      @(negedge clk);
      rst = 1'b0;
      push_valid = 1'b1;
      push_data = d;
      pop_ready = 1'b0;
      #1;
      @(posedge clk);
      if (update_model)
        model_push(d);
      #1;
      push_valid = 1'b0;
      #1;
    end
  endtask

  task pop_expect;
    input [7:0] expected;
    input       check_following_head;
    input [7:0] following_head;
    begin
      @(negedge clk);
      rst = 1'b0;
      push_valid = 1'b0;
      pop_ready = 1'b1;
      #1;
      check1(pop_valid, 1'b1, "buffered pop must be valid");
      check8(pop_data, expected, "buffered pop must show current head");
      @(posedge clk);
      model_pop;
      #1;
      pop_ready = 1'b0;
      #1;
      if (check_following_head) begin
        check1(pop_valid, 1'b1, "next buffered item must be valid on following cycle");
        check8(pop_data, following_head, "next buffered item must appear on following cycle");
      end
    end
  endtask

  initial begin
    errors = 0;
    rst = 1'b0;
    push_valid = 1'b0;
    push_data = 8'h00;
    pop_ready = 1'b0;
    model_reset();

    // RESET_IDLE_CHECKS
    @(negedge clk);
    rst = 1'b1;
    push_valid = 1'b0;
    pop_ready = 1'b0;
    push_data = 8'h00;
    #1;
    @(posedge clk);
    #1;
    check1(empty, 1'b1, "reset idle: empty");
    check1(full, 1'b0, "reset idle: full");
    check4(items, 4'd0, "reset idle: items");
    check4(slots, 4'd13, "reset idle: slots");
    check1(pop_valid, 1'b0, "reset idle: pop_valid");
    check1(push_ready, 1'b1, "reset idle: push_ready");
    @(negedge clk);
    rst = 1'b0;
    push_valid = 1'b0;
    pop_ready = 1'b0;
    #1;

    // EMPTY_BYPASS_CHECKS
    check1(empty, 1'b1, "empty bypass precondition: empty");
    check4(items, 4'd0, "empty bypass precondition: items");
    check4(slots, 4'd13, "empty bypass precondition: slots");
    push_valid = 1'b1;
    push_data = 8'h5A;
    pop_ready = 1'b1;
    #1;
    check1(pop_valid, 1'b1, "empty bypass: pop_valid");
    check8(pop_data, 8'h5A, "empty bypass: pop_data");
    @(posedge clk);
    #1;
    push_valid = 1'b0;
    pop_ready = 1'b0;
    #1;
    check1(empty, 1'b1, "empty bypass post-edge: empty");
    check1(full, 1'b0, "empty bypass post-edge: full");
    check4(items, 4'd0, "empty bypass post-edge: items");
    check4(slots, 4'd13, "empty bypass post-edge: slots");

    // ONE_ITEM_STORE_AND_IDLE_CHECKS
    @(negedge clk);
    push_valid = 1'b1;
    push_data = 8'hAA;
    pop_ready = 1'b0;
    #1;
    @(posedge clk);
    #1;
    push_valid = 1'b0;
    pop_ready = 1'b0;
    #1;
    check1(empty, 1'b0, "one-item idle: empty");
    check1(full, 1'b0, "one-item idle: full");
    check4(items, 4'd1, "one-item idle: items");
    check4(slots, 4'd12, "one-item idle: slots");
    check1(pop_valid, 1'b1, "one-item idle: pop_valid");
    check8(pop_data, 8'hAA, "one-item idle: pop_data");
    check1(push_ready, 1'b1, "one-item idle: push_ready");
    check1(empty_next, 1'b0, "one-item idle next: empty_next");
    check1(full_next, 1'b0, "one-item idle next: full_next");
    check4(items_next, 4'd1, "one-item idle next: items_next");
    check4(slots_next, 4'd12, "one-item idle next: slots_next");

    // ONE_ITEM_POP_NEXT_CHECKS
    @(negedge clk);
    push_valid = 1'b0;
    pop_ready = 1'b1;
    #1;
    check1(empty_next, 1'b1, "one-item pop next: empty_next");
    check1(full_next, 1'b0, "one-item pop next: full_next");
    check4(items_next, 4'd0, "one-item pop next: items_next");
    check4(slots_next, 4'd13, "one-item pop next: slots_next");
    check1(pop_valid, 1'b1, "one-item pop handshake: pop_valid");
    check8(pop_data, 8'hAA, "one-item pop handshake: pop_data");
    @(posedge clk);
    #1;
    pop_ready = 1'b0;
    #1;
    check1(empty, 1'b1, "one-item pop post-edge: empty");
    check1(full, 1'b0, "one-item pop post-edge: full");
    check4(items, 4'd0, "one-item pop post-edge: items");
    check4(slots, 4'd13, "one-item pop post-edge: slots");
    check1(pop_valid, 1'b0, "one-item pop post-edge: pop_valid");
    check1(push_ready, 1'b1, "one-item pop post-edge: push_ready");

    // BUFFERED_ORDERING_CHECKS
    model_reset();
    store_byte(8'h10, 1'b1);
    store_byte(8'h20, 1'b1);
    store_byte(8'h30, 1'b1);

    @(negedge clk);
    push_valid = 1'b1;
    push_data = 8'h40;
    pop_ready = 1'b1;
    #1;
    check1(pop_valid, 1'b1, "simultaneous buffered push+pop: pop_valid");
    check8(pop_data, 8'h10, "simultaneous buffered push+pop: old head");
    @(posedge clk);
    model_pop();
    model_push(8'h40);
    #1;
    push_valid = 1'b0;
    pop_ready = 1'b0;
    #1;
    check4(items, 4'd3, "simultaneous buffered push+pop: occupancy unchanged");
    check1(pop_valid, 1'b1, "simultaneous buffered push+pop: next head valid");
    check8(pop_data, 8'h20, "simultaneous buffered push+pop: next head data");

    pop_expect(8'h20, 1'b1, 8'h30);
    pop_expect(8'h30, 1'b1, 8'h40);
    pop_expect(8'h40, 1'b0, 8'h00);
    check4(items, 4'd0, "buffered ordering drain complete: items");
    check4(slots, 4'd13, "buffered ordering drain complete: slots");
    check1(empty, 1'b1, "buffered ordering drain complete: empty");
    check1(pop_valid, 1'b0, "buffered ordering drain complete: pop_valid");

    // TWELVE_TO_THIRTEEN_NEXT_CHECKS
    model_reset();
    for (i = 0; i < 12; i = i + 1)
      store_byte(8'h80 + i[7:0], 1'b1);

    @(negedge clk);
    push_valid = 1'b1;
    push_data = 8'hE1;
    pop_ready = 1'b0;
    #1;
    check1(full_next, 1'b1, "twelve-to-thirteen: full_next");
    check4(items_next, 4'd13, "twelve-to-thirteen: items_next");
    @(posedge clk);
    model_push(8'hE1);
    #1;
    push_valid = 1'b0;
    pop_ready = 1'b0;
    #1;

    // FULL_IDLE_CHECKS
    check1(empty, 1'b0, "full idle: empty");
    check1(full, 1'b1, "full idle: full");
    check4(items, 4'd13, "full idle: items");
    check4(slots, 4'd0, "full idle: slots");
    check1(pop_valid, 1'b1, "full idle: pop_valid");
    check1(push_ready, 1'b0, "full idle: push_ready");

    @(negedge clk);
    push_valid = 1'b1;
    push_data = 8'hFE;
    pop_ready = 1'b0;
    #1;
    check1(full, 1'b1, "full blocked push: full remains asserted");
    check1(push_ready, 1'b0, "full blocked push: push_ready deasserted");
    check1(pop_valid, 1'b1, "full blocked push: head remains valid");
    check8(pop_data, model_q[0], "full blocked push: head remains unchanged");
    @(posedge clk);
    #1;
    push_valid = 1'b0;
    pop_ready = 1'b0;
    #1;
    check4(items, 4'd13, "full blocked push post-edge: items unchanged");
    check4(slots, 4'd0, "full blocked push post-edge: slots unchanged");

    for (i = 0; i < 12; i = i + 1)
      pop_expect(model_q[0], 1'b1, model_q[1]);
    pop_expect(model_q[0], 1'b0, 8'h00);

    check1(empty, 1'b1, "final empty: empty");
    check1(full, 1'b0, "final empty: full");
    check4(items, 4'd0, "final empty: items");
    check4(slots, 4'd13, "final empty: slots");
    check1(pop_valid, 1'b0, "final empty: pop_valid");
    check1(push_ready, 1'b1, "final empty: push_ready");

    if (errors == 0)
      $display("PASS");
    else
      $display("FAIL");

    $finish;
  end

endmodule