//============================================================================
// FPLNS — Floating Point Multiplier Wrapper (FP32)
// This is the native domain for FPLNS — direct exponent addition + 
// Mitchell approximation on mantissa
//============================================================================

module fplns_floating_point_mul(
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

    // ---- Determine configuration level from Conf_Bit_Mask ----
    reg [3:0] level;
    integer ki;
    always @(*) begin
        level = 0;
        for (ki = 0; ki < 22; ki = ki + 1) begin
            if (Conf_Bit_Mask[ki])
                level = level + 1;
        end
        // Normalize to 0-5 range
        if (level > 5) level = 5;
    end

    // ---- Mitchell Approximation for mantissa ----
    // (1 + mA) × (1 + mB) = 1 + mA + mB + mA×mB
    // Mitchell approx: ≈ 1 + mA + mB + c (drop the mA×mB cross-term, add bias c)
    
    reg [22:0] bias_c;
    reg [4:0] trunc_shift;
    always @(*) begin
        case (level)
            4'd0: begin bias_c = 23'd0;       trunc_shift = 5'd0;  end // Pure Mitchell
            4'd1: begin bias_c = 23'h040000;   trunc_shift = 5'd0;  end // c ≈ 0.03125
            4'd2: begin bias_c = 23'h080000;   trunc_shift = 5'd0;  end // c ≈ 0.0625
            4'd3: begin bias_c = 23'h0C0000;   trunc_shift = 5'd0;  end // c ≈ 0.09375
            4'd4: begin bias_c = 23'd0;        trunc_shift = 5'd8;  end // Truncate 8 LSBs
            default: begin bias_c = 23'd0;     trunc_shift = 5'd16; end // Truncate 16 LSBs
        endcase
    end

    // Apply truncation to mantissa
    reg [22:0] mant_a_t, mant_b_t;
    integer ti;
    always @(*) begin
        mant_a_t = mantissa_a;
        mant_b_t = mantissa_b;
        for (ti = 0; ti < 23; ti = ti + 1) begin
            if (ti < trunc_shift) begin
                mant_a_t[ti] = 1'b0;
                mant_b_t[ti] = 1'b0;
            end
        end
    end

    // Mitchell approximation: sum of mantissas + bias
    wire [23:0] mantissa_sum;
    assign mantissa_sum = {1'b0, mant_a_t} + {1'b0, mant_b_t} + {1'b0, bias_c};

    // Handle mantissa overflow (sum >= 1.0 in fractional representation)
    wire mantissa_carry;
    assign mantissa_carry = mantissa_sum[23];

    wire [22:0] mantissa_result;
    assign mantissa_result = mantissa_carry ? mantissa_sum[23:1] : mantissa_sum[22:0];

    // Exponent calculation
    wire [9:0] exp_sum;
    assign exp_sum = {2'b0, exp_a} + {2'b0, exp_b} - 10'd127 + {9'd0, mantissa_carry};

    // Overflow/underflow detection
    wire overflow, underflow;
    assign overflow = (~exp_sum[9] && exp_sum[8])
                   || (~exp_sum[9] && ~exp_sum[8] && (&exp_sum[7:0]));
    assign underflow = exp_sum[9];

    wire [22:0] mantissa_r;
    wire [7:0] exp_r;
    assign mantissa_r = overflow ? 23'h7fffff : (underflow ? 23'd0 : mantissa_result);
    assign exp_r = overflow ? 8'hfe : (underflow ? 8'h01 : exp_sum[7:0]);

    assign R = {sign_r, exp_r, mantissa_r};

endmodule
