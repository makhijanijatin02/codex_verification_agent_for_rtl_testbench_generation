`timescale 1ns/1ps

module tb;

  reg  [9:0] bin;
  wire [9:0] gray;

  integer errors;
  integer i;
  integer j;
  integer rand_val;
  reg [9:0] prev_gray;
  reg [9:0] curr_gray;

  enc_bin2gray dut (
    .bin(bin),
    .gray(gray)
  );

  function [9:0] golden_gray;
    input [9:0] v;
    begin
      golden_gray = v ^ (v >> 1);
    end
  endfunction

  function integer popcount10;
    input [9:0] v;
    integer k;
    begin
      popcount10 = 0;
      for (k = 0; k < 10; k = k + 1) begin
        popcount10 = popcount10 + v[k];
      end
    end
  endfunction

  task check_vector;
    input [9:0] stimulus;
    reg   [9:0] expected;
    begin
      bin = stimulus;
      #1;
      expected = golden_gray(stimulus);

      if (gray !== expected) begin
        $display("FAIL: bin=%010b expected gray=%010b got=%010b at time %0t",
                 stimulus, expected, gray, $time);
        errors = errors + 1;
      end

      if (gray[9] !== stimulus[9]) begin
        $display("FAIL: MSB copy violation for bin=%010b expected gray[9]=%b got=%b at time %0t",
                 stimulus, stimulus[9], gray[9], $time);
        errors = errors + 1;
      end

      for (j = 0; j < 9; j = j + 1) begin
        if (gray[j] !== (stimulus[j+1] ^ stimulus[j])) begin
          $display("FAIL: bit %0d violation for bin=%010b expected gray[%0d]=%b got=%b at time %0t",
                   j, stimulus, j, (stimulus[j+1] ^ stimulus[j]), gray[j], $time);
          errors = errors + 1;
        end
      end
    end
  endtask

  initial begin
    errors = 0;
    bin = 10'b0000000000;

    check_vector(10'b0000000000);
    check_vector(10'b1111111111);
    check_vector(10'b1010101010);
    check_vector(10'b0101010101);

    check_vector(10'b0000000001);
    check_vector(10'b1000000000);
    check_vector(10'b0000000010);

    check_vector(10'b0000000011);
    check_vector(10'b1100000000);
    check_vector(10'b0111111111);

    check_vector(10'b1111111110);
    check_vector(10'b1111111101);
    check_vector(10'b1011111111);
    check_vector(10'b0111111111);

    check_vector(10'b0000000100);
    check_vector(10'b0000000101);
    check_vector(10'b0010101100);
    check_vector(10'b1100101001);

    check_vector(10'b0000000000);
    check_vector(10'b0000000001);
    check_vector(10'b0000000011);
    check_vector(10'b0000000010);
    check_vector(10'b1000000000);
    check_vector(10'b0000000000);

    prev_gray = golden_gray(10'b0000000000);
    for (i = 1; i < 16; i = i + 1) begin
      check_vector(i[9:0]);
      curr_gray = golden_gray(i[9:0]);
      if (popcount10(prev_gray ^ curr_gray) !== 1) begin
        $display("FAIL: Gray adjacency violation between bin=%010b and bin=%010b (gray %010b -> %010b) at time %0t",
                 (i-1), i, prev_gray, curr_gray, $time);
        errors = errors + 1;
      end
      prev_gray = curr_gray;
    end

    for (i = 0; i < 10; i = i + 1) begin
      check_vector(10'b0000000001 << i);
    end

    for (i = 0; i < 1024; i = i + 1) begin
      check_vector(i[9:0]);
    end

    for (i = 0; i < 200; i = i + 1) begin
      rand_val = $random;
      check_vector(rand_val[9:0]);

      if ((i % 25) == 0) begin
        check_vector(rand_val[9:0]);
      end

      if ((i % 40) == 0) begin
        check_vector(10'b0000000000);
        check_vector(10'b1111111111);
        check_vector(10'b1010101010);
      end
    end

    if (errors == 0) begin
      $display("PASS");
    end else begin
      $display("FAIL: %0d mismatches detected", errors);
    end

    $finish;
  end

endmodule