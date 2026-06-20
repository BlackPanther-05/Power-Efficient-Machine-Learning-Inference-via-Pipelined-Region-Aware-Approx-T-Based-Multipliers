//============================================================================
// scaleTRIM — Floating Point Multiplier Wrapper (FP32)
//============================================================================

module scaletrim_floating_point_mul(
    input  [31:0] A,
    input  [31:0] B,
    input  [21:0] Conf_Bit_Mask,
    output [31:0] R
);

    wire sign_r;
    assign sign_r = A[31] ^ B[31];

    wire [7:0] exp_a, exp_b;
    assign exp_a = A[30:23];
    assign exp_b = B[30:23];

    wire [22:0] mantissa_a, mantissa_b;
    assign mantissa_a = A[22:0];
    assign mantissa_b = B[22:0];

    // Use 24-bit scaleTRIM core for mantissa multiplication
    wire [47:0] mantissa_product;
    scaletrim_core #(24) m_core(
        .A({1'b1, mantissa_a}),
        .B({1'b1, mantissa_b}),
        .Conf_Bit_Mask(Conf_Bit_Mask),
        .P(mantissa_product)
    );

    wire [1:0] shift;
    assign shift = mantissa_product[47:46];

    wire [22:0] mantissa_out;
    assign mantissa_out = shift[1] ? mantissa_product[46:24] :
                          shift[0] ? mantissa_product[45:23] :
                                     mantissa_product[44:22];

    wire [9:0] exp_overflow;
    assign exp_overflow = {2'b0, exp_a} + {2'b0, exp_b}
                        + {8'b11100000, shift[1], shift[0] && ~shift[1]};

    wire overflow;
    assign overflow = (~exp_overflow[9] && exp_overflow[8])
                   || (~exp_overflow[9] && ~exp_overflow[8] && (&exp_overflow[7:0]));
    wire underflow;
    assign underflow = exp_overflow[9] && exp_overflow[8];

    wire [22:0] mantissa_r;
    wire [7:0] exp_r;
    assign mantissa_r = overflow ? 23'h7fffff : (underflow ? 23'd0 : mantissa_out);
    assign exp_r = overflow ? 8'hfe : (underflow ? 8'h01 : exp_overflow[7:0]);

    assign R = {sign_r, exp_r, mantissa_r};

endmodule
