//Date: 2024/5/29
//Description: floating point multiplication
//Note:        Pipelined RTL_proposed_2 variant.

module floating_point_mul(
    input clk,
    input rst_n,
    input valid_in,
    input [31:0] A,
    input [31:0] B,
    input [3:0] Region_Enable,
    input [15:0] Region_Conf_Mask,
    output valid_out,
    output [31:0] R
);
    wire sign_r_comb;
    wire [7:0] exp_a_comb;
    wire [7:0] exp_b_comb;
    wire [22:0] mantissa_a_comb;
    wire [22:0] mantissa_b_comb;

    assign sign_r_comb = A[31] ^ B[31];
    assign exp_a_comb = A[30:23];
    assign exp_b_comb = B[30:23];
    assign mantissa_a_comb = A[22:0];
    assign mantissa_b_comb = B[22:0];

    reg sign_pipe0;
    reg sign_pipe1;
    reg sign_pipe2;
    reg [7:0] exp_a_pipe0;
    reg [7:0] exp_a_pipe1;
    reg [7:0] exp_a_pipe2;
    reg [7:0] exp_b_pipe0;
    reg [7:0] exp_b_pipe1;
    reg [7:0] exp_b_pipe2;

    wire approx_valid_out;
    wire [47:0] mantissa_out_temp0;

    approx_t #(
        .WIDTH(24)
    ) m_approx_t (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .x(mantissa_a_comb),
        .y(mantissa_b_comb),
        .Region_Enable(Region_Enable),
        .Region_Conf_Mask(Region_Conf_Mask),
        .valid_out(approx_valid_out),
        .f(mantissa_out_temp0)
    );

    wire [1:0] shift_comb;
    wire [22:0] mantissa_out_comb;
    wire [9:0] exp_overflow_comb;
    wire overflow_comb;
    wire underflow_comb;
    wire [22:0] mantissa_r_comb;
    wire [7:0] exp_r_comb;

    assign shift_comb = mantissa_out_temp0[24:23];
    assign mantissa_out_comb = shift_comb[1] ? mantissa_out_temp0[23:1] : mantissa_out_temp0[22:0];
    assign exp_overflow_comb = {2'b0, exp_a_pipe2} + {2'b0, exp_b_pipe2}
                             + {8'b11100000, shift_comb[1], shift_comb[0] && ~shift_comb[1]};
    assign overflow_comb = (~exp_overflow_comb[9] && exp_overflow_comb[8])
                         || (~exp_overflow_comb[9] && ~exp_overflow_comb[8] && (&exp_overflow_comb[7:0]));
    assign underflow_comb = exp_overflow_comb[9] && exp_overflow_comb[8];
    assign mantissa_r_comb = overflow_comb ? 23'h7fffff : (underflow_comb ? 23'd0 : mantissa_out_comb);
    assign exp_r_comb = overflow_comb ? 8'hfe : (underflow_comb ? 8'h01 : exp_overflow_comb[7:0]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sign_pipe0 <= 1'b0;
            sign_pipe1 <= 1'b0;
            sign_pipe2 <= 1'b0;
            exp_a_pipe0 <= 8'd0;
            exp_a_pipe1 <= 8'd0;
            exp_a_pipe2 <= 8'd0;
            exp_b_pipe0 <= 8'd0;
            exp_b_pipe1 <= 8'd0;
            exp_b_pipe2 <= 8'd0;
        end else begin
            sign_pipe0 <= sign_r_comb;
            sign_pipe1 <= sign_pipe0;
            sign_pipe2 <= sign_pipe1;

            exp_a_pipe0 <= exp_a_comb;
            exp_a_pipe1 <= exp_a_pipe0;
            exp_a_pipe2 <= exp_a_pipe1;

            exp_b_pipe0 <= exp_b_comb;
            exp_b_pipe1 <= exp_b_pipe0;
            exp_b_pipe2 <= exp_b_pipe1;
        end
    end

    assign R = {sign_pipe2, exp_r_comb, mantissa_r_comb};
    assign valid_out = approx_valid_out;

endmodule
