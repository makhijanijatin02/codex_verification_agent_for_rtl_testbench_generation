`timescale 1ns/1ps

module tb;

  reg         clk;
  reg         rst;
  reg         in_valid;
  reg  [3:0]  in;
  wire [14:0] out;

  integer errors;
  integer i;
  integer j;
  integer rand_in;
  integer rand_valid;
  integer rand_rst;
  reg [14:0] expected;

  enc_bin2onehot dut (
    .clk(clk),
    .rst(rst),
    .in_valid(in_valid),
    .in(in),
    .out(out)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  function [14:0] onehot15;
    input [3:0] idx;
    begin
      onehot15 = 15'b0;
      if (idx < 15)
        onehot15[idx] = 1'b1;
    end
  endfunction

  function integer popcount15;
    input [14:0] val;
    integer k;
    begin
      popcount15 = 0;
      for (k = 0; k < 15; k = k + 1)
        if (val[k] === 1'b1)
          popcount15 = popcount15 + 1;
    end
  endfunction

  task fail;
    input [1023:0] msg;
    begin
      errors = errors + 1;
      $display("FAIL: %0s", msg);
    end
  endtask

  task check_defined_case;
    input [3:0] t_in;
    input       t_valid;
    input [1023:0] label;
    reg [14:0] exp;
    begin
      in = t_in;
      in_valid = t_valid;
      #1;

      exp = t_valid ? onehot15(t_in) : 15'b0;

      if (out !== exp) begin
        $display("Context: %0s", label);
        $display("  in_valid=%0b in=%0d out=%015b expected=%015b", t_valid, t_in, out, exp);
        fail("output mismatch");
      end

      if (t_valid && (t_in <= 4'd14)) begin
        if (popcount15(out) != 1) begin
          $display("Context: %0s", label);
          $display("  in_valid=%0b in=%0d out=%015b", t_valid, t_in, out);
          fail("valid decode is not exactly one-hot");
        end
        if (out[t_in] !== 1'b1) begin
          $display("Context: %0s", label);
          $display("  in_valid=%0b in=%0d out=%015b", t_valid, t_in, out);
          fail("decoded bit index is incorrect");
        end
      end

      if (!t_valid && out !== 15'b0) begin
        $display("Context: %0s", label);
        $display("  in_valid=%0b in=%0d out=%015b", t_valid, t_in, out);
        fail("output not zero while in_valid is low");
      end
    end
  endtask

  task check_no_strict_undefined;
    input [3:0] t_in;
    input       t_valid;
    input [1023:0] label;
    begin
      in = t_in;
      in_valid = t_valid;
      #1;
      $display("INFO: undefined case observed (%0s): in_valid=%0b in=%0d out=%015b", label, t_valid, t_in, out);
    end
  endtask

  task check_stable_over_aux_toggles;
    input [3:0] t_in;
    input       t_valid;
    input [1023:0] label;
    reg [14:0] baseline;
    integer m;
    begin
      in = t_in;
      in_valid = t_valid;
      #1;
      baseline = out;

      for (m = 0; m < 6; m = m + 1) begin
        rst = ~rst;
        #1;
        if (out !== baseline) begin
          $display("Context: %0s", label);
          $display("  rst toggle changed out: in_valid=%0b in=%0d baseline=%015b out=%015b", t_valid, t_in, baseline, out);
          fail("rst affected combinational output");
        end

        @(posedge clk);
        #1;
        if (out !== baseline) begin
          $display("Context: %0s", label);
          $display("  clk posedge changed out: in_valid=%0b in=%0d baseline=%015b out=%015b", t_valid, t_in, baseline, out);
          fail("clk affected combinational output");
        end

        @(negedge clk);
        #1;
        if (out !== baseline) begin
          $display("Context: %0s", label);
          $display("  clk negedge changed out: in_valid=%0b in=%0d baseline=%015b out=%015b", t_valid, t_in, baseline, out);
          fail("clk affected combinational output");
        end
      end
    end
  endtask

  initial begin
    errors   = 0;
    rst      = 1'b0;
    in_valid = 1'b0;
    in       = 4'd0;

    #1;

    for (i = 0; i <= 14; i = i + 1)
      check_defined_case(i[3:0], 1'b1, "exhaustive valid decode");

    for (i = 0; i <= 15; i = i + 1)
      check_defined_case(i[3:0], 1'b0, "exhaustive invalid gating");

    check_defined_case(4'd0,  1'b1, "boundary input 0");
    check_defined_case(4'd14, 1'b1, "boundary input 14");

    check_defined_case(4'd14, 1'b1, "pre-undefined defined case");
    check_no_strict_undefined(4'd15, 1'b1, "undefined input 15 with in_valid=1");
    check_defined_case(4'd15, 1'b0, "post-undefined invalid gating at 15");
    check_defined_case(4'd0,  1'b1, "post-undefined recovery to input 0");

    check_defined_case(4'd5,  1'b1, "alternating pattern 5");
    check_defined_case(4'd10, 1'b1, "alternating pattern 10");
    check_defined_case(4'd6,  1'b1, "alternating pattern 6");
    check_defined_case(4'd9,  1'b1, "alternating pattern 9");

    in_valid = 1'b1;
    in = 4'd2;
    #1;
    expected = onehot15(4'd2);
    if (out !== expected) fail("sequence step 2 mismatch");

    in = 4'd3;
    #1;
    expected = onehot15(4'd3);
    if (out !== expected) fail("sequence step 3 mismatch");

    in = 4'd7;
    #1;
    expected = onehot15(4'd7);
    if (out !== expected) fail("sequence step 7 mismatch");

    in = 4'd14;
    #1;
    expected = onehot15(4'd14);
    if (out !== expected) fail("sequence step 14 mismatch");

    in_valid = 1'b0;
    #1;
    if (out !== 15'b0) fail("in_valid drop did not force zero");

    in_valid = 1'b1;
    #1;
    expected = onehot15(4'd14);
    if (out !== expected) fail("in_valid reassert did not restore decode");

    in_valid = 1'b1; in = 4'd3;  #1;
    if (out !== onehot15(4'd3))  fail("temporal sequence step (1,3) mismatch");
    in_valid = 1'b1; in = 4'd12; #1;
    if (out !== onehot15(4'd12)) fail("temporal sequence step (1,12) mismatch");
    in_valid = 1'b0; in = 4'd12; #1;
    if (out !== 15'b0)           fail("temporal sequence step (0,12) mismatch");
    in_valid = 1'b1; in = 4'd4;  #1;
    if (out !== onehot15(4'd4))  fail("temporal sequence step (1,4) mismatch");
    in_valid = 1'b1; in = 4'd14; #1;
    if (out !== onehot15(4'd14)) fail("temporal sequence step (1,14) mismatch");

    in_valid = 1'b1; in = 4'd1;  #1;
    if (out !== onehot15(4'd1))  fail("back-to-back step 1 mismatch");
    in = 4'd14; #1;
    if (out !== onehot15(4'd14)) fail("back-to-back step 14 mismatch");
    in = 4'd2; #1;
    if (out !== onehot15(4'd2))  fail("back-to-back step 2 mismatch");
    in = 4'd13; #1;
    if (out !== onehot15(4'd13)) fail("back-to-back step 13 mismatch");
    in_valid = 1'b0; #1;
    if (out !== 15'b0)           fail("back-to-back drop valid mismatch");
    in_valid = 1'b1; #1;
    if (out !== onehot15(4'd13)) fail("back-to-back reassert valid mismatch");

    rst = 1'b1;
    in_valid = 1'b0;
    in = 4'd0;  #1; if (out !== 15'b0) fail("reset test invalid case in=0");
    in = 4'd7;  #1; if (out !== 15'b0) fail("reset test invalid case in=7");
    in = 4'd14; #1; if (out !== 15'b0) fail("reset test invalid case in=14");
    in = 4'd15; #1; if (out !== 15'b0) fail("reset test invalid case in=15");
    @(posedge clk);
    @(posedge clk);

    in_valid = 1'b1;
    in = 4'd0;  #1; if (out !== onehot15(4'd0))  fail("reset asserted valid case in=0");
    in = 4'd1;  #1; if (out !== onehot15(4'd1))  fail("reset asserted valid case in=1");
    in = 4'd7;  #1; if (out !== onehot15(4'd7))  fail("reset asserted valid case in=7");
    in = 4'd14; #1; if (out !== onehot15(4'd14)) fail("reset asserted valid case in=14");
    @(posedge clk);
    @(posedge clk);

    in_valid = 1'b1;
    in = 4'd4;
    rst = 1'b0; #1; if (out !== onehot15(4'd4)) fail("rst toggle low for in=4");
    rst = 1'b1; #1; if (out !== onehot15(4'd4)) fail("rst toggle high for in=4");
    rst = 1'b0; #1; if (out !== onehot15(4'd4)) fail("rst toggle low again for in=4");

    in = 4'd10;
    rst = 1'b0; #1; if (out !== onehot15(4'd10)) fail("rst toggle low for in=10");
    rst = 1'b1; #1; if (out !== onehot15(4'd10)) fail("rst toggle high for in=10");
    rst = 1'b0; #1; if (out !== onehot15(4'd10)) fail("rst toggle low again for in=10");

    check_stable_over_aux_toggles(4'd1,  1'b1, "aux independence with input 1");
    check_stable_over_aux_toggles(4'd8,  1'b1, "aux independence with input 8");
    check_stable_over_aux_toggles(4'd13, 1'b1, "aux independence with input 13");
    check_stable_over_aux_toggles(4'd2,  1'b1, "hold across edges valid");
    check_stable_over_aux_toggles(4'd2,  1'b0, "hold across edges invalid");
    check_stable_over_aux_toggles(4'd11, 1'b1, "hold across edges valid 11");

    for (j = 0; j < 100; j = j + 1) begin
      rand_in    = $random;
      rand_valid = $random;
      rand_rst   = $random;

      in       = rand_in[3:0];
      in_valid = rand_valid[0];
      rst      = rand_rst[0];
      #1;

      if (!in_valid) begin
        if (out !== 15'b0) begin
          $display("Random step %0d: in_valid=0 in=%0d rst=%0b out=%015b", j, in, rst, out);
          fail("random invalid gating failure");
        end
      end else if (in <= 4'd14) begin
        expected = onehot15(in);
        if (out !== expected) begin
          $display("Random step %0d: in_valid=1 in=%0d rst=%0b out=%015b expected=%015b", j, in, rst, out, expected);
          fail("random valid decode failure");
        end
        if (popcount15(out) != 1) begin
          $display("Random step %0d: in_valid=1 in=%0d rst=%0b out=%015b", j, in, rst, out);
          fail("random valid decode not one-hot");
        end
      end
    end

    if (errors == 0)
      $display("PASS");

    $finish;
  end

endmodule