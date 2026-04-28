`timescale 1ns/1ps

module tb;

  reg         clk;
  reg         rst;
  reg         data_valid;
  reg  [11:0] data;
  wire        enc_valid;
  wire [12:0] enc_codeword;

  integer errors;
  integer checks;
  integer i;
  integer r;

  ecc_sed_encoder dut (
    .clk(clk),
    .rst(rst),
    .data_valid(data_valid),
    .enc_valid(enc_valid),
    .data(data),
    .enc_codeword(enc_codeword)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  function [12:0] expected_codeword;
    input [11:0] d;
    begin
      expected_codeword = {^d, d};
    end
  endfunction

  task check_outputs;
    input        expect_valid;
    input [11:0] d;
    input [255:0] label;
    reg   [12:0] exp_codeword;
    begin
      #1;
      checks = checks + 1;
      if (enc_valid !== expect_valid) begin
        $display("FAIL: %0s: enc_valid mismatch. expected=%b got=%b data_valid=%b data=%03h rst=%b clk=%b time=%0t",
                 label, expect_valid, enc_valid, data_valid, data, rst, clk, $time);
        errors = errors + 1;
      end

      if (expect_valid) begin
        exp_codeword = expected_codeword(d);
        if (enc_codeword !== exp_codeword) begin
          $display("FAIL: %0s: enc_codeword mismatch. expected=%04h got=%04h data=%03h rst=%b clk=%b time=%0t",
                   label, exp_codeword, enc_codeword, d, rst, clk, $time);
          errors = errors + 1;
        end
        if ((^enc_codeword) !== 1'b0) begin
          $display("FAIL: %0s: encoded word does not have even parity. enc_codeword=%04h data=%03h time=%0t",
                   label, enc_codeword, d, $time);
          errors = errors + 1;
        end
      end
    end
  endtask

  task drive_and_check;
    input        dv;
    input [11:0] d;
    input        rr;
    input [255:0] label;
    begin
      data_valid = dv;
      data       = d;
      rst        = rr;
      check_outputs(dv, d, label);
    end
  endtask

  task pulse_clk_and_check_stable;
    input        dv;
    input [11:0] d;
    input        rr;
    input [255:0] label;
    reg   [12:0] exp_codeword;
    begin
      data_valid = dv;
      data       = d;
      rst        = rr;
      #1;
      exp_codeword = expected_codeword(d);

      @(posedge clk);
      #1;
      checks = checks + 1;
      if (enc_valid !== dv) begin
        $display("FAIL: %0s after posedge: enc_valid mismatch. expected=%b got=%b time=%0t",
                 label, dv, enc_valid, $time);
        errors = errors + 1;
      end
      if (dv && enc_codeword !== exp_codeword) begin
        $display("FAIL: %0s after posedge: enc_codeword mismatch. expected=%04h got=%04h time=%0t",
                 label, exp_codeword, enc_codeword, $time);
        errors = errors + 1;
      end

      @(negedge clk);
      #1;
      checks = checks + 1;
      if (enc_valid !== dv) begin
        $display("FAIL: %0s after negedge: enc_valid mismatch. expected=%b got=%b time=%0t",
                 label, dv, enc_valid, $time);
        errors = errors + 1;
      end
      if (dv && enc_codeword !== exp_codeword) begin
        $display("FAIL: %0s after negedge: enc_codeword mismatch. expected=%04h got=%04h time=%0t",
                 label, exp_codeword, enc_codeword, $time);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    errors = 0;
    checks = 0;
    rst = 1'b0;
    data_valid = 1'b0;
    data = 12'h000;

    #2;

    drive_and_check(1'b1, 12'h000, 1'b0, "spot_000");
    drive_and_check(1'b1, 12'h001, 1'b0, "spot_001");
    drive_and_check(1'b1, 12'h003, 1'b0, "spot_003");
    drive_and_check(1'b1, 12'h800, 1'b0, "spot_800");
    drive_and_check(1'b1, 12'hAAA, 1'b0, "spot_AAA");

    drive_and_check(1'b1, 12'hFFF, 1'b0, "corner_FFF");
    drive_and_check(1'b1, 12'h555, 1'b0, "corner_555");
    drive_and_check(1'b1, 12'hFFE, 1'b0, "corner_FFE");
    drive_and_check(1'b1, 12'h7FF, 1'b0, "corner_7FF");
    drive_and_check(1'b1, 12'h801, 1'b0, "subset_801");
    drive_and_check(1'b1, 12'h400, 1'b0, "subset_400");
    drive_and_check(1'b1, 12'h002, 1'b0, "subset_002");
    drive_and_check(1'b1, 12'h123, 1'b0, "position_123");

    for (i = 0; i < 4096; i = i + 1) begin
      drive_and_check(1'b1, i[11:0], 1'b0, "exhaustive_valid");
    end

    drive_and_check(1'b0, 12'h000, 1'b0, "invalid_000");
    drive_and_check(1'b0, 12'hFFF, 1'b0, "invalid_FFF");
    drive_and_check(1'b0, 12'hA55, 1'b0, "invalid_A55");

    data       = 12'h000;
    data_valid = 1'b1;
    rst        = 1'b0;
    check_outputs(1'b1, 12'h000, "same_cycle_start_000");
    data       = 12'h001;
    check_outputs(1'b1, 12'h001, "same_cycle_data_change_000_to_001");

    data       = 12'hABC;
    data_valid = 1'b0;
    rst        = 1'b0;
    check_outputs(1'b0, 12'hABC, "same_cycle_valid_low_ABC");
    data_valid = 1'b1;
    check_outputs(1'b1, 12'hABC, "same_cycle_valid_rise_ABC");
    data_valid = 1'b0;
    check_outputs(1'b0, 12'hABC, "same_cycle_valid_fall_ABC");

    data       = 12'h3C3;
    data_valid = 1'b0;
    rst        = 1'b0;
    check_outputs(1'b0, 12'h3C3, "gate_fixed_invalid_3C3");
    data_valid = 1'b1;
    check_outputs(1'b1, 12'h3C3, "gate_fixed_valid_3C3");
    data_valid = 1'b0;
    check_outputs(1'b0, 12'h3C3, "gate_fixed_invalid_again_3C3");

    drive_and_check(1'b1, 12'h000, 1'b0, "seq0");
    drive_and_check(1'b1, 12'h001, 1'b1, "seq1_rst_high_should_not_matter");
    drive_and_check(1'b0, 12'hFFF, 1'b0, "seq2_invalid");
    drive_and_check(1'b1, 12'hFFF, 1'b0, "seq3_valid_fff");
    drive_and_check(1'b1, 12'h800, 1'b0, "seq4_valid_800");
    drive_and_check(1'b0, 12'h123, 1'b1, "seq5_invalid_rst_high");
    drive_and_check(1'b1, 12'h123, 1'b0, "seq6_valid_123");
    drive_and_check(1'b1, 12'h122, 1'b0, "seq7_valid_122");

    drive_and_check(1'b0, 12'h055, 1'b0, "pulse0");
    drive_and_check(1'b1, 12'h055, 1'b0, "pulse1");
    drive_and_check(1'b0, 12'h155, 1'b0, "pulse2");
    drive_and_check(1'b1, 12'h155, 1'b0, "pulse3");
    drive_and_check(1'b0, 12'h955, 1'b0, "pulse4");
    drive_and_check(1'b1, 12'h955, 1'b0, "pulse5");

    drive_and_check(1'b1, 12'hA5C, 1'b0, "rst_indep_valid_lowrst");
    drive_and_check(1'b1, 12'hA5C, 1'b1, "rst_indep_valid_highrst");
    drive_and_check(1'b1, 12'hA5C, 1'b0, "rst_indep_valid_lowrst_again");

    drive_and_check(1'b0, 12'h000, 1'b0, "rst_indep_invalid_0");
    drive_and_check(1'b0, 12'hFFF, 1'b1, "rst_indep_invalid_1");
    drive_and_check(1'b0, 12'h123, 1'b0, "rst_indep_invalid_2");

    pulse_clk_and_check_stable(1'b1, 12'h96B, 1'b0, "clk_independence_0");
    pulse_clk_and_check_stable(1'b1, 12'h96B, 1'b0, "clk_independence_1");
    pulse_clk_and_check_stable(1'b1, 12'h96B, 1'b0, "clk_independence_2");

    for (i = 0; i < 200; i = i + 1) begin
      r = $random;
      if ((i % 4) == 0) begin
        data = (data + 12'h001) & 12'hFFF;
      end else if ((i % 4) == 1) begin
        data = (data ^ 12'h001);
      end else begin
        data = r[11:0];
      end

      data_valid = r[16];
      rst = r[17];

      check_outputs(data_valid, data, "random_trial");

      if ((i % 25) == 0) begin
        @(posedge clk);
        #1;
        checks = checks + 1;
        if (enc_valid !== data_valid) begin
          $display("FAIL: random_clk_rst_independence: enc_valid changed unexpectedly after clk edge. expected=%b got=%b time=%0t",
                   data_valid, enc_valid, $time);
          errors = errors + 1;
        end
        if (data_valid && enc_codeword !== expected_codeword(data)) begin
          $display("FAIL: random_clk_rst_independence: enc_codeword changed unexpectedly after clk edge. expected=%04h got=%04h time=%0t",
                   expected_codeword(data), enc_codeword, $time);
          errors = errors + 1;
        end
      end
    end

    if (errors == 0) begin
      $display("PASS");
    end else begin
      $display("FAIL: %0d errors across %0d checks", errors, checks);
    end
    $finish;
  end

endmodule