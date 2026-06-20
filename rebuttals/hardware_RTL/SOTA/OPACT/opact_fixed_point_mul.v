//============================================================================
// OPACT [5] — Fixed Point Multiplier Wrapper
//============================================================================

module opact_fixed_point_mul
#(parameter WIDTH = 8,
  parameter DEC_POINT_POS = 4)
(
    input  signed [WIDTH-1:0] A,
    input  signed [WIDTH-1:0] B,
    input  [WIDTH-3:0] Conf_Bit_Mask,
    output signed [2*WIDTH-1:0] R
);

    wire sign_R;
    assign sign_R = A[WIDTH-1] ^ B[WIDTH-1];

    wire [WIDTH-1:0] mag_A, mag_B;
    assign mag_A = A[WIDTH-1] ? (~A[WIDTH-1:0] + 1) : A[WIDTH-1:0];
    assign mag_B = B[WIDTH-1] ? (~B[WIDTH-1:0] + 1) : B[WIDTH-1:0];

    wire [2*WIDTH-1:0] mag_R;
    opact_unsigned_int_mul #(WIDTH) m_opact_uint(
        .A(mag_A),
        .B(mag_B),
        .Conf_Bit_Mask(Conf_Bit_Mask),
        .R(mag_R)
    );

    wire signed [2*WIDTH-1:0] R0;
    assign R0 = sign_R ? (~mag_R + 1'b1) : mag_R;
    wire signed [2*WIDTH-1:0] R0_rounded = R0 + (1 << (DEC_POINT_POS - 1));
    assign R = R0_rounded >>> DEC_POINT_POS;

endmodule
