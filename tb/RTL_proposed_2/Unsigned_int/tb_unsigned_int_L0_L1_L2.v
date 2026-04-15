`timescale 1ns / 1ps

/*
 * Comprehensive Test Bench: Unsigned Integer Multiplication
 * Variant: RTL_proposed_2 (Non-Pipelined)
 * Data Type: Unsigned 8-bit × 8-bit → 16-bit
 * Precision Levels: L0, L1, L2
 * Test Cases: 256 per level
 * CSV Output: Standard format for all levels
 */

module tb_unsigned_int_L0_L1_L2();
    
    reg [7:0] a, b;
    reg [5:0] config_bits;
    wire [15:0] result;
    
    integer csv_l0, csv_l1, csv_l2, log_file;
    integer i, test_num;
    integer errors_l0, errors_l1, errors_l2;
    integer max_err_l0, max_err_l1, max_err_l2;
    real sum_err_l0, sum_err_l1, sum_err_l2;
    real sum_rel_l0, sum_rel_l1, sum_rel_l2;
    
    wire [15:0] expected = a * b;
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
        csv_l0 = $fopen("Unsigned_int_L0_results.csv", "w");
        csv_l1 = $fopen("Unsigned_int_L1_results.csv", "w");
        csv_l2 = $fopen("Unsigned_int_L2_results.csv", "w");
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
        
        $fwrite(log_file, "UNSIGNED INTEGER TESTBENCH - RTL_proposed_2\n");
        $fwrite(log_file, "=============================================\n\n");
        
        // ===== LEVEL 0 =====
        $fwrite(log_file, "PRECISION LEVEL 0\n");
        $fwrite(log_file, "─────────────────────────────────────────────\n");
        config_bits = 6'b000001;
        
        for (i = 0; i < 256; i++) begin
            a = i;
            b = ((i * 7 + 3) % 256);
            #5;
            
            rel_error = (expected != 0) ? (real(error) / real(expected) * 100.0) : 0.0;            absolute_error = error;
            percentage_error = (expected != 0) ? ((real(absolute_error) / real(expected)) * 100.0) : 0.0;            
            if (error != 0) errors_l0++;
            if (error > max_err_l0) max_err_l0 = error;
            sum_err_l0 = sum_err_l0 + error;
            sum_rel_l0 = sum_rel_l0 + rel_error;
            
            $fwrite(csv_l0, "%0d,%0d,%0d,%0d,%0d,%0d,%.2f,%0d,%.2f\n",
                    i+1, a, b, expected, result, error, rel_error, absolute_error, percentage_error);
            
            if ((i % 32) == 0)
                $fwrite(log_file, "Test %3d: A=%3d, B=%3d | Exp=%5d, Got=%5d | Err=%3d (%.2f%%)\n",
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
            a = i;
            b = ((i * 13 + 5) % 256);
            #5;
            
            rel_error = (expected != 0) ? (real(error) / real(expected) * 100.0) : 0.0;
            absolute_error = error;
            percentage_error = (expected != 0) ? ((real(absolute_error) / real(expected)) * 100.0) : 0.0;
            
            if (error != 0) errors_l1++;
            if (error > max_err_l1) max_err_l1 = error;
            sum_err_l1 = sum_err_l1 + error;
            sum_rel_l1 = sum_rel_l1 + rel_error;
            
            $fwrite(csv_l1, "%0d,%0d,%0d,%0d,%0d,%0d,%.2f,%0d,%.2f\n",
                    i+1, a, b, expected, result, error, rel_error, absolute_error, percentage_error);
            
            if ((i % 32) == 0)
                $fwrite(log_file, "Test %3d: A=%3d, B=%3d | Exp=%5d, Got=%5d | Err=%3d (%.2f%%)\n",
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
            a = i;
            b = ((i * 19 + 7) % 256);
            #5;
            
            rel_error = (expected != 0) ? (real(error) / real(expected) * 100.0) : 0.0;
            absolute_error = error;
            percentage_error = (expected != 0) ? ((real(absolute_error) / real(expected)) * 100.0) : 0.0;
            
            if (error != 0) errors_l2++;
            if (error > max_err_l2) max_err_l2 = error;
            sum_err_l2 = sum_err_l2 + error;
            sum_rel_l2 = sum_rel_l2 + rel_error;
            
            $fwrite(csv_l2, "%0d,%0d,%0d,%0d,%0d,%0d,%.2f,%0d,%.2f\n",
                    i+1, a, b, expected, result, error, rel_error, absolute_error, percentage_error);
            
            if ((i % 32) == 0)
                $fwrite(log_file, "Test %3d: A=%3d, B=%3d | Exp=%5d, Got=%5d | Err=%3d (%.2f%%)\n",
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
        $display("  - Unsigned_int_L0_results.csv");
        $display("  - Unsigned_int_L1_results.csv");
        $display("  - Unsigned_int_L2_results.csv");
        
        $fclose(csv_l0);
        $fclose(csv_l1);
        $fclose(csv_l2);
        $fclose(log_file);
        $finish;
    end
    
endmodule
