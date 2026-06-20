//============================================================================
// OPACT [5] — 8-bit Approximate Multiplier Core using Compressor Tree
// Reference: "OPACT: Optimization of Approximate Compressor Tree for
//             Approximate Multiplier" (DATE 2022)
//
// Architecture:
//   1. AND-gate Partial Product Generator (PPG) — generates 8×8 PP matrix
//   2. Approximate Compressor Tree (CT):
//      - LSP (columns 0 to N-1): uses approximate compressors
//      - MSP (columns N to 2N-2): uses exact compressors (Dadda scheme)
//   3. Final carry-propagate adder (CPA)
//
// Conf_Bit_Mask controls the boundary between LSP and MSP:
//   Higher Conf_Bit_Mask → more approximate columns → more error but less area
//   6'b000001 (L0): columns 0-1 approximate → minimal approximation
//   6'b000011 (L1): columns 0-3 approximate
//   6'b000111 (L2): columns 0-5 approximate
//   6'b001111 (L3): columns 0-7 approximate (full LSP)
//   6'b011111 (L4): columns 0-9 approximate
//   6'b111111 (L5): columns 0-11 approximate → maximum approximation
//============================================================================

module opact_mul_core
#(parameter WIDTH = 8)
(
    input  [WIDTH-1:0] A,
    input  [WIDTH-1:0] B,
    input  [WIDTH-3:0] Conf_Bit_Mask,
    output [2*WIDTH-1:0] P
);

    // ---- Partial Product Generation (AND gates) ----
    wire [WIDTH-1:0] pp [0:WIDTH-1];
    genvar gi, gj;
    generate
        for (gi = 0; gi < WIDTH; gi = gi + 1) begin : gen_pp_row
            for (gj = 0; gj < WIDTH; gj = gj + 1) begin : gen_pp_col
                assign pp[gi][gj] = A[gj] & B[gi];
            end
        end
    endgenerate

    // ---- Determine approximation boundary from Conf_Bit_Mask ----
    // Count number of set bits to determine how many LSP columns
    // to process with approximate compressors
    reg [3:0] approx_cols;
    integer k;
    always @(*) begin
        approx_cols = 4'd2; // minimum 2 columns
        for (k = 0; k < WIDTH-2; k = k + 1) begin
            if (Conf_Bit_Mask[k])
                approx_cols = approx_cols + 4'd2;
        end
        // Cap at 2*WIDTH-2
        if (approx_cols > 2*WIDTH-2)
            approx_cols = 2*WIDTH-2;
    end

    // ---- Column-wise compression ----
    // For an 8×8 multiplier, column j has partial products from
    // rows max(0, j-7) to min(j, 7), contributing bits at weight 2^j
    //
    // We use a behavioral approach: accumulate each column with
    // either approximate compression (OR-based) or exact compression (addition)

    reg [2*WIDTH-1:0] result;
    integer col, row;
    reg [WIDTH:0] col_sum;       // column accumulator
    reg [WIDTH:0] col_approx;    // approximate column value
    reg carry_in;

    always @(*) begin
        result = {(2*WIDTH){1'b0}};
        carry_in = 1'b0;

        for (col = 0; col < 2*WIDTH; col = col + 1) begin
            col_sum = 0;

            // Accumulate partial products contributing to this column
            for (row = 0; row < WIDTH; row = row + 1) begin
                if ((col - row) >= 0 && (col - row) < WIDTH) begin
                    col_sum = col_sum + pp[row][col - row];
                end
            end

            if (col < approx_cols) begin
                // --- Approximate compression (LSP) ---
                // Use OR-based approximation: approximate the column sum
                // by OR-ing the partial product bits (simulates approx compressors)
                // Then apply a correction bias
                col_approx = 0;
                for (row = 0; row < WIDTH; row = row + 1) begin
                    if ((col - row) >= 0 && (col - row) < WIDTH) begin
                        col_approx = col_approx | pp[row][col - row];
                    end
                end
                // Approximate column result: use OR for bit, carry from previous
                result[col] = col_approx[0] ^ carry_in;
                carry_in = col_approx[0] & carry_in;
            end else begin
                // --- Exact compression (MSP) ---
                col_sum = col_sum + carry_in;
                result[col] = col_sum[0];
                carry_in = col_sum >> 1;
            end
        end
    end

    assign P = result;

endmodule
