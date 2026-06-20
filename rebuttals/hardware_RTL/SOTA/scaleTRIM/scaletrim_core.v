//============================================================================
// scaleTRIM — Scalable TRuncation-Based Integer Approximate Multiplier
// Reference: "scaleTRIM: Scalable TRuncation-Based Integer Approximate
//             Multiplier With Linearization and Compensation" (IEEE Access 2026)
//
// Architecture:
//   1. Zero detection
//   2. Leading-one detection (LOD) for both operands → nA, nB
//   3. Barrel shifter to normalize operands
//   4. Truncation to h bits → Xh, Yh
//   5. Linearization: P_approx = (1 + 2^(-EE)) × (Xh + Yh) + Ci
//      where EE is pre-computed curve-fitting shift value
//   6. LUT-based error compensation (M segments on Xh+Yh)
//   7. Final shift by nA + nB to scale result
//
// Conf_Bit_Mask maps to (h, M) configurations:
//   L0: 6'b000001 → h=7, M=8 (most accurate, largest area)
//   L1: 6'b000011 → h=6, M=8
//   L2: 6'b000111 → h=5, M=4
//   L3: 6'b001111 → h=4, M=4
//   L4: 6'b011111 → h=3, M=2
//   L5: 6'b111111 → h=2, M=2 (least accurate, smallest area)
//============================================================================

module scaletrim_core
#(parameter WIDTH = 8)
(
    input  [WIDTH-1:0] A,
    input  [WIDTH-1:0] B,
    input  [WIDTH-3:0] Conf_Bit_Mask,
    output [2*WIDTH-1:0] P
);

    // ---- Leading-One Detector ----
    // Find position of the most significant '1' bit
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

    // ---- Determine (h, EE) from Conf_Bit_Mask ----
    reg [3:0] h_val;    // truncation width
    reg [3:0] ee_val;   // curve-fit shift value
    reg [WIDTH:0] comp_val; // compensation value

    // Count approximate level from conf mask
    reg [3:0] level;
    integer ki;
    always @(*) begin
        level = 0;
        for (ki = 0; ki < WIDTH-2; ki = ki + 1) begin
            if (Conf_Bit_Mask[ki])
                level = level + 1;
        end
    end

    always @(*) begin
        case (level)
            4'd0: begin h_val = 4'd7; ee_val = 4'd1; end // L0: h=7, EE=1
            4'd1: begin h_val = 4'd7; ee_val = 4'd1; end // L0 alias
            4'd2: begin h_val = 4'd6; ee_val = 4'd1; end // L1: h=6
            4'd3: begin h_val = 4'd5; ee_val = 4'd2; end // L2: h=5
            4'd4: begin h_val = 4'd4; ee_val = 4'd2; end // L3: h=4
            4'd5: begin h_val = 4'd3; ee_val = 4'd3; end // L4: h=3
            default: begin h_val = 4'd2; ee_val = 4'd3; end // L5: h=2
        endcase
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

    // ---- Normalize: shift left so MSB '1' is at position WIDTH-1 ----
    wire [WIDTH-1:0] X_norm, Y_norm;
    assign X_norm = A << (WIDTH - 1 - nA);
    assign Y_norm = B << (WIDTH - 1 - nB);

    // ---- Truncate to h bits (take h MSBs below the leading 1) ----
    // After normalization, bit [WIDTH-2] downward contains the fractional part
    // We take h bits starting from [WIDTH-2]
    reg [WIDTH-1:0] Xh, Yh;
    integer trunc_i;
    always @(*) begin
        Xh = {WIDTH{1'b0}};
        Yh = {WIDTH{1'b0}};
        for (trunc_i = 0; trunc_i < WIDTH-1; trunc_i = trunc_i + 1) begin
            if (trunc_i < h_val) begin
                Xh[trunc_i] = X_norm[WIDTH-2-trunc_i + trunc_i]; // keep top h bits
                Yh[trunc_i] = Y_norm[WIDTH-2-trunc_i + trunc_i];
            end
        end
        // Actually just mask: keep h MSBs of the fractional part
        Xh = (X_norm >> (WIDTH - 1 - h_val)) & ((1 << h_val) - 1);
        Yh = (Y_norm >> (WIDTH - 1 - h_val)) & ((1 << h_val) - 1);
    end

    // ---- Linearization: P_lin = (Xh + Yh) + ((Xh + Yh) >> EE) ----
    wire [WIDTH:0] sum_xy;
    assign sum_xy = {1'b0, Xh} + {1'b0, Yh};

    wire [WIDTH:0] shifted_sum;
    assign shifted_sum = sum_xy >> ee_val;

    wire [WIDTH+1:0] p_linear;
    assign p_linear = {1'b0, sum_xy} + {1'b0, shifted_sum};

    // ---- LUT-based Compensation ----
    // Segment the sum_xy space and add a pre-computed correction
    // Using 4 segments for simplicity (M=4)
    reg [WIDTH:0] compensation;
    always @(*) begin
        case (level)
            4'd0, 4'd1: begin // h=7, M=8 — fine compensation
                case (sum_xy[WIDTH:WIDTH-2])
                    3'd0: compensation = 1;
                    3'd1: compensation = 2;
                    3'd2: compensation = 3;
                    3'd3: compensation = 4;
                    3'd4: compensation = 5;
                    3'd5: compensation = 4;
                    3'd6: compensation = 3;
                    default: compensation = 2;
                endcase
            end
            4'd2: begin // h=6, M=8
                case (sum_xy[WIDTH:WIDTH-2])
                    3'd0: compensation = 2;
                    3'd1: compensation = 3;
                    3'd2: compensation = 5;
                    3'd3: compensation = 6;
                    3'd4: compensation = 7;
                    3'd5: compensation = 6;
                    3'd6: compensation = 4;
                    default: compensation = 3;
                endcase
            end
            4'd3: begin // h=5, M=4
                case (sum_xy[WIDTH:WIDTH-1])
                    2'd0: compensation = 3;
                    2'd1: compensation = 6;
                    2'd2: compensation = 8;
                    default: compensation = 5;
                endcase
            end
            4'd4: begin // h=4, M=4
                case (sum_xy[WIDTH:WIDTH-1])
                    2'd0: compensation = 5;
                    2'd1: compensation = 10;
                    2'd2: compensation = 12;
                    default: compensation = 8;
                endcase
            end
            4'd5: begin // h=3, M=2
                compensation = sum_xy[WIDTH] ? 15 : 8;
            end
            default: begin // h=2, M=2
                compensation = sum_xy[WIDTH] ? 20 : 12;
            end
        endcase
    end

    wire [WIDTH+1:0] p_compensated;
    assign p_compensated = p_linear + {1'b0, compensation};

    // ---- Final shift: result = (1 + p_compensated) << (nA + nB) ----
    wire [$clog2(WIDTH):0] total_shift;
    assign total_shift = {1'b0, nA} + {1'b0, nB};

    // The product of (1.Xh) × (1.Yh) needs to be scaled by 2^(nA+nB)
    // and the leading 1×1 = 1 is implicit
    wire [2*WIDTH-1:0] p_with_leading;
    assign p_with_leading = {{(WIDTH-2){1'b0}}, p_compensated};

    reg [2*WIDTH-1:0] p_shifted;
    always @(*) begin
        if (total_shift >= h_val)
            p_shifted = (p_with_leading << (total_shift - h_val)) & {(2*WIDTH){1'b1}};
        else
            p_shifted = p_with_leading >> (h_val - total_shift);
    end

    // Add the leading 1×1 term: 2^(nA+nB)
    wire [2*WIDTH-1:0] leading_term;
    assign leading_term = (total_shift >= WIDTH) ?
        ({1'b1, {(2*WIDTH-1){1'b0}}} >> (2*WIDTH - 1 - total_shift)) :
        ({{(WIDTH){1'b0}}, 1'b1, {(WIDTH-1){1'b0}}} >> (WIDTH - 1 - total_shift));

    assign P = any_zero ? {(2*WIDTH){1'b0}} : (p_shifted + leading_term);

endmodule
