// Generic testbench for SOTA signed integer multipliers
`timescale 1ns / 1ps

module tb;

    wire signed [15:0] r;
    reg  signed [7:0]  A;
    reg  signed [7:0]  B;
    integer i;
    integer j;
    integer test_count;
    integer pass_count;
    integer fail_count;
    integer file_ptr;
    integer exact_result;
    integer approx_result;
    integer error_bias;
    real relative_error;
    real absolute_error;
    real percentage_error;
    real percentage_error_sum;

    initial begin
        A = 8'sd0;
        B = 8'sd0;
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        percentage_error_sum = 0.0;

        file_ptr = $fopen(`RESULT_CSV, "w");
        if (file_ptr == 0) begin
            $display("Error: could not open CSV file %s", `RESULT_CSV);
            $finish;
        end

        $fdisplay(file_ptr, "Test,A,B,Exact_Result,Approx_Result,Error_Bias,Relative_Error,Absolute_Error,Percentage_Error,Status");

        for (i = -128; i < 128; i = i + 1) begin
            for (j = -128; j < 128; j = j + 1) begin
                A = 8'sd0;
                B = 8'sd0;
                #1;
                A = i[7:0];
                B = j[7:0];
                #1;

                exact_result = i * j;
                approx_result = $signed(r);
                error_bias = approx_result - exact_result;
                absolute_error = $itor((error_bias < 0) ? -error_bias : error_bias);
                relative_error = (exact_result == 0) ? 0.0 : $itor(error_bias) / $itor(exact_result);
                percentage_error = (exact_result == 0) ? 0.0 : (absolute_error * 100.0) / $itor((exact_result < 0) ? -exact_result : exact_result);

                test_count = test_count + 1;
                percentage_error_sum = percentage_error_sum + percentage_error;

                if (percentage_error <= `ERROR_THRESHOLD) begin
                    pass_count = pass_count + 1;
                    $fdisplay(file_ptr, "%0d,%0d,%0d,%0d,%0d,%0d,%f,%f,%f,PASS",
                              test_count, i, j, exact_result, approx_result, error_bias,
                              relative_error, absolute_error, percentage_error);
                end else begin
                    fail_count = fail_count + 1;
                    $fdisplay(file_ptr, "%0d,%0d,%0d,%0d,%0d,%0d,%f,%f,%f,FAIL",
                              test_count, i, j, exact_result, approx_result, error_bias,
                              relative_error, absolute_error, percentage_error);
                end
            end
        end

        $display("[%s] %s %s: tests=%0d PASS=%0d FAIL=%0d mean_pct_error=%f%%",
                 (fail_count == 0) ? "ALL PASS" : "HAS FAIL",
                 `TB_DESIGN, `TB_LEVEL, test_count, pass_count, fail_count,
                 (test_count == 0) ? 0.0 : (percentage_error_sum / $itor(test_count)));

        $fclose(file_ptr);
        $finish;
    end

    `DESIGN_MODULE dut(
        .A(A),
        .B(B),
        .R(r),
        .Conf_Bit_Mask(`CONF_MASK)
    );

endmodule
