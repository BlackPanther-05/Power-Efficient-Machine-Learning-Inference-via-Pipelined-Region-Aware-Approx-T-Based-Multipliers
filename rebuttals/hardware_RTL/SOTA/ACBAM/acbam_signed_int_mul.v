//============================================================================
// ACBAM — Signed Integer Multiplier Wrapper
//============================================================================

module acbam_signed_int_mul
#(parameter WIDTH = 8)
(
    input  signed [WIDTH-1:0] A,
    input  signed [WIDTH-1:0] B,
    input  [WIDTH-3:0] Conf_Bit_Mask,
    output signed [2*WIDTH-1:0] R
);

    wire sign_R;
    assign sign_R = A[WIDTH-1] ^ B[WIDTH-1];

    wire [WIDTH-1:0] mag_A, mag_B;
    assign mag_A = A[WIDTH-1] ? (~A[WIDTH-1:0] + 1'b1) : A[WIDTH-1:0];
    assign mag_B = B[WIDTH-1] ? (~B[WIDTH-1:0] + 1'b1) : B[WIDTH-1:0];

    wire [2*WIDTH-1:0] mag_R;
    acbam_unsigned_int_mul #(WIDTH) m_uint(
        .A(mag_A),
        .B(mag_B),
        .Conf_Bit_Mask(Conf_Bit_Mask),
        .R(mag_R)
    );

    assign R = sign_R ? (~mag_R + 1'b1) : mag_R;

endmodule
