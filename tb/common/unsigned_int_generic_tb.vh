`timescale 1ns / 1ps

module tb;

    wire [15:0] r;
    reg  [7:0]  A;
    reg  [7:0]  B;
    integer i;
    integer j;
    integer test_count;
    integer file_ptr;
    integer error_count;
    integer exact_result;
    integer approx_result;
    integer error_bias;
    real relative_error;
    real absolute_error;
    real percentage_error;
    real percentage_error_sum;

    initial begin
        A = 8'd0;
        B = 8'd0;
        test_count = 0;
        error_count = 0;
        percentage_error_sum = 0.0;

        file_ptr = $fopen(`RESULT_CSV, "w");
        if (file_ptr == 0) begin
            $display("Error: could not open CSV file %s", `RESULT_CSV);
            $finish;
        end

        $dumpfile(`VCD_FILE);
        $dumpvars(0, tb);

        $fdisplay(file_ptr, "Test,A,B,Acc_Result,Approx_Result,Error_Bias,Relative_Error,Absolute_Error,Percentage_Error");

        for (i = 0; i < 256; i = i + 1) begin
            for (j = 0; j < 256; j = j + 1) begin
                A = 8'd0;
                B = 8'd0;
                #1;
                A = i[7:0];
                B = j[7:0];
                #1;

                exact_result = i * j;
                approx_result = r;
                error_bias = approx_result - exact_result;
                absolute_error = $itor((error_bias < 0) ? -error_bias : error_bias);
                relative_error = (exact_result == 0) ? 0.0 : $itor(error_bias) / $itor(exact_result);
                percentage_error = (exact_result == 0) ? 0.0 : (absolute_error * 100.0) / $itor(exact_result);

                test_count = test_count + 1;
                if (error_bias != 0) begin
                    error_count = error_count + 1;
                end
                percentage_error_sum = percentage_error_sum + percentage_error;

                $fdisplay(file_ptr, "%0d,%0d,%0d,%0d,%0d,%0d,%f,%f,%f",
                          test_count, i, j, exact_result, approx_result, error_bias,
                          relative_error, absolute_error, percentage_error);
            end
        end

        $display("%s %s complete: tests=%0d errors=%0d mean_percentage_error=%f%%",
                 `TB_VARIANT, `TB_LEVEL, test_count, error_count,
                 (test_count == 0) ? 0.0 : (percentage_error_sum / test_count));

        $fclose(file_ptr);
        $finish;
    end

    unsigned_int_mul dut(
        .A(A),
        .B(B),
        .R(r),
        .Conf_Bit_Mask(`CONF_MASK)
    );

endmodule
