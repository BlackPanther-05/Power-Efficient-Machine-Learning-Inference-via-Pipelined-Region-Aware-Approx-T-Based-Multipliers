//============================================================================
// FPLNS — Unsigned Integer Multiplier Wrapper
//============================================================================

module fplns_unsigned_int_mul
#(parameter WIDTH = 8)
(
    input  [WIDTH-1:0] A,
    input  [WIDTH-1:0] B,
    input  [WIDTH-3:0] Conf_Bit_Mask,
    output [2*WIDTH-1:0] R
);

    fplns_core #(WIDTH) m_core(
        .A(A),
        .B(B),
        .Conf_Bit_Mask(Conf_Bit_Mask),
        .P(R)
    );

endmodule
