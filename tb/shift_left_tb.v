`timescale 1ns/1ps

module tb;

  reg  [95:0] in;
  reg  [2:0]  shift;
  reg  [11:0] fill;
  wire        out_valid;
  wire [95:0] out;

  integer errors;
  integer test_id;
  integer i;
  integer sel;
  integer lane;
  reg [11:0] sym_a;
  reg [11:0] sym_b;
  reg [95:0] rand_in;

  shift_left dut (
    .out_valid(out_valid),
    .in(in),
    .shift(shift),
    .fill(fill),
    .out(out)
  );

  function [95:0] pack_symbols;
    input [11:0] s0;
    input [11:0] s1;
    input [11:0] s2;
    input [11:0] s3;
    input [11:0] s4;
    input [11:0] s5;
    input [11:0] s6;
    input [11:0] s7;
    begin
      pack_symbols = {s7, s6, s5, s4, s3, s2, s1, s0};
    end
  endfunction

  function [95:0] golden_out;
    input [95:0] in_vec;
    input [2:0]  shift_vec;
    input [11:0] fill_vec;
    integer idx;
    reg [95:0] tmp;
    begin
      tmp = 96'h0;
      for (idx = 0; idx < 8; idx = idx + 1) begin
        if (idx < shift_vec)
          tmp[idx*12 +: 12] = fill_vec;
        else
          tmp[idx*12 +: 12] = in_vec[(idx-shift_vec)*12 +: 12];
      end
      golden_out = tmp;
    end
  endfunction

  task fail_valid;
    input integer id;
    input [95:0] in_vec;
    input [2:0]  shift_vec;
    input [11:0] fill_vec;
    input        exp_valid;
    begin
      $display("FAIL test=%0d kind=out_valid in=%024h shift=%0d fill=%03h expected_valid=%0b actual_valid=%0b",
               id, in_vec, shift_vec, fill_vec, exp_valid, out_valid);
      errors = errors + 1;
    end
  endtask

  task fail_out;
    input integer id;
    input [95:0] in_vec;
    input [2:0]  shift_vec;
    input [11:0] fill_vec;
    input [95:0] exp_out;
    begin
      $display("FAIL test=%0d kind=out in=%024h shift=%0d fill=%03h expected_out=%024h actual_out=%024h",
               id, in_vec, shift_vec, fill_vec, exp_out, out);
      errors = errors + 1;
    end
  endtask

  task run_case;
    input [95:0] in_vec;
    input [2:0]  shift_vec;
    input [11:0] fill_vec;
    input        check_out;
    reg          exp_valid;
    reg [95:0]   exp_out;
    begin
      test_id = test_id + 1;
      in = in_vec;
      shift = shift_vec;
      fill = fill_vec;
      #1;

      exp_valid = (shift_vec <= 3'd5);
      if (out_valid !== exp_valid)
        fail_valid(test_id, in_vec, shift_vec, fill_vec, exp_valid);

      if (check_out && exp_valid) begin
        exp_out = golden_out(in_vec, shift_vec, fill_vec);
        if (out !== exp_out)
          fail_out(test_id, in_vec, shift_vec, fill_vec, exp_out);
      end
    end
  endtask

  initial begin
    errors = 0;
    test_id = 0;
    in = 96'h0;
    shift = 3'b000;
    fill = 12'h000;

    #1;

    run_case(
      pack_symbols(12'h001, 12'h123, 12'h456, 12'h789, 12'hABC, 12'hDEF, 12'h135, 12'h246),
      3'd0,
      12'hAAA,
      1'b1
    );

    run_case(
      pack_symbols(12'h001, 12'h123, 12'h456, 12'h789, 12'hABC, 12'hDEF, 12'h135, 12'h246),
      3'd1,
      12'h55A,
      1'b1
    );

    run_case(
      pack_symbols(12'h010, 12'h111, 12'h222, 12'h333, 12'h444, 12'h555, 12'h666, 12'h777),
      3'd2,
      12'hE3C,
      1'b1
    );

    run_case(
      pack_symbols(12'h001, 12'h123, 12'h456, 12'h789, 12'hABC, 12'hDEF, 12'h135, 12'h246),
      3'd6,
      12'hAAA,
      1'b0
    );

    run_case(
      pack_symbols(12'h001, 12'h123, 12'h456, 12'h789, 12'hABC, 12'hDEF, 12'h135, 12'h246),
      3'd7,
      12'h555,
      1'b0
    );

    run_case(
      pack_symbols(12'h000, 12'h000, 12'h000, 12'h000, 12'h000, 12'h000, 12'h000, 12'h000),
      3'd5,
      12'h000,
      1'b1
    );

    run_case(
      pack_symbols(12'hFFF, 12'hFFF, 12'hFFF, 12'hFFF, 12'hFFF, 12'hFFF, 12'hFFF, 12'hFFF),
      3'd1,
      12'hFFF,
      1'b1
    );

    run_case(
      pack_symbols(12'hFFF, 12'h000, 12'hFFF, 12'h000, 12'hFFF, 12'h000, 12'hFFF, 12'h000),
      3'd1,
      12'h000,
      1'b1
    );

    run_case(
      pack_symbols(12'hAAA, 12'h555, 12'hA5A, 12'h5A5, 12'hF0F, 12'h0F0, 12'h99A, 12'h660),
      3'd2,
      12'hC3C,
      1'b1
    );

    run_case(
      pack_symbols(12'h001, 12'h002, 12'h004, 12'h008, 12'h010, 12'h020, 12'h040, 12'h080),
      3'd3,
      12'h100,
      1'b1
    );

    for (i = 0; i < 8; i = i + 1)
      run_case(
        pack_symbols(12'h001, 12'h123, 12'h456, 12'h789, 12'hABC, 12'hDEF, 12'h135, 12'h246),
        i[2:0],
        12'h69C,
        (i <= 5)
      );

    run_case(
      pack_symbols(12'h111, 12'h222, 12'h333, 12'h444, 12'h555, 12'h666, 12'h777, 12'h888),
      3'd2,
      12'hACE,
      1'b1
    );
    run_case(
      pack_symbols(12'h111, 12'h222, 12'h333, 12'h444, 12'h555, 12'h666, 12'h777, 12'h888),
      3'd2,
      12'h135,
      1'b1
    );
    run_case(
      pack_symbols(12'h999, 12'hAAA, 12'hBBB, 12'hCCC, 12'hDDD, 12'hEEE, 12'h123, 12'h456),
      3'd2,
      12'h135,
      1'b1
    );
    run_case(
      pack_symbols(12'hFED, 12'hCBA, 12'h987, 12'h654, 12'h321, 12'h0F0, 12'hF0F, 12'h55A),
      3'd2,
      12'h00D,
      1'b1
    );

    run_case(
      pack_symbols(12'h001, 12'h123, 12'h456, 12'h789, 12'hABC, 12'hDEF, 12'h135, 12'h246),
      3'd5,
      12'h777,
      1'b1
    );
    run_case(
      pack_symbols(12'h001, 12'h123, 12'h456, 12'h789, 12'hABC, 12'hDEF, 12'h135, 12'h246),
      3'd6,
      12'h777,
      1'b0
    );
    run_case(
      pack_symbols(12'h001, 12'h123, 12'h456, 12'h789, 12'hABC, 12'hDEF, 12'h135, 12'h246),
      3'd5,
      12'h777,
      1'b1
    );
    run_case(
      pack_symbols(12'h001, 12'h123, 12'h456, 12'h789, 12'hABC, 12'hDEF, 12'h135, 12'h246),
      3'd0,
      12'h777,
      1'b1
    );

    for (i = 0; i < 100; i = i + 1) begin
      if (i < 50) begin
        case (i % 6)
          0: shift = 3'd0;
          1: shift = 3'd1;
          2: shift = 3'd4;
          3: shift = 3'd5;
          4: shift = 3'd6;
          default: shift = 3'd7;
        endcase
      end else begin
        shift = ($random & 3'b111);
      end

      sel = ($random & 32'h7fffffff) % 4;
      fill = $random & 12'hFFF;
      rand_in = 96'h0;

      case (sel)
        0: begin
          for (lane = 0; lane < 8; lane = lane + 1)
            rand_in[lane*12 +: 12] = $random & 12'hFFF;
        end

        1: begin
          sym_a = $random & 12'hFFF;
          sym_b = $random & 12'hFFF;
          for (lane = 0; lane < 8; lane = lane + 1) begin
            if ((lane % 2) == 0)
              rand_in[lane*12 +: 12] = sym_a;
            else
              rand_in[lane*12 +: 12] = sym_b;
          end
        end

        2: begin
          rand_in = pack_symbols(12'hAAA, 12'h555, 12'hA5A, 12'h5A5, 12'hF0F, 12'h0F0, 12'h99A, 12'h660);
          if (($random & 1'b1) == 1'b1)
            fill = 12'hC3C;
          else
            fill = 12'h3C3;
        end

        default: begin
          for (lane = 0; lane < 8; lane = lane + 1)
            rand_in[lane*12 +: 12] = $random & 12'hFFF;
          fill = rand_in[(($random & 32'h7fffffff) % 8)*12 +: 12];
        end
      endcase

      run_case(rand_in, shift, fill, (shift <= 3'd5));
    end

    if (errors == 0)
      $display("PASS");

    $finish;
  end

endmodule