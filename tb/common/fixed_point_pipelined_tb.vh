`timescale 1ns / 1ps

module tb;

    reg clk;
    reg rst_n;
    reg valid_in;
    reg signed [7:0] A;
    reg signed [7:0] B;
    wire valid_out;
    wire signed [15:0] r;

`ifndef REGION_EN
    `define REGION_EN 4'b1111
`endif

`ifndef REGION_CONF
    `define REGION_CONF 16'h7777
`endif

    integer i;
    integer j;
    integer head;
    integer tail;
    integer total_tests;
    integer file_ptr;
    integer error_count;
    integer queued_a;
    integer queued_b;
    real a_real;
    real b_real;
    real exact_result;
    real approx_result;
    real error_bias;
    real relative_error;
    real absolute_error;
    real percentage_error;
    real percentage_error_sum;
    real denominator;

    integer input_a_queue [0:255];
    integer input_b_queue [0:255];

    always #0.5 clk = ~clk;

    task launch_case;
        input integer next_a;
        input integer next_b;
        begin
            @(negedge clk);
            A <= next_a[7:0];
            B <= next_b[7:0];
            valid_in <= 1'b1;
            input_a_queue[tail] = next_a;
            input_b_queue[tail] = next_b;
            tail = tail + 1;
        end
    endtask

    always @(posedge clk) begin
        if (rst_n && valid_out) begin
            queued_a = input_a_queue[head];
            queued_b = input_b_queue[head];

            a_real = $itor(queued_a) / 16.0;
            b_real = $itor(queued_b) / 16.0;
            exact_result = a_real * b_real;
            approx_result = $itor($signed(r)) / 16.0;
            error_bias = approx_result - exact_result;
            absolute_error = $abs(error_bias);
            denominator = (exact_result != 0.0) ? exact_result :
                          ((approx_result != 0.0) ? approx_result : 1.0);
            relative_error = (absolute_error == 0.0) ? 0.0 : error_bias / denominator;
            percentage_error = (exact_result == 0.0) ? 0.0 : (absolute_error * 100.0) / $abs(exact_result);

            head = head + 1;
            if (absolute_error > 1.0e-12) begin
                error_count = error_count + 1;
            end
            percentage_error_sum = percentage_error_sum + percentage_error;

            $fdisplay(file_ptr, "%0d,%f,%f,%f,%f,%f,%f,%f,%f",
                      head, a_real, b_real, exact_result, approx_result, error_bias,
                      relative_error, absolute_error, percentage_error);
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        valid_in = 1'b0;
        A = 8'sd0;
        B = 8'sd0;
        head = 0;
        tail = 0;
        total_tests = 16 * 16;
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

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (i = 16; i < 32; i = i + 1) begin
            for (j = 16; j < 32; j = j + 1) begin
                launch_case(i, j);
            end
        end

        @(negedge clk);
        valid_in <= 1'b0;
        A <= 8'sd0;
        B <= 8'sd0;

        wait (head == total_tests);
        repeat (4) @(posedge clk);

        $display("%s %s complete: tests=%0d errors=%0d mean_percentage_error=%f%%",
                 `TB_VARIANT, `TB_LEVEL, head, error_count,
                 (head == 0) ? 0.0 : (percentage_error_sum / head));

        $fclose(file_ptr);
        $finish;
    end

    fixed_point_mul dut(
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .A(A),
        .B(B),
        .R(r),
        .valid_out(valid_out),
        .Region_Enable(`REGION_EN),
        .Region_Conf_Mask(`REGION_CONF)
    );

endmodule
