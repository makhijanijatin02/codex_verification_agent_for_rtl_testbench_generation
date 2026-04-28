`timescale 1ns/1ps

module tb;

  reg clk;
  reg rst;
  reg reinit;
  reg advance;
  reg [4:0] initial_state;
  reg [4:0] taps;
  wire out;
  wire [4:0] out_state;

  reg [4:0] ref_state;
  integer error_count;
  integer seed;
  integer trial;
  integer step;
  integer seq_len;
  integer sel;
  reg [31:0] randv;
  reg [4:0] rand_init;
  reg [4:0] rand_taps;
  reg rand_rst;
  reg rand_reinit;
  reg rand_advance;

  lfsr dut (
    .clk(clk),
    .rst(rst),
    .reinit(reinit),
    .advance(advance),
    .out(out),
    .initial_state(initial_state),
    .taps(taps),
    .out_state(out_state)
  );

  function [4:0] lfsr_next;
    input [4:0] state_in;
    input [4:0] taps_in;
    reg feedback_bit;
    begin
      feedback_bit = ^(state_in & taps_in);
      lfsr_next = {state_in[3:0], feedback_bit};
    end
  endfunction

  task fail_mismatch;
    input [8*120-1:0] testname;
    input [4:0] expected_state;
    begin
      error_count = error_count + 1;
      $display("FAIL: %0s time=%0t rst=%b reinit=%b advance=%b initial_state=%b taps=%b expected_state=%b got_state=%b expected_out=%b got_out=%b",
               testname, $time, rst, reinit, advance, initial_state, taps,
               expected_state, out_state, expected_state[0], out);
    end
  endtask

  task fail_relation;
    input [8*120-1:0] testname;
    begin
      error_count = error_count + 1;
      $display("FAIL: %0s time=%0t out must equal out_state[0], got out=%b out_state=%b",
               testname, $time, out, out_state);
    end
  endtask

  task check_outputs;
    input [8*120-1:0] testname;
    input [4:0] expected_state;
    begin
      #1;
      if (out_state !== expected_state) begin
        fail_mismatch(testname, expected_state);
      end
      if (out !== expected_state[0]) begin
        fail_mismatch(testname, expected_state);
      end
      if (out !== out_state[0]) begin
        fail_relation(testname);
      end
    end
  endtask

  task apply_cycle;
    input cycle_rst;
    input cycle_reinit;
    input cycle_advance;
    input [4:0] cycle_initial_state;
    input [4:0] cycle_taps;
    input [8*120-1:0] testname;
    begin
      @(negedge clk);
      rst = cycle_rst;
      reinit = cycle_reinit;
      advance = cycle_advance;
      initial_state = cycle_initial_state;
      taps = cycle_taps;

      @(posedge clk);
      if (cycle_rst) begin
        ref_state = cycle_initial_state;
      end else if (cycle_reinit) begin
        ref_state = cycle_initial_state;
      end else if (cycle_advance) begin
        ref_state = lfsr_next(ref_state, cycle_taps);
      end
      check_outputs(testname, ref_state);
    end
  endtask

  task midcycle_no_change;
    input glitch_rst;
    input glitch_reinit;
    input glitch_advance;
    input [4:0] glitch_initial_state;
    input [4:0] glitch_taps;
    input [8*120-1:0] testname;
    begin
      rst = glitch_rst;
      reinit = glitch_reinit;
      advance = glitch_advance;
      initial_state = glitch_initial_state;
      taps = glitch_taps;
      #1;
      check_outputs(testname, ref_state);
    end
  endtask

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    rst = 1'b0;
    reinit = 1'b0;
    advance = 1'b0;
    initial_state = 5'b00000;
    taps = 5'b00000;
    ref_state = 5'b00000;
    error_count = 0;
    seed = 32'h13579BDF;

    #2;

    apply_cycle(1'b1, 1'b0, 1'b0, 5'b00000, 5'b10101, "reset load zero seed");
    apply_cycle(1'b1, 1'b0, 1'b0, 5'b11111, 5'b00000, "reset load all ones seed");
    apply_cycle(1'b1, 1'b0, 1'b0, 5'b10101, 5'b11111, "reset load alternating seed");
    apply_cycle(1'b1, 1'b0, 1'b0, 5'b00001, 5'b01010, "reset load single hot seed");

    apply_cycle(1'b1, 1'b0, 1'b0, 5'b10110, 5'b10010, "basic trace load");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b10110, 5'b10010, "basic trace advance 1");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b10110, 5'b10010, "basic trace advance 2");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b10110, 5'b10010, "basic trace advance 3");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b10110, 5'b10010, "basic trace advance 4");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b10110, 5'b10010, "basic trace advance 5");

    apply_cycle(1'b1, 1'b0, 1'b0, 5'b11001, 5'b10110, "hold test load");
    apply_cycle(1'b0, 1'b0, 1'b0, 5'b00111, 5'b01001, "hold cycle 1");
    apply_cycle(1'b0, 1'b0, 1'b0, 5'b11111, 5'b11111, "hold cycle 2");
    apply_cycle(1'b0, 1'b0, 1'b0, 5'b00000, 5'b00000, "hold cycle 3");

    apply_cycle(1'b1, 1'b0, 1'b0, 5'b10110, 5'b10010, "sync reset timing setup load");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b10110, 5'b10010, "sync reset timing setup advance");
    @(negedge clk);
    rst = 1'b1;
    reinit = 1'b0;
    advance = 1'b0;
    initial_state = 5'b00101;
    taps = 5'b11111;
    #1;
    check_outputs("rst asserted between edges must not act asynchronously", ref_state);
    @(posedge clk);
    ref_state = 5'b00101;
    check_outputs("rst must load on posedge only", ref_state);

    apply_cycle(1'b1, 1'b0, 1'b0, 5'b11100, 5'b11111, "reinit setup load");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b11100, 5'b11111, "reinit setup advance");
    apply_cycle(1'b0, 1'b1, 1'b0, 5'b10001, 5'b11100, "reinit reloads initial_state");

    apply_cycle(1'b1, 1'b0, 1'b0, 5'b10011, 5'b00101, "priority sequence load");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b10011, 5'b00101, "priority sequence first advance");
    apply_cycle(1'b0, 1'b1, 1'b1, 5'b10011, 5'b00101, "reinit must beat advance");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b10011, 5'b00101, "advance after reinit");
    apply_cycle(1'b1, 1'b1, 1'b1, 5'b01011, 5'b11101, "rst must beat reinit and advance");

    apply_cycle(1'b1, 1'b0, 1'b0, 5'b11111, 5'b00000, "zero taps trace load");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b11111, 5'b00000, "zero taps trace 1");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b11111, 5'b00000, "zero taps trace 2");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b11111, 5'b00000, "zero taps trace 3");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b11111, 5'b00000, "zero taps trace 4");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b11111, 5'b00000, "zero taps trace 5");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b11111, 5'b00000, "zero taps trace 6");

    apply_cycle(1'b1, 1'b0, 1'b0, 5'b00000, 5'b11111, "zero seed absorbing load");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b00000, 5'b11111, "zero seed advance with taps 11111");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b00000, 5'b00101, "zero seed advance with taps 00101");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b00000, 5'b00000, "zero seed advance with taps 00000");

    apply_cycle(1'b1, 1'b0, 1'b0, 5'b10001, 5'b00001, "shift direction discriminator load");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b10001, 5'b00001, "shift direction discriminator advance");

    apply_cycle(1'b1, 1'b0, 1'b0, 5'b10101, 5'b00111, "tap alignment discriminator load");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b10101, 5'b00111, "tap alignment discriminator advance");

    apply_cycle(1'b1, 1'b0, 1'b0, 5'b11010, 5'b10101, "interleaved sequence load");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b11010, 5'b10101, "interleaved sequence advance 1");
    apply_cycle(1'b0, 1'b0, 1'b0, 5'b00000, 5'b11111, "interleaved sequence hold 1");
    apply_cycle(1'b0, 1'b0, 1'b0, 5'b00101, 5'b00000, "interleaved sequence hold 2");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b11010, 5'b10101, "interleaved sequence advance 2");
    apply_cycle(1'b0, 1'b1, 1'b0, 5'b11010, 5'b10101, "interleaved sequence reinit");
    apply_cycle(1'b0, 1'b0, 1'b0, 5'b11111, 5'b01010, "interleaved sequence hold 3");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b11010, 5'b10101, "interleaved sequence advance 3");

    apply_cycle(1'b1, 1'b0, 1'b0, 5'b01011, 5'b00110, "control timing load");
    #1;
    advance = 1'b1;
    rst = 1'b0;
    reinit = 1'b0;
    initial_state = 5'b11111;
    taps = 5'b00110;
    #1;
    check_outputs("advance asserted after posedge must wait for next posedge", ref_state);
    @(posedge clk);
    ref_state = lfsr_next(ref_state, taps);
    check_outputs("advance sampled on next posedge only", ref_state);

    @(negedge clk);
    rst = 1'b0;
    reinit = 1'b1;
    advance = 1'b1;
    initial_state = 5'b10100;
    taps = 5'b11111;
    #1;
    check_outputs("reinit asserted near negedge must not act immediately", ref_state);
    @(posedge clk);
    ref_state = 5'b10100;
    check_outputs("reinit sampled on posedge after negedge change", ref_state);

    apply_cycle(1'b1, 1'b0, 1'b0, 5'b01111, 5'b11101, "out relation load");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b01111, 5'b11101, "out relation advance 1");
    apply_cycle(1'b0, 1'b0, 1'b1, 5'b01111, 5'b11101, "out relation advance 2");
    apply_cycle(1'b0, 1'b0, 1'b0, 5'b00000, 5'b00000, "out relation hold");

    for (trial = 0; trial < 20; trial = trial + 1) begin
      randv = $random(seed);
      case (trial % 6)
        0: rand_init = 5'b00000;
        1: rand_init = 5'b11111;
        2: rand_init = 5'b10101;
        3: rand_init = 5'b01010;
        4: rand_init = 5'b00001;
        default: rand_init = randv[4:0];
      endcase

      randv = $random(seed);
      case ((trial + 2) % 6)
        0: rand_taps = 5'b00000;
        1: rand_taps = 5'b11111;
        2: rand_taps = 5'b00101;
        3: rand_taps = 5'b10010;
        4: rand_taps = 5'b01010;
        default: rand_taps = randv[9:5];
      endcase

      apply_cycle(1'b1, 1'b0, 1'b0, rand_init, rand_taps, "random trial reset load");

      seq_len = 5 + (($random(seed)) & 7);
      for (step = 0; step < seq_len; step = step + 1) begin
        randv = $random(seed);
        sel = randv & 7;
        case (sel)
          0: begin rand_rst = 1'b1; rand_reinit = 1'b1; rand_advance = 1'b1; end
          1: begin rand_rst = 1'b0; rand_reinit = 1'b1; rand_advance = 1'b1; end
          2: begin rand_rst = 1'b0; rand_reinit = 1'b0; rand_advance = 1'b0; end
          3: begin rand_rst = 1'b0; rand_reinit = 1'b0; rand_advance = 1'b1; end
          4: begin rand_rst = 1'b1; rand_reinit = 1'b0; rand_advance = 1'b0; end
          5: begin rand_rst = 1'b0; rand_reinit = 1'b1; rand_advance = 1'b0; end
          6: begin rand_rst = randv[0]; rand_reinit = randv[1]; rand_advance = randv[2]; end
          default: begin rand_rst = 1'b0; rand_reinit = randv[3]; rand_advance = randv[4]; end
        endcase

        randv = $random(seed);
        case (randv & 7)
          0: rand_init = 5'b00000;
          1: rand_init = 5'b11111;
          2: rand_init = 5'b10101;
          3: rand_init = 5'b01010;
          4: rand_init = 5'b10000;
          5: rand_init = 5'b00001;
          default: rand_init = randv[4:0];
        endcase

        randv = $random(seed);
        case (randv & 7)
          0: rand_taps = 5'b00000;
          1: rand_taps = 5'b11111;
          2: rand_taps = 5'b00111;
          3: rand_taps = 5'b10010;
          4: rand_taps = 5'b10101;
          5: rand_taps = 5'b01010;
          default: rand_taps = randv[9:5];
        endcase

        if (($random(seed) & 3) == 0) begin
          midcycle_no_change(($random(seed) & 1),
                             ($random(seed) & 1),
                             ($random(seed) & 1),
                             $random(seed),
                             $random(seed),
                             "midcycle glitch must not change state");
        end

        apply_cycle(rand_rst, rand_reinit, rand_advance, rand_init, rand_taps, "random cycle");
      end
    end

    if (error_count == 0) begin
      $display("PASS");
    end else begin
      $display("FAIL: %0d mismatches detected", error_count);
    end
    $finish;
  end



    // Injected guard: synchronous reset must not change registered outputs
    // until the next active clock edge.
    reg [4:0] tb_sync_reset_snapshot;
    time tb_sync_reset_last_clock_edge;

    initial tb_sync_reset_last_clock_edge = 0;

    always @(posedge clk) begin
        tb_sync_reset_last_clock_edge = $time;
    end

    always @(posedge rst) begin
        if (($time - tb_sync_reset_last_clock_edge) > 0) begin
            tb_sync_reset_snapshot = out_state;
            #1;
            if (out_state !== tb_sync_reset_snapshot) begin
                $display("FAIL: synchronous reset changed registered outputs before clock edge at %0t", $time);
                $finish;
            end
        end
    end

endmodule