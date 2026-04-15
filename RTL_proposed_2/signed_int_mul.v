//Date: 2024/5/29
//Description: signed integer multiplication
//Note:        Pipelined RTL_proposed_2 variant.

module signed_int_mul
#(parameter WIDTH = 8)
(
    input clk,
    input rst_n,
    input valid_in,
    input signed [WIDTH-1:0] A,
    input signed [WIDTH-1:0] B,
    input [3:0] Region_Enable,
    input [15:0] Region_Conf_Mask,
    output valid_out,
    output signed [2*WIDTH-1:0] R
);
    wire sign_R_comb;
    wire [WIDTH-1:0] mag_A;
    wire [WIDTH-1:0] mag_B;

    assign sign_R_comb = A[WIDTH-1] ^ B[WIDTH-1];
    assign mag_A = A[WIDTH-1] ? (~A[WIDTH-1:0] + 1'b1) : A[WIDTH-1:0];
    assign mag_B = B[WIDTH-1] ? (~B[WIDTH-1:0] + 1'b1) : B[WIDTH-1:0];

    reg sign_pipe0;
    reg sign_pipe1;
    reg sign_pipe2;

    wire unsigned_valid_out;
    wire [2*WIDTH-1:0] mag_R;

    unsigned_int_mul #(WIDTH) m_unsigned_int_mul(
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .A(mag_A),
        .B(mag_B),
        .Region_Enable(Region_Enable),
        .Region_Conf_Mask(Region_Conf_Mask),
        .valid_out(unsigned_valid_out),
        .R(mag_R)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sign_pipe0 <= 1'b0;
            sign_pipe1 <= 1'b0;
            sign_pipe2 <= 1'b0;
        end else begin
            sign_pipe0 <= sign_R_comb;
            sign_pipe1 <= sign_pipe0;
            sign_pipe2 <= sign_pipe1;
        end
    end

    assign R = sign_pipe2 ? $signed(~mag_R + 1'b1) : $signed(mag_R);
    assign valid_out = unsigned_valid_out;

endmodule
