//============================================================================
// OPACT [5] — Approximate 3:2 Compressor with Equally Weighted Outputs
// Reference: "OPACT: Optimization of Approximate Compressor Tree for
//             Approximate Multiplier" (DATE 2022)
//
// Truth table (approximate 3:2 compressor):
//   w1 = x0 | x1        (OR gate)
//   w2 = x2 & ~(x0 & x1) | (x0 & x1 & x2)
//      = x2 ^ (x0 & x1)  ... simplified
// Both outputs have the same weight as inputs (equally weighted).
//============================================================================

module opact_approx_compressor_3_2(
    input  x0,
    input  x1,
    input  x2,
    output w1,
    output w2
);
    // Approximate 3:2 compressor from [11] in OPACT paper
    // w1 and w2 have the same weight as inputs
    assign w1 = x0 | x1;
    assign w2 = x2 & ~(x0 & x1) | (x0 & x1 & x2);

endmodule
