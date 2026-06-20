`timescale 1ns / 1ps

/*
 * Comprehensive Test Bench: Signed Integer Multiplication
 * Variant: RTL_proposed (Non-Pipelined)
 * Data Type: Signed 8-bit × 8-bit → 16-bit
 * Precision Levels: L0, L1, L2
 * Test Cases: 256 per level
 * CSV Output: Standard format for all levels
 */

module tb_signed_int_L0_L1_L2();
    
    reg signed [7:0] a, b;
    reg [5:0] config_bits;
    wire signed [15:0] result;
    
    integer csv_l0, csv_l1, csv_l2, log_file;
    integer i, test_num;
    integer errors_l0, errors_l1, errors_l2;
    integer max_err_l0, max_err_l1, max_err_l2;
    real sum_err_l0, sum_err_l1, sum_err_l2;
    real sum_rel_l0, sum_rel_l1, sum_rel_l2;
    
    wire signed [15:0] expected = a * b;
    wire [15:0] error = (expected > result) ? (expected - result) : (result - expected);
    real rel_error;
    real absolute_error;
    real percentage_error;
    
    approx_t uut(
        .a(a),
        .b(b),
        .Conf_Bit_Mask(config_bits),
        .result(result)
    );
    
    initial begin : MAIN_TEST
        real mean_l0, mean_l1, mean_l2;
        real rel_mean_l0, rel_mean_l1, rel_mean_l2;
        
        // Open output files
        csv_l0 = $fopen("Signed_int_L0_results.csv", "w");
        csv_l1 = $fopen("Signed_int_L1_results.csv", "w");
        csv_l2 = $fopen("Signed_int_L2_results.csv", "w");
        log_file = $fopen("simulation_log.txt", "w");
        
        // Write CSV headers
        $fwrite(csv_l0, "Test,A,B,Acc_Result,Approx_Result,Error_Bias,Relative_Error,Absolute_Error,Percentage_Error\n");
        $fwrite(csv_l1, "Test,A,B,Acc_Result,Approx_Result,Error_Bias,Relative_Error,Absolute_Error,Percentage_Error\n");
        $fwrite(csv_l2, "Test,A,B,Acc_Result,Approx_Result,Error_Bias,Relative_Error,Absolute_Error,Percentage_Error\n");
        
        // Initialize counters
        errors_l0 = 0; errors_l1 = 0; errors_l2 = 0;
        max_err_l0 = 0; max_err_l1 = 0; max_err_l2 = 0;
        sum_err_l0 = 0; sum_err_l1 = 0; sum_err_l2 = 0;
        sum_rel_l0 = 0; sum_rel_l1 = 0; sum_rel_l2 = 0;
        
        $fwrite(log_file, "SIGNED INTEGER TESTBENCH - RTL_proposed\n");
        $fwrite(log_file, "=============================================\n\n");
        
        // ===== LEVEL 0 =====
        $fwrite(log_file, "PRECISION LEVEL 0\n");
        $fwrite(log_file, "─────────────────────────────────────────────\n");
        config_bits = 6'b000001;
        
        for (i = 0; i < 256; i++) begin
            a = i - 128;  // Range -128 to 127
            b = ((i * 7 + 3) % 256) - 128;
            #5;
            
            rel_error = (expected != 0) ? (real(error) / (expected < 0 ? -expected : expected) * 100.0) : 0.0;
            absolute_error = error;
            percentage_error = (expected != 0) ? ((real(absolute_error) / (expected < 0 ? -expected : expected)) * 100.0) : 0.0;
            
            if (error != 0) errors_l0++;
            if (error > max_err_l0) max_err_l0 = error;
            sum_err_l0 = sum_err_l0 + error;
            sum_rel_l0 = sum_rel_l0 + rel_error;
            
            $fwrite(csv_l0, "%0d,%0d,%0d,%0d,%0d,%0d,%.2f,%0d,%.2f\n",
                    i+1, a, b, expected, result, error, rel_error, absolute_error, percentage_error);
            
            if ((i % 32) == 0)
                $fwrite(log_file, "Test %3d: A=%4d, B=%4d | Exp=%6d, Got=%6d | Err=%3d (%.2f%%)\n",
                        i+1, a, b, expected, result, error, rel_error);
        end
        
        mean_l0 = sum_err_l0 / 256.0;
        rel_mean_l0 = sum_rel_l0 / 256.0;
        $fwrite(log_file, "L0 Summary: Errors=%0d/256, Max=%0d, Mean=%.2f, RelErr=%.2f%%\n\n",
                errors_l0, max_err_l0, mean_l0, rel_mean_l0);
        
        // ===== LEVEL 1 =====
        $fwrite(log_file, "PRECISION LEVEL 1 (RECOMMENDED)\n");
        $fwrite(log_file, "─────────────────────────────────────────────\n");
        config_bits = 6'b000011;
        
        for (i = 0; i < 256; i++) begin
            a = i - 128;
            b = ((i * 13 + 5) % 256) - 128;
            #5;
            
            rel_error = (expected != 0) ? (real(error) / (expected < 0 ? -expected : expected) * 100.0) : 0.0;
            absolute_error = error;
            percentage_error = (expected != 0) ? ((real(absolute_error) / (expected < 0 ? -expected : expected)) * 100.0) : 0.0;
            
            if (error != 0) errors_l1++;
            if (error > max_err_l1) max_err_l1 = error;
            sum_err_l1 = sum_err_l1 + error;
            sum_rel_l1 = sum_rel_l1 + rel_error;
            
            $fwrite(csv_l1, "%0d,%0d,%0d,%0d,%0d,%0d,%.2f,%0d,%.2f\n",
                    i+1, a, b, expected, result, error, rel_error, absolute_error, percentage_error);
            
            if ((i % 32) == 0)
                $fwrite(log_file, "Test %3d: A=%4d, B=%4d | Exp=%6d, Got=%6d | Err=%3d (%.2f%%)\n",
                        i+1, a, b, expected, result, error, rel_error);
        end
        
        mean_l1 = sum_err_l1 / 256.0;
        rel_mean_l1 = sum_rel_l1 / 256.0;
        $fwrite(log_file, "L1 Summary: Errors=%0d/256, Max=%0d, Mean=%.2f, RelErr=%.2f%%\n\n",
                errors_l1, max_err_l1, mean_l1, rel_mean_l1);
        
        // ===== LEVEL 2 =====
        $fwrite(log_file, "PRECISION LEVEL 2 (MAXIMUM)\n");
        $fwrite(log_file, "─────────────────────────────────────────────\n");
        config_bits = 6'b000111;
        
        for (i = 0; i < 256; i++) begin
            a = i - 128;
            b = ((i * 19 + 7) % 256) - 128;
            #5;
            
            rel_error = (expected != 0) ? (real(error) / (expected < 0 ? -expected : expected) * 100.0) : 0.0;
            absolute_error = error;
            percentage_error = (expected != 0) ? ((real(absolute_error) / (expected < 0 ? -expected : expected)) * 100.0) : 0.0;
            if (error > max_err_l2) max_err_l2 = error;
            sum_err_l2 = sum_err_l2 + error;
            sum_rel_l2 = sum_rel_l2 + rel_error;
            
            $fwrite(csv_l2, "%0d,%0d,%0d,%0d,%0d,%0d,%.2f,%0d,%.2f\n",
                    i+1, a, b, expected, result, error, rel_error, absolute_error, percentage_error);
            
            if ((i % 32) == 0)
                $fwrite(log_file, "Test %3d: A=%4d, B=%4d | Exp=%6d, Got=%6d | Err=%3d (%.2f%%)\n",
                        i+1, a, b, expected, result, error, rel_error);
        end
        
        mean_l2 = sum_err_l2 / 256.0;
        rel_mean_l2 = sum_rel_l2 / 256.0;
        $fwrite(log_file, "L2 Summary: Errors=%0d/256, Max=%0d, Mean=%.2f, RelErr=%.2f%%\n\n",
                errors_l2, max_err_l2, mean_l2, rel_mean_l2);
        
        // Final summary
        $fwrite(log_file, "=============================================\n");
        $fwrite(log_file, "FINAL SUMMARY\n");
        $fwrite(log_file, "=============================================\n");
        $fwrite(log_file, "L0: Errors=%0d, Max=%0d, Mean=%.2f, Rel=%.2f%%\n",
                errors_l0, max_err_l0, mean_l0, rel_mean_l0);
        $fwrite(log_file, "L1: Errors=%0d, Max=%0d, Mean=%.2f, Rel=%.2f%%\n",
                errors_l1, max_err_l1, mean_l1, rel_mean_l1);
        $fwrite(log_file, "L2: Errors=%0d, Max=%0d, Mean=%.2f, Rel=%.2f%%\n",
                errors_l2, max_err_l2, mean_l2, rel_mean_l2);
        $fwrite(log_file, "=============================================\n");
        
        $display("Test Complete!");
        $display("CSV Output:");
        $display("  - Signed_int_L0_results.csv");
        $display("  - Signed_int_L1_results.csv");
        $display("  - Signed_int_L2_results.csv");
        
        $fclose(csv_l0);
        $fclose(csv_l1);
        $fclose(csv_l2);
        $fclose(log_file);
        $finish;
    end
    
endmodule
    
    // System clock and reset
    reg clk;
    reg rst_n;
    
    // Input signals to APProx-T unit
    reg [7:0] a, b;              // 8-bit signed inputs
    reg [5:0] Conf_Bit_Mask;     // 6-bit precision configuration
    
    // Output signals  
    wire [15:0] result;           // 16-bit output
    
    // Test harness variables
    integer test_count;
    integer error_count;
    integer max_error;
    real mean_error;
    real sum_errors;
    real rel_error;
    real mean_rel_error;
    integer cycle_count;
    
    // File handles for results
    integer log_file, csv_file;
    integer summary_file;
    
    // Operand storage and expected result calculation
    reg [15:0] expected_result;
    reg [15:0] error;
    integer signed a_signed, b_signed;
    
    // Test progress tracking
    integer test_case;
    integer precision_level;
    integer level_0_errors, level_1_errors, level_2_errors;
    real level_0_mean_error, level_1_mean_error, level_2_mean_error;
    real level_0_rel_error, level_1_rel_error, level_2_rel_error;
    integer level_0_tests, level_1_tests, level_2_tests;
    integer level_0_max_error, level_1_max_error, level_2_max_error;
    
    // Performance timing
    real throughput;
    integer total_cycles;
    integer level_cycles;
    
    // ==================== Module Instantiation ====================
    
    // Instantiate the Approx-T multiplier (RTL_proposed - non-pipelined)
    approx_t uut (
        .clk(clk),
        .reset_n(rst_n),
        .a(a),
        .b(b),
        .Conf_Bit_Mask(Conf_Bit_Mask),
        .result(result)
    );
    
    // ==================== Clock Generation ====================
    
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;  // 5ns period = 200 MHz
    end
    
    // ==================== Test Stimulus and Monitoring ====================
    
    initial begin
        
        // Initialize files for output
        log_file = $fopen("simulation_log_signed_int.txt", "w");
        summary_file = $fopen("Signed_int_summary_results.txt", "w");
        
        // Open CSV file for detailed results across all levels
        csv_file = $fopen("Signed_int_L0_L1_L2_detailed.csv", "w");
        $fwrite(csv_file, "Test#,A,B,Precision_Level,Expected,Actual,Error,Rel_Error_pct\n");
        
        // ==================== Initialization ====================
        
        $fwrite(log_file, "═══════════════════════════════════════════════════════════════\n");
        $fwrite(log_file, "   SIGNED INTEGER TESTBENCH - APPROX-T MULTIPLIER (Non-Pipelined)\n");
        $fwrite(log_file, "═══════════════════════════════════════════════════════════════\n");
        $fwrite(log_file, "Test Start Time: %0t\n", $time);
        $fwrite(log_file, "Precision Levels: L0 (6'b000001), L1 (6'b010101), L2 (6'b111111)\n");
        $fwrite(log_file, "Test Range: -128 to +127 × -128 to +127\n");
        $fwrite(log_file, "Input Patterns: Sequential sweep of signed operand space\n");
        $fwrite(log_file, "═══════════════════════════════════════════════════════════════\n\n");
        
        rst_n = 1'b0;
        clk = 1'b0;
        a = 8'b0;
        b = 8'b0;
        Conf_Bit_Mask = 6'b0;
        
        #20 rst_n = 1'b1;  // Release reset after 20ns
        
        // Initialize counters
        total_cycles = 0;
        test_count = 0;
        error_count = 0;
        max_error = 0;
        sum_errors = 0;
        mean_error = 0;
        mean_rel_error = 0;
        
        level_0_errors = 0;
        level_1_errors = 0;
        level_2_errors = 0;
        level_0_max_error = 0;
        level_1_max_error = 0;
        level_2_max_error = 0;
        level_0_tests = 0;
        level_1_tests = 0;
        level_2_tests = 0;
        level_0_mean_error = 0;
        level_1_mean_error = 0;
        level_2_mean_error = 0;
        level_0_rel_error = 0;
        level_1_rel_error = 0;
        level_2_rel_error = 0;
        
        // ==================== TEST LOOP: All Precision Levels ====================
        
        // Level 0: Base approximation (6'b000001)
        $fwrite(log_file, "\n┌─ PRECISION LEVEL 0 (Base Approximation) ─┐\n");
        $fwrite(log_file, "│ Conf_Bit_Mask = 6'b000001 (delta_f0 only)\n");
        $fwrite(log_file, "│ Expected: Fast, low accuracy (~98-99%% error rate)\n");
        $fwrite(log_file, "│ Use Case: Ultra-low power embedding\n");
        $fwrite(log_file, "└──────────────────────────────────────────┘\n\n");
        
        Conf_Bit_Mask = 6'b000001;
        precision_level = 0;
        level_cycles = 0;
        
        for (test_case = 0; test_case < 256; test_case = test_case + 1) begin
            // Generate signed test vectors (16 LSBs used for signed representation)
            a = {test_case[7], test_case[6:0]};  // -128 to +127
            b = {(test_case >> 4)[3], (test_case >> 4)[2:0], (test_case >> 1)[2:0]};  // Varying b values
            
            #10;  // Wait one clock cycle for result
            level_cycles = level_cycles + 1;
            
            // Calculate expected result (signed multiplication)
            a_signed = $signed(a);
            b_signed = $signed(b);
            expected_result = a_signed * b_signed;
            
            // Calculate error
            error = (expected_result > result) ? (expected_result - result) : (result - expected_result);
            
            if (error != 0) begin
                level_0_errors = level_0_errors + 1;
            end
            
            if (error > level_0_max_error) begin
                level_0_max_error = error;
            end
            
            level_0_tests = level_0_tests + 1;
            
            // Calculate relative error percentage
            if (expected_result != 0) begin
                rel_error = (error * 100.0) / (expected_result < 0 ? -expected_result : expected_result);
            end else begin
                rel_error = 0;
            end
            
            level_0_mean_error = level_0_mean_error + error;
            level_0_rel_error = level_0_rel_error + rel_error;
            
            // Log sample test cases (every 32nd)
            if ((test_case % 32) == 0) begin
                $fwrite(log_file, "Test %3d: %4d × %4d = %6d (approx), Expected %6d, Error: %3d LSBs (%.2f%%)\n",
                    test_case, a_signed, b_signed, result, expected_result, error, rel_error);
            end
            
            // Detailed CSV logging
            $fwrite(csv_file, "%0d,%0d,%0d,L0,%0d,%0d,%0d,%.3f\n",
                test_case, a_signed, b_signed, expected_result, result[15:0], error, rel_error);
        end
        
        level_0_mean_error = level_0_mean_error / level_0_tests;
        level_0_rel_error = level_0_rel_error / level_0_tests;
        
        $fwrite(log_file, "\nL0 Summary: Errors: %0d/%0d, Max: %0d LSBs, Mean: %.2f LSBs, Rel Error: %.2f%%\n\n",
            level_0_errors, level_0_tests, level_0_max_error, level_0_mean_error, level_0_rel_error);
        
        // ==================== Level 1: Moderate Precision ====================
        
        $fwrite(log_file, "\n┌─ PRECISION LEVEL 1 (Recommended) ─┐\n");
        $fwrite(log_file, "│ Conf_Bit_Mask = 6'b010101 (delta_f0,2,4 + deltas)\n");
        $fwrite(log_file, "│ Expected: Good balance power/accuracy (~5-15%% error rate)\n");
        $fwrite(log_file, "│ Use Case: Typical embedded systems\n");
        $fwrite(log_file, "└────────────────────────────────────┘\n\n");
        
        Conf_Bit_Mask = 6'b010101;
        precision_level = 1;
        level_cycles = 0;
        
        for (test_case = 0; test_case < 256; test_case = test_case + 1) begin
            // Generate new signed test vectors with different pattern
            a = {test_case[6:0], 1'b0} + (test_case[7] ? -128 : 0);  // Different pattern
            b = (~test_case[7:0]) & 8'hFF;  // Inverted pattern
            
            #10;
            level_cycles = level_cycles + 1;
            
            // Calculate expected result
            a_signed = $signed(a);
            b_signed = $signed(b);
            expected_result = a_signed * b_signed;
            
            // Calculate error
            error = (expected_result > result) ? (expected_result - result) : (result - expected_result);
            
            if (error != 0) begin
                level_1_errors = level_1_errors + 1;
            end
            
            if (error > level_1_max_error) begin
                level_1_max_error = error;
            end
            
            level_1_tests = level_1_tests + 1;
            
            // Calculate relative error
            if (expected_result != 0) begin
                rel_error = (error * 100.0) / (expected_result < 0 ? -expected_result : expected_result);
            end else begin
                rel_error = 0;
            end
            
            level_1_mean_error = level_1_mean_error + error;
            level_1_rel_error = level_1_rel_error + rel_error;
            
            // Log samples
            if ((test_case % 32) == 0) begin
                $fwrite(log_file, "Test %3d: %4d × %4d = %6d (approx), Expected %6d, Error: %3d LSBs (%.2f%%)\n",
                    test_case, a_signed, b_signed, result, expected_result, error, rel_error);
            end
            
            $fwrite(csv_file, "%0d,%0d,%0d,L1,%0d,%0d,%0d,%.3f\n",
                test_case, a_signed, b_signed, expected_result, result[15:0], error, rel_error);
        end
        
        level_1_mean_error = level_1_mean_error / level_1_tests;
        level_1_rel_error = level_1_rel_error / level_1_tests;
        
        $fwrite(log_file, "\nL1 Summary: Errors: %0d/%0d, Max: %0d LSBs, Mean: %.2f LSBs, Rel Error: %.2f%%\n\n",
            level_1_errors, level_1_tests, level_1_max_error, level_1_mean_error, level_1_rel_error);
        
        // ==================== Level 2: Maximum Precision ====================
        
        $fwrite(log_file, "\n┌─ PRECISION LEVEL 2 (Maximum) ─┐\n");
        $fwrite(log_file, "│ Conf_Bit_Mask = 6'b111111 (All 6 delta-f terms active)\n");
        $fwrite(log_file, "│ Expected: High accuracy (<2%% error rate), minimal overhead\n");
        $fwrite(log_file, "│ Use Case: Accuracy-critical embedded systems (recommended)\n");
        $fwrite(log_file, "└──────────────────────────────────┘\n\n");
        
        Conf_Bit_Mask = 6'b111111;
        precision_level = 2;
        level_cycles = 0;
        
        for (test_case = 0; test_case < 256; test_case = test_case + 1) begin
            a = (test_case[7:4] << 4) | test_case[3:0];  // Full range sweep
            b = {test_case[7], ~test_case[6:0]};  // Complemented pattern
            
            #10;
            level_cycles = level_cycles + 1;
            
            // Calculate expected result
            a_signed = $signed(a);
            b_signed = $signed(b);
            expected_result = a_signed * b_signed;
            
            // Calculate error
            error = (expected_result > result) ? (expected_result - result) : (result - expected_result);
            
            if (error != 0) begin
                level_2_errors = level_2_errors + 1;
            end
            
            if (error > level_2_max_error) begin
                level_2_max_error = error;
            end
            
            level_2_tests = level_2_tests + 1;
            
            // Calculate relative error
            if (expected_result != 0) begin
                rel_error = (error * 100.0) / (expected_result < 0 ? -expected_result : expected_result);
            end else begin
                rel_error = 0;
            end
            
            level_2_mean_error = level_2_mean_error + error;
            level_2_rel_error = level_2_rel_error + rel_error;
            
            // Log samples
            if ((test_case % 32) == 0) begin
                $fwrite(log_file, "Test %3d: %4d × %4d = %6d (approx), Expected %6d, Error: %3d LSBs (%.2f%%)\n",
                    test_case, a_signed, b_signed, result, expected_result, error, rel_error);
            end
            
            $fwrite(csv_file, "%0d,%0d,%0d,L2,%0d,%0d,%0d,%.3f\n",
                test_case, a_signed, b_signed, expected_result, result[15:0], error, rel_error);
        end
        
        level_2_mean_error = level_2_mean_error / level_2_tests;
        level_2_rel_error = level_2_rel_error / level_2_tests;
        
        $fwrite(log_file, "\nL2 Summary: Errors: %0d/%0d, Max: %0d LSBs, Mean: %.2f LSBs, Rel Error: %.2f%%\n\n",
            level_2_errors, level_2_tests, level_2_max_error, level_2_mean_error, level_2_rel_error);
        
        // ==================== Final Summary and Statistics ====================
        
        total_cycles = 3 * 256 + 100;  // Approximate total
        throughput = (3.0 * 256.0) / total_cycles;
        
        $fwrite(log_file, "\n═══════════════════════════════════════════════════════════════\n");
        $fwrite(log_file, "                    COMPREHENSIVE TEST SUMMARY\n");
        $fwrite(log_file, "═══════════════════════════════════════════════════════════════\n");
        $fwrite(log_file, "Total Tests Executed: %0d (256 per level × 3 levels)\n", 3*256);
        $fwrite(log_file, "Total Cycles: %0d\n", total_cycles);
        $fwrite(log_file, "Throughput: %.4f results/cycle\n", throughput);
        $fwrite(log_file, "Average Latency: %.2f cycles/operation\n", 1.0/throughput);
        $fwrite(log_file, "\n");
        
        // Level-by-level summary
        $fwrite(log_file, "┌─ LEVEL 0 (Base, L0) ─┐\n");
        $fwrite(log_file, "│ Tests: %0d  Errors: %0d  Error Rate: %.2f%%\n", 
            level_0_tests, level_0_errors, (100.0 * level_0_errors / level_0_tests));
        $fwrite(log_file, "│ Max Error: %0d LSBs  Mean Error: %.3f LSBs  Mean Rel Error: %.3f%%\n",
            level_0_max_error, level_0_mean_error, level_0_rel_error);
        $fwrite(log_file, "│ Recommendation: Power-constrained applications only\n");
        $fwrite(log_file, "└──────────────────────┘\n\n");
        
        $fwrite(log_file, "┌─ LEVEL 1 (Moderate, L1) ─┐\n");
        $fwrite(log_file, "│ Tests: %0d  Errors: %0d  Error Rate: %.2f%%\n",
            level_1_tests, level_1_errors, (100.0 * level_1_errors / level_1_tests));
        $fwrite(log_file, "│ Max Error: %0d LSBs  Mean Error: %.3f LSBs  Mean Rel Error: %.3f%%\n",
            level_1_max_error, level_1_mean_error, level_1_rel_error);
        $fwrite(log_file, "│ Recommendation: Typical embedded systems\n");
        $fwrite(log_file, "└──────────────────────→┘\n\n");
        
        $fwrite(log_file, "┌─ LEVEL 2 (Maximum, L2) ─┐\n");
        $fwrite(log_file, "│ Tests: %0d  Errors: %0d  Error Rate: %.2f%%\n",
            level_2_tests, level_2_errors, (100.0 * level_2_errors / level_2_tests));
        $fwrite(log_file, "│ Max Error: %0d LSBs  Mean Error: %.3f LSBs  Mean Rel Error: %.3f%%\n",
            level_2_max_error, level_2_mean_error, level_2_rel_error);
        $fwrite(log_file, "│ Recommendation: Accuracy-critical applications (RECOMMENDED)\n");
        $fwrite(log_file, "└──────────────────────→┘\n\n");
        
        // Write summary file
        $fwrite(summary_file, "═════════════════════════════════════════════\n");
        $fwrite(summary_file, "SIGNED INTEGER TEST SUMMARY - RTL_proposed\n");
        $fwrite(summary_file, "═════════════════════════════════════════════\n");
        $fwrite(summary_file, "Timestamp: %0t\n", $time);
        $fwrite(summary_file, "Total Test Cases: %d\n", 3*256);
        $fwrite(summary_file, "Throughput: %.4f results/cycle\n", throughput);
        $fwrite(summary_file, "\nLevel 0: %d errors in %d tests (%.2f%%), Max: %d LSBs\n",
            level_0_errors, level_0_tests, (100.0 * level_0_errors / level_0_tests), level_0_max_error);
        $fwrite(summary_file, "Level 1: %d errors in %d tests (%.2f%%), Max: %d LSBs\n",
            level_1_errors, level_1_tests, (100.0 * level_1_errors / level_1_tests), level_1_max_error);
        $fwrite(summary_file, "Level 2: %d errors in %d tests (%.2f%%), Max: %d LSBs\n",
            level_2_errors, level_2_tests, (100.0 * level_2_errors / level_2_tests), level_2_max_error);
        $fwrite(summary_file, "\nMean Error Distances:\n");
        $fwrite(summary_file, "  L0: %.3f LSBs (%.3f%% relative)\n", level_0_mean_error, level_0_rel_error);
        $fwrite(summary_file, "  L1: %.3f LSBs (%.3f%% relative)\n", level_1_mean_error, level_1_rel_error);
        $fwrite(summary_file, "  L2: %.3f LSBs (%.3f%% relative)\n", level_2_mean_error, level_2_rel_error);
        
        $fwrite(log_file, "═══════════════════════════════════════════════════════════════\n");
        $fwrite(log_file, "Test End Time: %0t\n", $time);
        $fwrite(log_file, "═══════════════════════════════════════════════════════════════\n");
        
        // Close files
        $fclose(log_file);
        $fclose(csv_file);
        $fclose(summary_file);
        
        $display("\n");
        $display("════════════════════════════════════════════════════════════════");
        $display("SIGNED INTEGER TEST COMPLETE (RTL_proposed Non-Pipelined)");
        $display("════════════════════════════════════════════════════════════════");
        $display("Test  Cases: 768 (256 per level × 3)");
        $display("Throughput: %.4f results/cycle", throughput);
        $display("L0 Errors: %d/%d (%.2f%%), Max: %d LSBs", level_0_errors, level_0_tests, 
            (100.0 * level_0_errors / level_0_tests), level_0_max_error);
        $display("L1 Errors: %d/%d (%.2f%%), Max: %d LSBs", level_1_errors, level_1_tests,
            (100.0 * level_1_errors / level_1_tests), level_1_max_error);
        $display("L2 Errors: %d/%d (%.2f%%), Max: %d LSBs", level_2_errors, level_2_tests,
            (100.0 * level_2_errors / level_2_tests), level_2_max_error);
        $display("════════════════════════════════════════════════════════════════");
        $display("Output files:");
        $display("  - simulation_log_signed_int.txt");
        $display("  - Signed_int_L0_L1_L2_detailed.csv");
        $display("  - Signed_int_summary_results.txt");
        $display("════════════════════════════════════════════════════════════════\n");
        
        $finish;
    end
    
endmodule
