#!/usr/bin/env python3
"""Systematically test different shift amounts to find error-reducing configuration."""

import subprocess
import tempfile
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent
RTL_DIR = ROOT / "RTL_proposed"

# Test different shift amounts for both delta_f1 and delta_f2
SHIFT_AMOUNTS = [4, 5, 6, 7, 8, 9, 10]  # Will try dividing by 16, 32, 64, 128, 256, 512, 1024

def test_shift_amount(shift_f1, shift_f2):
    """Test a specific shift configuration and return mean errors."""
    # Modify the approx_t.v file with the new shifts
    approx_t_path = RTL_DIR / "approx_t.v"
    approx_t_content = approx_t_path.read_text()
    
    # Replace the shift amounts in the delta_f1 and delta_f2 calculations
    # delta_f1 line: assign delta_f1 = (term1_f1 + term2_f1) >>> 6;
    modified = re.sub(
        r'assign delta_f1 = \(term1_f1 \+ term2_f1\) >>> \d+;',
        f'assign delta_f1 = (term1_f1 + term2_f1) >>> {shift_f1};',
        approx_t_content
    )
    # delta_f2 line: assign delta_f2 = cross_product >>> 6;
    modified = re.sub(
        r'assign delta_f2 = cross_product >>> \d+;',
        f'assign delta_f2 = cross_product >>> {shift_f2};',
        modified
    )
    
    approx_t_path.write_text(modified)
    
    # Run L0, L1, L2 tests
    try:
        results = {}
        for level in [0, 1, 2]:
            tb_file = ROOT / f"tb/RTL_proposed/Unsigned_int/tb_unsigned_int_L{level}.v"
            
            with tempfile.TemporaryDirectory() as temp_dir:
                executable = Path(temp_dir) / f"test_L{level}"
                compile_cmd = [
                    "iverilog", "-g2012", "-o", str(executable),
                    str(RTL_DIR / "unsigned_int_mul.v"),
                    str(RTL_DIR / "approx_t.v"),
                    str(RTL_DIR / "leading_one_detector.v"),
                    str(RTL_DIR / "bit_mask_sel.v"),
                    str(tb_file),
                ]
                subprocess.run(compile_cmd, cwd=ROOT, check=True, capture_output=True)
                result = subprocess.run(["vvp", str(executable)], cwd=ROOT, check=True, capture_output=True, text=True)
                
                # Extract mean error from output (if it exists)
                # Parse the CSV that was written
                csv_file = ROOT / f"Unsigned_int_L{level}_results.csv"
                if csv_file.exists():
                    with open(csv_file, 'r') as f:
                        import csv
                        reader = csv.DictReader(f)
                        errors = []
                        for row in reader:
                            try:
                                errors.append(float(row['Percentage_Error']))
                            except (ValueError, KeyError):
                                pass
                    if errors:
                        results[f"L{level}"] = sum(errors) / len(errors)
        
        return results
    except Exception as e:
        print(f"Error testing shifts {shift_f1},{shift_f2}: {e}")
        return None

# Test different combinations
print("Shift_F1  Shift_F2  |  L0_Error  L1_Error  L2_Error  |  Trend")
print("-" * 70)

best_config = None
best_trend = float('inf')

for shift_f1 in SHIFT_AMOUNTS:
    for shift_f2 in SHIFT_AMOUNTS:
        results = test_shift_amount(shift_f1, shift_f2)
        if results and 'L0' in results and 'L1' in results and 'L2' in results:
            l0 = results['L0']
            l1 = results['L1']
            l2 = results['L2']
            
            # Measure trend: sum of increases (negative is good, means error decreases)
            trend = (l1 - l0) + (l2 - l1)
            
            print(f"  {shift_f1:2d}     {shift_f2:2d}    |  {l0:6.2f}%   {l1:6.2f}%   {l2:6.2f}%  |  {trend:+6.2f}%")
            
            # Track best trend (most negative = best improvement)
            if trend < best_trend:
                best_trend = trend
                best_config = (shift_f1, shift_f2, l0, l1, l2)

print("-" * 70)
if best_config:
    shift_f1, shift_f2, l0, l1, l2 = best_config
    print(f"BEST: Shifts ({shift_f1}, {shift_f2}) with trend {best_trend:+.2f}% L0:{l0:.2f}% L1:{l1:.2f}% L2:{l2:.2f}%")
    
    # Apply the best configuration
    test_shift_amount(shift_f1, shift_f2)
    print(f"Applied best configuration to approx_t.v: delta_f1 >> {shift_f1}, delta_f2 >> {shift_f2}")
