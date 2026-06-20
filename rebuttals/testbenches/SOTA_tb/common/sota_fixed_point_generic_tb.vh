// Generic testbench for SOTA fixed-point multipliers (Q4.4 format)
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
    real a_real, b_real, exact_real, approx_real;
    real error_real, absolute_error, percentage_error;
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

        $fdisplay(file_ptr, "Test,A_hex,B_hex,A_real,B_real,Exact_Result,Approx_Result,Error,Absolute_Error,Percentage_Error,Status");

        for (i = -128; i < 128; i = i + 1) begin
            for (j = -128; j < 128; j = j + 1) begin
                A = 8'sd0;
                B = 8'sd0;
                #1;
                A = i[7:0];
                B = j[7:0];
                #1;

                // Q4.4 format: value = signed_int / 16.0
                a_real = $itor(i) / 16.0;
                b_real = $itor(j) / 16.0;
                exact_real = a_real * b_real;
                // The RTL already does >>> DEC_POINT_POS, so result is in Q8.4 format
                approx_real = $itor($signed(r)) / 16.0;

                error_real = approx_real - exact_real;
                absolute_error = (error_real < 0.0) ? -error_real : error_real;
                percentage_error = (exact_real == 0.0) ? 0.0 : (absolute_error * 100.0) / ((exact_real < 0.0) ? -exact_real : exact_real);

                test_count = test_count + 1;
                percentage_error_sum = percentage_error_sum + percentage_error;

                if (percentage_error <= `ERROR_THRESHOLD) begin
                    pass_count = pass_count + 1;
                    $fdisplay(file_ptr, "%0d,%h,%h,%f,%f,%f,%f,%f,%f,%f,PASS",
                              test_count, A, B, a_real, b_real, exact_real, approx_real,
                              error_real, absolute_error, percentage_error);
                end else begin
                    fail_count = fail_count + 1;
                    $fdisplay(file_ptr, "%0d,%h,%h,%f,%f,%f,%f,%f,%f,%f,FAIL",
                              test_count, A, B, a_real, b_real, exact_real, approx_real,
                              error_real, absolute_error, percentage_error);
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

    `DESIGN_MODULE #(.WIDTH(8), .DEC_POINT_POS(4)) dut(
        .A(A),
        .B(B),
        .R(r),
        .Conf_Bit_Mask(`CONF_MASK)
    );

endmodule
