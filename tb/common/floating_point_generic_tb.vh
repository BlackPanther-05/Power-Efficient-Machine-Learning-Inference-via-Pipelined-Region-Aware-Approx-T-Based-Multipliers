`timescale 1ns / 1ps

module tb;

    reg  [31:0] a;
    reg  [31:0] b;
    wire [31:0] result_re;
    wire [31:0] result;
    integer file_ptr;
    integer test_count;
    integer error_count;
    integer i;
    integer corner_i;
    integer corner_j;
    real percentage_error_sum;
    real error_epsilon;
    reg [31:0] case_a;
    reg [31:0] case_b;

    function real ieee754_to_real(input [31:0] ieee);
        reg sign;
        integer exponent;
        integer mantissa;
        real fraction;
        integer exp_val;
        begin
            sign = ieee[31];
            exponent = ieee[30:23];
            mantissa = ieee[22:0];

            if (exponent == 8'hFF) begin
                ieee754_to_real = 0.0;
            end else if (exponent == 0) begin
                fraction = mantissa / (2.0 ** 23);
                ieee754_to_real = (sign ? -1.0 : 1.0) * fraction * (2.0 ** (-126));
            end else begin
                fraction = 1.0 + (mantissa / (2.0 ** 23));
                exp_val = exponent - 127;
                ieee754_to_real = (sign ? -1.0 : 1.0) * fraction * (2.0 ** exp_val);
            end
        end
    endfunction

    function [31:0] dataset_float(input integer idx);
        reg [22:0] mantissa;
        begin
            mantissa = ((idx * 23'h12345) + 23'h054321) & 23'h7FFFFF;
            dataset_float = {1'b0, 8'd127, mantissa};
        end
    endfunction

    task get_corner_float;
        input integer idx;
        output [31:0] corner_float;
        begin
            case (idx)
                0: corner_float = 32'h3F800000;
                1: corner_float = 32'h3F900000;
                2: corner_float = 32'h3FA00000;
                3: corner_float = 32'h3FB00000;
                4: corner_float = 32'h3FC00000;
                5: corner_float = 32'h3FD00000;
                6: corner_float = 32'h3FE00000;
                default: corner_float = 32'h3FFFFFFF;
            endcase
        end
    endtask

    task run_case;
        input [31:0] next_a;
        input [31:0] next_b;
        real a_real;
        real b_real;
        real exact_result;
        real result_real;
        real error_bias;
        real relative_error;
        real absolute_error;
        real percentage_error;
        begin
            a = 32'd0;
            b = 32'd0;
            #1;
            a = next_a;
            b = next_b;
            #10;

            a_real = ieee754_to_real(a);
            b_real = ieee754_to_real(b);
            exact_result = ieee754_to_real(result);
            result_real = ieee754_to_real(result_re);
            error_bias = result_real - exact_result;
            absolute_error = $abs(error_bias);

            if (absolute_error <= error_epsilon) begin
                error_bias = 0.0;
                absolute_error = 0.0;
                relative_error = 0.0;
                percentage_error = 0.0;
            end else if ($abs(exact_result) > error_epsilon) begin
                relative_error = error_bias / exact_result;
                percentage_error = (absolute_error * 100.0) / $abs(exact_result);
            end else if ($abs(result_real) <= error_epsilon) begin
                relative_error = 0.0;
                percentage_error = 0.0;
            end else begin
                relative_error = (result_real > 0.0) ? 1.0 : -1.0;
                percentage_error = 100.0;
            end

            test_count = test_count + 1;
            if (absolute_error > error_epsilon) begin
                error_count = error_count + 1;
            end
            percentage_error_sum = percentage_error_sum + percentage_error;

            $fdisplay(file_ptr, "%0d,%f,%f,%f,%f,%f,%f,%f,%f",
                      test_count, a_real, b_real, exact_result, result_real, error_bias,
                      relative_error, absolute_error, percentage_error);
        end
    endtask

    initial begin
        a = 32'd0;
        b = 32'd0;
        test_count = 0;
        error_count = 0;
        percentage_error_sum = 0.0;
        error_epsilon = 1.0e-6;

        file_ptr = $fopen(`RESULT_CSV, "w");
        if (file_ptr == 0) begin
            $display("Error: could not open CSV file %s", `RESULT_CSV);
            $finish;
        end

        $dumpfile(`VCD_FILE);
        $dumpvars(0, tb);

        $fdisplay(file_ptr, "Test,A,B,Acc_Result,Approx_Result,Error_Bias,Relative_Error,Absolute_Error,Percentage_Error");

        for (corner_i = 0; corner_i < 8; corner_i = corner_i + 1) begin
            for (corner_j = 0; corner_j < 8; corner_j = corner_j + 1) begin
                get_corner_float(corner_i, case_a);
                get_corner_float(corner_j, case_b);
                run_case(case_a, case_b);
            end
        end

        for (i = 0; i < 65472; i = i + 1) begin
            case_a = dataset_float((2 * i) + 17);
            case_b = dataset_float((2 * i) + 53);
            run_case(case_a, case_b);
        end

        $display("%s %s complete: tests=%0d errors=%0d mean_percentage_error=%f%%",
                 `TB_VARIANT, `TB_LEVEL, test_count, error_count,
                 (test_count == 0) ? 0.0 : (percentage_error_sum / test_count));

        $fclose(file_ptr);
        $finish;
    end

    floating_point_mul dut(
        .A(a),
        .B(b),
        .Conf_Bit_Mask(`CONF_MASK),
        .R(result_re)
    );

    floating_point_multiplier golden_dut(
        .a(a),
        .b(b),
        .res(result)
    );

endmodule

module floating_point_multiplier(
    input [31:0] a,
    input [31:0] b,
    output [31:0] res
);

    wire sign;
    wire round;
    wire normalised;
    wire zero;
    wire [8:0] exponent;
    wire [8:0] sum_exponent;
    wire [22:0] product_mantissa;
    wire [23:0] op_a;
    wire [23:0] op_b;
    wire [47:0] product;
    wire [47:0] product_normalised;
    wire exception;
    wire overflow;
    wire underflow;

    assign sign = a[31] ^ b[31];
    assign exception = (&a[30:23]) | (&b[30:23]);
    assign op_a = (|a[30:23]) ? {1'b1, a[22:0]} : {1'b0, a[22:0]};
    assign op_b = (|b[30:23]) ? {1'b1, b[22:0]} : {1'b0, b[22:0]};
    assign product = op_a * op_b;
    assign normalised = product[47];
    assign product_normalised = normalised ? product : (product << 1);
    assign round = |product_normalised[22:0];
    assign product_mantissa = product_normalised[46:24] + (product_normalised[23] & round);
    assign zero = exception ? 1'b0 : (product_mantissa == 23'd0);
    assign sum_exponent = a[30:23] + b[30:23];
    assign exponent = sum_exponent - 8'd127 + normalised;
    assign overflow = (exponent[8] & !exponent[7]) & !zero;
    assign underflow = (exponent[8] & exponent[7]) & !zero;
    assign res = exception ? 32'd0 :
                 zero ? {sign, 31'd0} :
                 overflow ? {sign, 8'hFF, 23'd0} :
                 underflow ? {sign, 31'd0} :
                 {sign, exponent[7:0], product_mantissa};

endmodule
