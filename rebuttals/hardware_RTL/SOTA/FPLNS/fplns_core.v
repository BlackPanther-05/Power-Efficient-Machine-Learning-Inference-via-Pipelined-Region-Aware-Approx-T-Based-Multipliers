//============================================================================
// FPLNS — Mitchell/FPLNS Logarithmic Approximate Multiplier
// Reference: "Beyond Integer Quantization: Approximate Arithmetic for
//             Machine Learning Accelerators" (ICCD 2023)
//
// Architecture:
//   Mitchell's approximation: log2(1 + x) ≈ x + c
//   where c is a bias correction term.
//
//   For unsigned multiplication A × B:
//   1. Find leading-one positions nA, nB
//   2. Extract fractional parts xA, xB (bits below leading one)
//   3. log2(A) ≈ nA + xA + c
//   4. log2(B) ≈ nB + xB + c
//   5. log2(A×B) = log2(A) + log2(B) = (nA+nB) + (xA+xB) + 2c
//   6. Antilog: A×B ≈ 2^(nA+nB) × (1 + xA + xB + 2c)
//      If (xA+xB+2c) >= 1, add 1 to exponent and subtract 1 from fraction
//
// Conf_Bit_Mask controls configuration:
//   L0: 6'b000001 → c=0 (pure Mitchell)
//   L1: 6'b000011 → c=0.043 bias
//   L2: 6'b000111 → c=0.086 bias
//   L3: 6'b001111 → truncation to 6 fractional bits
//   L4: 6'b011111 → truncation to 4 fractional bits
//   L5: 6'b111111 → truncation to 2 fractional bits
//============================================================================

module fplns_core
#(parameter WIDTH = 8)
(
    input  [WIDTH-1:0] A,
    input  [WIDTH-1:0] B,
    input  [WIDTH-3:0] Conf_Bit_Mask,
    output [2*WIDTH-1:0] P
);

    // ---- Leading-One Detector ----
    function [$clog2(WIDTH)-1:0] lod;
        input [WIDTH-1:0] val;
        integer i;
        reg found;
        begin
            lod = 0;
            found = 0;
            for (i = WIDTH-1; i >= 0; i = i - 1) begin
                if (val[i] && !found) begin
                    lod = i[$clog2(WIDTH)-1:0];
                    found = 1;
                end
            end
        end
    endfunction

    // ---- Determine configuration level ----
    reg [3:0] level;
    integer ki;
    always @(*) begin
        level = 0;
        for (ki = 0; ki < WIDTH-2; ki = ki + 1) begin
            if (Conf_Bit_Mask[ki])
                level = level + 1;
        end
    end

    // ---- Zero Detection ----
    wire a_zero, b_zero, any_zero;
    assign a_zero = (A == {WIDTH{1'b0}});
    assign b_zero = (B == {WIDTH{1'b0}});
    assign any_zero = a_zero | b_zero;

    // ---- LOD ----
    wire [$clog2(WIDTH)-1:0] nA, nB;
    assign nA = lod(A);
    assign nB = lod(B);

    // ---- Extract fractional parts ----
    // After finding leading one at position n, the fractional part is
    // the bits below position n, left-justified to WIDTH-1 bits
    wire [WIDTH-1:0] fracA, fracB;
    assign fracA = (A << (WIDTH - nA)) >> 1;  // Remove leading 1, left-justify
    assign fracB = (B << (WIDTH - nB)) >> 1;

    // ---- Bias correction and truncation ----
    reg [WIDTH-1:0] bias_correction;
    reg [3:0] trunc_bits;

    always @(*) begin
        trunc_bits = WIDTH - 1;
        case (level)
            4'd0, 4'd1: begin bias_correction = 0;                        trunc_bits = WIDTH-1; end
            4'd2:        begin bias_correction = (1 << (WIDTH-1)) / 23;   trunc_bits = WIDTH-1; end
            4'd3:        begin bias_correction = (1 << (WIDTH-1)) / 12;   trunc_bits = WIDTH-1; end
            4'd4:        begin bias_correction = 0;                        trunc_bits = 4'd6;    end
            4'd5:        begin bias_correction = 0;                        trunc_bits = 4'd4;    end
            default:     begin bias_correction = 0;                        trunc_bits = 4'd2;    end
        endcase
    end

    // ---- Apply truncation mask ----
    reg [WIDTH-1:0] fracA_trunc, fracB_trunc;
    integer ti;
    always @(*) begin
        fracA_trunc = fracA;
        fracB_trunc = fracB;
        for (ti = 0; ti < WIDTH-1; ti = ti + 1) begin
            if (ti >= trunc_bits) begin
                fracA_trunc[WIDTH-2-ti] = 1'b0;
                fracB_trunc[WIDTH-2-ti] = 1'b0;
            end
        end
    end

    // ---- Mitchell Addition in Log Domain ----
    wire [WIDTH:0] frac_sum;
    assign frac_sum = {1'b0, fracA_trunc} + {1'b0, fracB_trunc}
                    + {1'b0, bias_correction} + {1'b0, bias_correction};

    // ---- Antilog Conversion ----
    wire carry;
    assign carry = frac_sum[WIDTH-1] | frac_sum[WIDTH];

    wire [$clog2(WIDTH):0] total_exp;
    assign total_exp = {1'b0, nA} + {1'b0, nB} + {{$clog2(WIDTH){1'b0}}, carry};

    wire [WIDTH-1:0] frac_result;
    assign frac_result = carry ? (frac_sum[WIDTH-1:0] - (1 << (WIDTH-1))) : frac_sum[WIDTH-1:0];

    // ---- Reconstruct Result ----
    // Result = (1 + frac_result/2^(WIDTH-1)) × 2^total_exp
    reg [2*WIDTH-1:0] result_val;
    always @(*) begin
        if (any_zero) begin
            result_val = {(2*WIDTH){1'b0}};
        end else begin
            // 2^total_exp (leading 1) + fractional contribution
            result_val = ({{(2*WIDTH-1){1'b0}}, 1'b1} << total_exp);
            // Add fractional part, properly shifted
            if (total_exp >= WIDTH-1)
                result_val = result_val + ({{(WIDTH){1'b0}}, frac_result} << (total_exp - (WIDTH-1)));
            else
                result_val = result_val + ({{(WIDTH){1'b0}}, frac_result} >> ((WIDTH-1) - total_exp));
        end
    end

    assign P = result_val;

endmodule
