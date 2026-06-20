//============================================================================
// ACBAM — Accuracy-Configurable Sign Inclusive Broken Array Booth Multiplier
// Reference: "ACBAM: Accuracy-Configurable Sign Inclusive Broken Array 
//             Booth Multiplier Design" (IEEE TETC 2022)
//
// Architecture (adapted for 8-bit):
//   1. Modified Radix-4 Booth Encoding of multiplier B
//   2. Partial Product Array generation
//   3. Horizontal break (parameter k): eliminate k LSB partial products
//   4. Vertical break (parameter m): truncate m LSBs from PP rows
//   5. Sign-bit correction: add discarded sign bits to improve accuracy
//   6. Carry-Propagate Addition of remaining partial products
//
// For 8-bit, we have 4 Booth-encoded partial products (radix-4).
// Conf_Bit_Mask maps to (k, m) accuracy modes:
//   L0: 6'b000001 → k=0, m=0 (exact — no breaks)
//   L1: 6'b000011 → k=0, m=2 (small vertical break)
//   L2: 6'b000111 → k=1, m=2 (1 PP eliminated + vertical break)
//   L3: 6'b001111 → k=1, m=4
//   L4: 6'b011111 → k=2, m=4
//   L5: 6'b111111 → k=2, m=6 (maximum approximation)
//============================================================================

module acbam_core
#(parameter WIDTH = 8)
(
    input  [WIDTH-1:0] A,
    input  [WIDTH-1:0] B,
    input  [WIDTH-3:0] Conf_Bit_Mask,
    output [2*WIDTH-1:0] P
);

    // ---- Determine (k, m) from Conf_Bit_Mask ----
    reg [3:0] k_val;  // horizontal break
    reg [3:0] m_val;  // vertical break

    reg [3:0] level;
    integer li;
    always @(*) begin
        level = 0;
        for (li = 0; li < WIDTH-2; li = li + 1) begin
            if (Conf_Bit_Mask[li])
                level = level + 1;
        end
    end

    always @(*) begin
        case (level)
            4'd0, 4'd1: begin k_val = 4'd0; m_val = 4'd0; end
            4'd2:        begin k_val = 4'd0; m_val = 4'd2; end
            4'd3:        begin k_val = 4'd1; m_val = 4'd2; end
            4'd4:        begin k_val = 4'd1; m_val = 4'd4; end
            4'd5:        begin k_val = 4'd2; m_val = 4'd4; end
            default:     begin k_val = 4'd2; m_val = 4'd6; end
        endcase
    end

    // ---- Booth Encoding Function ----
    // Extracts partial product for a Booth digit
    function [2*WIDTH-1:0] booth_pp;
        input [WIDTH-1:0] multiplicand;
        input [2:0] bits;
        input [3:0] shift_amt;
        reg [WIDTH:0] pp_mag;
        reg pp_neg;
        reg [2*WIDTH-1:0] pp_shifted;
        begin
            case (bits)
                3'b000: begin pp_mag = 0;                          pp_neg = 0; end
                3'b001: begin pp_mag = {1'b0, multiplicand};       pp_neg = 0; end
                3'b010: begin pp_mag = {1'b0, multiplicand};       pp_neg = 0; end
                3'b011: begin pp_mag = {multiplicand, 1'b0};       pp_neg = 0; end
                3'b100: begin pp_mag = {multiplicand, 1'b0};       pp_neg = 1; end
                3'b101: begin pp_mag = {1'b0, multiplicand};       pp_neg = 1; end
                3'b110: begin pp_mag = {1'b0, multiplicand};       pp_neg = 1; end
                3'b111: begin pp_mag = 0;                          pp_neg = 0; end
            endcase
            
            // Sign-extend and shift
            pp_shifted = {{(WIDTH-1){1'b0}}, pp_mag} << shift_amt;
            
            if (pp_neg)
                booth_pp = ~pp_shifted + 1;
            else
                booth_pp = pp_shifted;
        end
    endfunction

    // ---- Booth encoding for each PP ----
    // B extended with 0 at LSB
    wire [WIDTH:0] B_ext;
    assign B_ext = {B, 1'b0};

    // Extract Booth triplets
    wire [2:0] bt0, bt1, bt2, bt3;
    assign bt0 = B_ext[2:0];
    assign bt1 = B_ext[4:2];
    assign bt2 = B_ext[6:4];
    assign bt3 = B_ext[8:6];

    // Generate partial products
    wire [2*WIDTH-1:0] pp0, pp1, pp2, pp3;
    assign pp0 = booth_pp(A, bt0, 4'd0);
    assign pp1 = booth_pp(A, bt1, 4'd2);
    assign pp2 = booth_pp(A, bt2, 4'd4);
    assign pp3 = booth_pp(A, bt3, 4'd6);

    // ---- Apply breaks and accumulate ----
    reg [2*WIDTH-1:0] pp0_masked, pp1_masked, pp2_masked, pp3_masked;
    integer mi;

    always @(*) begin
        // Start with full partial products
        pp0_masked = pp0;
        pp1_masked = pp1;
        pp2_masked = pp2;
        pp3_masked = pp3;

        // Horizontal break: eliminate lower PPs
        if (k_val >= 1) pp0_masked = 0;
        if (k_val >= 2) pp1_masked = 0;
        if (k_val >= 3) pp2_masked = 0;

        // Vertical break: zero out m LSBs
        for (mi = 0; mi < 2*WIDTH; mi = mi + 1) begin
            if (mi < m_val) begin
                pp0_masked[mi] = 1'b0;
                pp1_masked[mi] = 1'b0;
                pp2_masked[mi] = 1'b0;
                pp3_masked[mi] = 1'b0;
            end
        end
    end

    // ---- Sign-bit correction ----
    // When PPs are eliminated by horizontal break, their sign information
    // is lost. Partially correct by adding sign bits back at the break boundary.
    reg [2*WIDTH-1:0] sign_correction;
    always @(*) begin
        sign_correction = 0;
        // Add sign correction at the vertical break boundary
        if (k_val >= 1 && bt0[2]) begin
            sign_correction[m_val] = 1'b1;
        end
        if (k_val >= 2 && bt1[2]) begin
            sign_correction[m_val + 2] = 1'b1;
        end
    end

    // ---- Final accumulation ----
    wire [2*WIDTH-1:0] sum_result;
    assign sum_result = pp0_masked + pp1_masked + pp2_masked + pp3_masked + sign_correction;

    wire [2*WIDTH-1:0] unsigned_correction;
    assign unsigned_correction = B[WIDTH-1] ? ({ {(WIDTH){1'b0}}, A } << WIDTH) : 0;

    assign P = sum_result + unsigned_correction;

endmodule
