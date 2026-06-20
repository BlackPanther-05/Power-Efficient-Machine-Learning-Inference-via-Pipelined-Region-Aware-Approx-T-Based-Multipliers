//============================================================================
// OPACT [5] — Unsigned Integer Multiplier Wrapper
// Same interface as RTL/unsigned_int_mul.v for drop-in comparison
//============================================================================

module opact_unsigned_int_mul
#(parameter WIDTH = 8)
(
    input  [WIDTH-1:0] A,
    input  [WIDTH-1:0] B,
    input  [WIDTH-3:0] Conf_Bit_Mask,
    output [2*WIDTH-1:0] R
);

    opact_mul_core #(WIDTH) m_opact_core(
        .A(A),
        .B(B),
        .Conf_Bit_Mask(Conf_Bit_Mask),
        .P(R)
    );

endmodule
