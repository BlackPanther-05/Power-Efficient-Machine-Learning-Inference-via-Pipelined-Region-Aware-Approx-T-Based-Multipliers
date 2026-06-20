//============================================================================
// OPACT [5] — Approximate 4:2 Compressor with Equally Weighted Outputs
// Reference: "OPACT: Optimization of Approximate Compressor Tree for
//             Approximate Multiplier" (DATE 2022)
//
// Approximate 4:2 compressor from [11] referenced in OPACT paper.
// Both outputs w1, w2 have the same weight as the inputs.
//   w1 = x1 | x0 | (x3 & x2)
//   w2 = x2 | x3 | (x1 & x0)
// This is a simplified approximate compressor that reduces 4 bits
// at a given column position to 2 bits at the same column.
//============================================================================

module opact_approx_compressor_4_2(
    input  x0,
    input  x1,
    input  x2,
    input  x3,
    output w1,
    output w2
);
    // Approximate 4:2 compressor — both outputs same weight as inputs
    assign w1 = x1 | x0 | (x3 & x2);
    assign w2 = x2 | x3 | (x1 & x0);

endmodule
