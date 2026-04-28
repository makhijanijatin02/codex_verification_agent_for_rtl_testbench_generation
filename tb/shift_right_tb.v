`timescale 1ns/1ps

module tb;

  reg  [49:0] in;
  reg  [2:0]  shift;
  reg  [4:0]  fill;
  wire        out_valid;
  wire [49:0] out;

  integer errors;
  integer test_id;
  integer i;
  integer j;
  integer mode;
  integer base;
  reg [49:0] tmp_in;
  reg [49:0] rand_in;
  reg [2:0]  rand_shift;
  reg [4:0]  rand_fill;
  reg [4:0]  symtmp;

  shift_right dut (
    .out_valid(out_valid),
    .in(in),
    .shift(shift),
    .fill(fill),
    .out(out)
  );

  function [49:0] pack10;
    input [4:0] s0;
    input [4:0] s1;
    input [4:0] s2;
    input [4:0] s3;
    input [4:0] s4;
    input [4:0] s5;
    input [4:0] s6;
    input [4:0] s7;
    input [4:0] s8;
    input [4:0] s9;
    begin
      pack10 = {s9, s8, s7, s6, s5, s4, s3, s2, s1, s0};
    end
  endfunction

  function [49:0] expected_out_fn;
    input [49:0] vin;
    input [2:0]  vshift;
    input [4:0]  vfill;
    integer k;
    reg [49:0] tmp;
    begin
      tmp = 50'b0;
      for (k = 0; k < 10; k = k + 1) begin
        if ((k + vshift) <= 9)
          tmp[k*5 +: 5] = vin[(k + vshift)*5 +: 5];
        else
          tmp[k*5 +: 5] = vfill;
      end
      expected_out_fn = tmp;
    end
  endfunction

  task check_case;
    input integer id;
    input [49:0] vin;
    input [2:0]  vshift;
    input [4:0]  vfill;
    reg [49:0] exp_out;
    reg        exp_valid;
    begin
      in    = vin;
      shift = vshift;
      fill  = vfill;
      #1;

      exp_valid = (vshift <= 3'd4);
      exp_out   = expected_out_fn(vin, vshift, vfill);

      if (out_valid !== exp_valid) begin
        $display("FAIL case=%0d out_valid mismatch: shift=%0d expected=%0b got=%0b in=%h fill=%h", id, vshift, exp_valid, out_valid, vin, vfill);
        errors = errors + 1;
      end

      if (exp_valid) begin
        if (out !== exp_out) begin
          $display("FAIL case=%0d out mismatch: shift=%0d expected=%h got=%h in=%h fill=%h", id, vshift, exp_out, out, vin, vfill);
          errors = errors + 1;
        end
      end
    end
  endtask

  initial begin
    errors  = 0;
    test_id = 0;

    in    = 50'b0;
    shift = 3'b0;
    fill  = 5'b0;

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b00000, 5'b00001, 5'b00010, 5'b00011, 5'b00100,
             5'b00101, 5'b00110, 5'b00111, 5'b01000, 5'b01001),
      3'd0,
      5'b10101);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b00000, 5'b00001, 5'b00010, 5'b00011, 5'b00100,
             5'b00101, 5'b00110, 5'b00111, 5'b01000, 5'b01001),
      3'd1,
      5'b11100);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b10000, 5'b10001, 5'b10010, 5'b10011, 5'b10100,
             5'b10101, 5'b10110, 5'b10111, 5'b11000, 5'b11001),
      3'd2,
      5'b01010);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b00001, 5'b00010, 5'b00100, 5'b01000, 5'b10000,
             5'b00011, 5'b00110, 5'b01100, 5'b11000, 5'b11111),
      3'd3,
      5'b00000);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b00001, 5'b00010, 5'b00100, 5'b01000, 5'b10000,
             5'b00011, 5'b00110, 5'b01100, 5'b11000, 5'b11111),
      3'd3,
      5'b11111);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b11111, 5'b00000, 5'b11011, 5'b00100, 5'b01010,
             5'b10100, 5'b01110, 5'b10001, 5'b00111, 5'b11100),
      3'd4,
      5'b10101);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b00000, 5'b00001, 5'b00010, 5'b00011, 5'b00100,
             5'b00101, 5'b00110, 5'b00111, 5'b01000, 5'b01001),
      3'd1,
      5'b10011);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b00001, 5'b00010, 5'b00100, 5'b01000, 5'b10000,
             5'b11111, 5'b01111, 5'b00111, 5'b00011, 5'b10101),
      3'd1,
      5'b00101);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b00001, 5'b00010, 5'b00100, 5'b01000, 5'b10000,
             5'b11111, 5'b01111, 5'b00111, 5'b00011, 5'b10101),
      3'd2,
      5'b00101);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b00001, 5'b00010, 5'b00100, 5'b01000, 5'b10000,
             5'b11111, 5'b01111, 5'b00111, 5'b00011, 5'b10101),
      3'd3,
      5'b00101);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b00001, 5'b00010, 5'b00100, 5'b01000, 5'b10000,
             5'b11111, 5'b01111, 5'b00111, 5'b00011, 5'b10101),
      3'd4,
      5'b00101);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b00000, 5'b00001, 5'b00010, 5'b00011, 5'b00100,
             5'b00101, 5'b00110, 5'b00111, 5'b01000, 5'b01001),
      3'd5,
      5'b00000);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b11111, 5'b11110, 5'b11101, 5'b11100, 5'b11011,
             5'b11010, 5'b11001, 5'b11000, 5'b10111, 5'b10110),
      3'd6,
      5'b11111);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b00101, 5'b01010, 5'b10101, 5'b11000, 5'b00011,
             5'b11100, 5'b01111, 5'b10000, 5'b00110, 5'b11001),
      3'd7,
      5'b01010);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b11110, 5'b00001, 5'b10101, 5'b01010, 5'b00111,
             5'b11000, 5'b01100, 5'b10011, 5'b00000, 5'b11111),
      3'd4,
      5'b01001);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b00110, 5'b11001, 5'b01011, 5'b10100, 5'b01101,
             5'b10010, 5'b00011, 5'b11100, 5'b00101, 5'b01010),
      3'd0,
      5'b11111);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b11111, 5'b00000, 5'b11111, 5'b00000, 5'b11111,
             5'b00000, 5'b11111, 5'b00000, 5'b11111, 5'b00000),
      3'd4,
      5'b00110);

    tmp_in = pack10(5'b00000, 5'b00001, 5'b00010, 5'b00011, 5'b00100,
                    5'b00101, 5'b00110, 5'b00111, 5'b01000, 5'b01001);

    for (i = 0; i < 12; i = i + 1) begin
      case (i)
        0:  rand_shift = 3'd0;
        1:  rand_shift = 3'd1;
        2:  rand_shift = 3'd2;
        3:  rand_shift = 3'd3;
        4:  rand_shift = 3'd4;
        5:  rand_shift = 3'd5;
        6:  rand_shift = 3'd4;
        7:  rand_shift = 3'd3;
        8:  rand_shift = 3'd2;
        9:  rand_shift = 3'd1;
        10: rand_shift = 3'd0;
        default: rand_shift = 3'd7;
      endcase
      test_id = test_id + 1;
      check_case(test_id, tmp_in, rand_shift, 5'b10110);
    end

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b00001, 5'b00011, 5'b00101, 5'b00111, 5'b01001,
             5'b01011, 5'b01101, 5'b01111, 5'b10001, 5'b10011),
      3'd2,
      5'b00000);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b00001, 5'b00011, 5'b00101, 5'b00111, 5'b01001,
             5'b01011, 5'b01101, 5'b01111, 5'b10001, 5'b10011),
      3'd2,
      5'b11111);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b10011, 5'b10001, 5'b01111, 5'b01101, 5'b01011,
             5'b01001, 5'b00111, 5'b00101, 5'b00011, 5'b00001),
      3'd2,
      5'b11111);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b00100, 5'b01000, 5'b01100, 5'b10000, 5'b10100,
             5'b11000, 5'b11100, 5'b00001, 5'b00101, 5'b01001),
      3'd2,
      5'b10101);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b00111, 5'b10100, 5'b11100, 5'b00010, 5'b01010,
             5'b10001, 5'b01101, 5'b11011, 5'b00100, 5'b11110),
      3'd6,
      5'b00101);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b11100, 5'b00011, 5'b01110, 5'b10101, 5'b00110,
             5'b11000, 5'b01001, 5'b10010, 5'b00101, 5'b01010),
      3'd4,
      5'b11001);

    test_id = test_id + 1;
    check_case(test_id,
      pack10(5'b01010, 5'b10101, 5'b00110, 5'b11001, 5'b01100,
             5'b10011, 5'b00001, 5'b11110, 5'b01000, 5'b10111),
      3'd5,
      5'b00011);

    for (i = 0; i < 200; i = i + 1) begin
      tmp_in = 50'b0;
      mode = i % 6;
      base = (i * 3) % 32;

      if (i < 100) begin
        case (mode)
          0: begin
            for (j = 0; j < 10; j = j + 1)
              tmp_in[j*5 +: 5] = (base + j) & 5'h1f;
          end
          1: begin
            for (j = 0; j < 10; j = j + 1)
              tmp_in[j*5 +: 5] = (j[0] ? 5'h1f : 5'h00);
          end
          2: begin
            tmp_in = 50'h0;
          end
          3: begin
            for (j = 0; j < 10; j = j + 1)
              tmp_in[j*5 +: 5] = 5'h1f;
          end
          4: begin
            for (j = 0; j < 10; j = j + 1) begin
              if (j == 0)
                tmp_in[j*5 +: 5] = 5'h01;
              else if (j == 9)
                tmp_in[j*5 +: 5] = 5'h1e;
              else
                tmp_in[j*5 +: 5] = (5'h08 + j) & 5'h1f;
            end
          end
          default: begin
            tmp_in = pack10(5'h01, 5'h02, 5'h04, 5'h08, 5'h10,
                            5'h1f, 5'h0f, 5'h07, 5'h03, 5'h15);
          end
        endcase

        case (i % 8)
          0: rand_fill = 5'h00;
          1: rand_fill = 5'h1f;
          2: rand_fill = 5'h15;
          3: rand_fill = 5'h0a;
          4: rand_fill = 5'h12;
          5: rand_fill = 5'h09;
          6: rand_fill = 5'h1b;
          default: rand_fill = 5'h05;
        endcase

        rand_shift = i % 8;
      end else begin
        rand_in    = {$random, $random};
        tmp_in     = rand_in;
        rand_fill  = $random;
        rand_shift = $random;
      end

      test_id = test_id + 1;
      check_case(test_id, tmp_in, rand_shift, rand_fill);
    end

    if (errors == 0)
      $display("PASS");
    else
      $display("FAIL: %0d mismatches", errors);

    $finish;
  end

endmodule