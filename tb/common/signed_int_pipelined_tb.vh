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
    integer exact_result;
    integer approx_result;
    integer error_bias;
    integer queued_a;
    integer queued_b;
    real relative_error;
    real absolute_error;
    real percentage_error;
    real percentage_error_sum;

    integer input_a_queue [0:65535];
    integer input_b_queue [0:65535];

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

            exact_result = queued_a * queued_b;
            approx_result = $signed(r);
            error_bias = approx_result - exact_result;
            absolute_error = $itor((error_bias < 0) ? -error_bias : error_bias);
            relative_error = (exact_result == 0) ? 0.0 : $itor(error_bias) / $itor(exact_result);
            percentage_error = (exact_result == 0) ? 0.0 : (absolute_error * 100.0) / $itor((exact_result < 0) ? -exact_result : exact_result);

            head = head + 1;
            if (error_bias != 0) begin
                error_count = error_count + 1;
            end
            percentage_error_sum = percentage_error_sum + percentage_error;

            $fdisplay(file_ptr, "%0d,%0d,%0d,%0d,%0d,%0d,%f,%f,%f",
                      head, queued_a, queued_b, exact_result, approx_result, error_bias,
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
        total_tests = 256 * 256;
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

        for (i = -128; i < 128; i = i + 1) begin
            for (j = -128; j < 128; j = j + 1) begin
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

    signed_int_mul dut(
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
