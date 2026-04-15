#!/usr/bin/env python3
"""
Base RTL Testbench Simulation Runner
Executes 24 testbenches across 4 data types (unsigned_int, signed_int, fixed_point,
floating_point) with 6 precision levels each (L0, L1, L2, L3, L4, L5).

Date: 2024
Description: Comprehensive simulation framework for base RTL variant with
             leading_one_detector integration and CSV result aggregation with error analysis.
"""

import os
import sys
import subprocess
import multiprocessing
import tempfile
import time
from pathlib import Path
from datetime import datetime
from tqdm import tqdm
from concurrent.futures import ThreadPoolExecutor, as_completed

# Define workspace and directories
WORKSPACE_ROOT = Path(__file__).parent.resolve()
TB_DIR = WORKSPACE_ROOT / "tb"
RTL_DIR = WORKSPACE_ROOT / "RTL"
SIM_LOG_DIR = WORKSPACE_ROOT / "Simulation_log"
SIM_RESULTS_DIR = WORKSPACE_ROOT / "Simulation_Results" / "base"
VCD_RESULTS_DIR = WORKSPACE_ROOT / "Results_tabulation" / "vcd" / "base"

# Create directories if they don't exist
SIM_LOG_DIR.mkdir(parents=True, exist_ok=True)
SIM_RESULTS_DIR.mkdir(parents=True, exist_ok=True)
VCD_RESULTS_DIR.mkdir(parents=True, exist_ok=True)

# Define testbench configuration for base RTL
TESTBENCHES = {
    "Unsigned_int": [
        {"level": "L0", "file": "tb_unsigned_int_L0.v", "tb_dir": "Unsigned_int"},
        {"level": "L1", "file": "tb_unsigned_int_L1.v", "tb_dir": "Unsigned_int"},
        {"level": "L2", "file": "tb_unsigned_int_L2.v", "tb_dir": "Unsigned_int"},
        {"level": "L3", "file": "tb_unsigned_int_L3.v", "tb_dir": "Unsigned_int"},
        {"level": "L4", "file": "tb_unsigned_int_L4.v", "tb_dir": "Unsigned_int"},
        {"level": "L5", "file": "tb_unsigned_int_L5.v", "tb_dir": "Unsigned_int"},
    ],
    "Signed_int": [
        {"level": "L0", "file": "tb_signed_int_L0.v", "tb_dir": "Signed_int"},
        {"level": "L1", "file": "tb_signed_int_L1.v", "tb_dir": "Signed_int"},
        {"level": "L2", "file": "tb_signed_int_L2.v", "tb_dir": "Signed_int"},
        {"level": "L3", "file": "tb_signed_int_L3.v", "tb_dir": "Signed_int"},
        {"level": "L4", "file": "tb_signed_int_L4.v", "tb_dir": "Signed_int"},
        {"level": "L5", "file": "tb_signed_int_L5.v", "tb_dir": "Signed_int"},
    ],
    "Fixed_point": [
        {"level": "L0", "file": "tb_fixed_point_L0.v", "tb_dir": "Fixed_point"},
        {"level": "L1", "file": "tb_fixed_point_L1.v", "tb_dir": "Fixed_point"},
        {"level": "L2", "file": "tb_fixed_point_L2.v", "tb_dir": "Fixed_point"},
        {"level": "L3", "file": "tb_fixed_point_L3.v", "tb_dir": "Fixed_point"},
        {"level": "L4", "file": "tb_fixed_point_L4.v", "tb_dir": "Fixed_point"},
        {"level": "L5", "file": "tb_fixed_point_L5.v", "tb_dir": "Fixed_point"},
    ],
    "Floating_point": [
        {"level": "L0", "file": "tb4float_L0.v", "tb_dir": "Floating_point"},
        {"level": "L1", "file": "tb4float_L1.v", "tb_dir": "Floating_point"},
        {"level": "L2", "file": "tb4float_L2.v", "tb_dir": "Floating_point"},
        {"level": "L3", "file": "tb4float_L3.v", "tb_dir": "Floating_point"},
        {"level": "L4", "file": "tb4float_L4.v", "tb_dir": "Floating_point"},
        {"level": "L5", "file": "tb4float_L5.v", "tb_dir": "Floating_point"},
    ],
}

# RTL module sources by data type
RTL_SOURCES = {
    "Unsigned_int": [
        RTL_DIR / "unsigned_int_mul.v",
        RTL_DIR / "approx_t.v",
        RTL_DIR / "leading_one_detector.v",
        RTL_DIR / "bit_mask_sel.v",
    ],
    "Signed_int": [
        RTL_DIR / "signed_int_mul.v",
        RTL_DIR / "unsigned_int_mul.v",
        RTL_DIR / "approx_t.v",
        RTL_DIR / "leading_one_detector.v",
        RTL_DIR / "bit_mask_sel.v",
    ],
    "Fixed_point": [
        RTL_DIR / "fixed_point_mul.v",
        RTL_DIR / "unsigned_int_mul.v",
        RTL_DIR / "approx_t.v",
        RTL_DIR / "leading_one_detector.v",
        RTL_DIR / "bit_mask_sel.v",
    ],
    "Floating_point": [
        RTL_DIR / "floating_point_mul.v",
        RTL_DIR / "approx_t.v",
        RTL_DIR / "bit_mask_sel.v",
    ],
}


class TestbenchRunner:
    """Manages compilation and execution of individual testbenches."""
    
    def __init__(self, data_type, tb_config):
        self.data_type = data_type
        self.tb_config = tb_config
        self.level = tb_config["level"]
        self.file = tb_config["file"]
        self.tb_dir = tb_config["tb_dir"]
        self.tb_path = TB_DIR / self.tb_dir / self.file
        self.log_file = SIM_LOG_DIR / f"{data_type}_{self.level}.log"
        
        # Create output directory for results
        self.result_dir = SIM_RESULTS_DIR / data_type
        self.result_dir.mkdir(parents=True, exist_ok=True)
        self.vcd_dir = VCD_RESULTS_DIR / data_type
        self.vcd_dir.mkdir(parents=True, exist_ok=True)
        self.result_csv = self.result_dir / f"{data_type}_{self.level}.csv"
        self.vcd_file = self.vcd_dir / f"{data_type}_{self.level}.vcd"
    
    def compile(self):
        """Compile testbench using iVerilog."""
        if not self.tb_path.exists():
            with open(self.log_file, "w") as f:
                f.write(f"ERROR: Testbench not found: {self.tb_path}\n")
            return False
        
        vvp_file = f"{self.data_type}_{self.level}.vvp"
        compile_cmd = ["iverilog", "-g2012", "-I", str(TB_DIR / "common"), "-o", vvp_file]
        
        # Add RTL sources specific to this data type
        if self.data_type in RTL_SOURCES:
            for src in RTL_SOURCES[self.data_type]:
                if src.exists():
                    compile_cmd.append(str(src))
                else:
                    with open(self.log_file, "w") as f:
                        f.write(f"Missing RTL source: {src}\n")
        
        # Add testbench last
        compile_cmd.append(str(self.tb_path))
        
        try:
            result = subprocess.run(
                compile_cmd,
                capture_output=True,
                text=True,
                cwd=self.result_dir,
                timeout=60
            )
            
            if result.returncode != 0:
                with open(self.log_file, "w") as f:
                    f.write(f"Compilation Error:\n{result.stderr}\n")
                return False
            
            with open(self.log_file, "w") as f:
                f.write(f"Compilation successful.\n")
            return True
        
        except subprocess.TimeoutExpired:
            with open(self.log_file, "w") as f:
                f.write("Compilation timed out.\n")
            return False
        except Exception as e:
            with open(self.log_file, "w") as f:
                f.write(f"Compilation exception: {str(e)}\n")
            return False
    
    def run(self):
        """Execute compiled testbench using VVP."""
        vvp_file = self.result_dir / f"{self.data_type}_{self.level}.vvp"
        
        if not vvp_file.exists():
            with open(self.log_file, "a") as f:
                f.write(f"Error: VVP file not found: {vvp_file}\n")
            return False
        
        try:
            if self.vcd_file.exists():
                self.vcd_file.unlink()

            # Run from workspace root so testbenches can find their output paths correctly
            result = subprocess.run(
                ["vvp", str(vvp_file)],
                capture_output=True,
                text=True,
                cwd=WORKSPACE_ROOT,  # Run from workspace root
                timeout=1200
            )
            
            with open(self.log_file, "a") as f:
                f.write(f"Execution Log:\n")
                if result.stdout:
                    f.write(f"STDOUT:\n{result.stdout}\n")
                if result.stderr:
                    f.write(f"STDERR:\n{result.stderr}\n")

            if result.returncode == 0 and not self.vcd_file.exists():
                with open(self.log_file, "a") as f:
                    f.write(f"ERROR: Expected VCD file not found: {self.vcd_file}\n")
                return False
            
            # Check if result was successful
            return result.returncode == 0
        
        except subprocess.TimeoutExpired:
            with open(self.log_file, "a") as f:
                f.write("Execution timed out (1200s limit).\n")
            return False
        except Exception as e:
            with open(self.log_file, "a") as f:
                f.write(f"Execution exception: {str(e)}\n")
            return False
    
    def execute(self):
        """Compile and run testbench."""
        if not self.compile():
            return False
        return self.run()


def run_testbench(args):
    """Wrapper for parallel execution."""
    data_type, tb_config = args
    runner = TestbenchRunner(data_type, tb_config)
    success = runner.execute()
    return (f"{data_type}_{tb_config['level']}", success)


def calculate_mean_error(csv_file):
    """Calculate mean error percentage from CSV file."""
    try:
        with open(csv_file, 'r') as f:
            lines = f.readlines()
        
        if len(lines) <= 1:
            return "N/A"
        
        errors = []
        for line in lines[1:]:  # Skip header
            parts = line.strip().split(',')
            if len(parts) >= 9:
                try:
                    pct_error = float(parts[-1].strip())
                    errors.append(pct_error)
                except (ValueError, IndexError):
                    pass
        
        if errors:
            mean_error = sum(errors) / len(errors)
            return f"{mean_error:.6f}%"
        else:
            return "N/A"
    except:
        return "N/A"


def main():
    """Main execution function."""
    print("\n" + "="*80)
    print("BASE RTL TESTBENCH SIMULATION SUITE")
    print("="*80)
    print(f"Workspace: {WORKSPACE_ROOT}")
    print(f"Simulation Log Directory: {SIM_LOG_DIR}")
    print(f"Results Directory: {SIM_RESULTS_DIR}")
    print(f"VCD Directory: {VCD_RESULTS_DIR}")
    print(f"Start Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*80 + "\n")
    
    # Build test queue
    test_queue = []
    for data_type, tb_list in TESTBENCHES.items():
        for tb_config in tb_list:
            test_queue.append((data_type, tb_config))
    
    print(f"Total testbenches to execute: {len(test_queue)}\n")
    print("Testbenches queued for execution:")
    print("-" * 80)
    for data_type, tb_config in test_queue:
        print(f"  {data_type:15} | Level {tb_config['level']} | File: {tb_config['file']}")
    print("-" * 80 + "\n")
    
    # Execute testbenches in parallel
    max_workers = min(8, multiprocessing.cpu_count())
    print(f"Executing with {max_workers} parallel workers...\n")
    
    results = {}
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(run_testbench, (dt, tc)): (dt, tc) 
                   for dt, tc in test_queue}
        
        # Use tqdm for progress tracking
        for future in tqdm(as_completed(futures), total=len(futures), 
                          desc="Testbenches", unit="test"):
            test_name, success = future.result()
            results[test_name] = success
    
    print("\n" + "="*80)
    print("SIMULATION RESULTS SUMMARY")
    print("="*80 + "\n")
    
    # Organize results by data type
    results_by_type = {}
    for data_type in TESTBENCHES.keys():
        results_by_type[data_type] = {}
        for tb_config in TESTBENCHES[data_type]:
            level = tb_config["level"]
            test_name = f"{data_type}_{level}"
            results_by_type[data_type][level] = results.get(test_name, False)
    
    # Display results
    total_tests = len(results)
    passed_tests = sum(1 for v in results.values() if v)
    
    print(f"Total Tests: {total_tests}")
    print(f"Passed: {passed_tests}")
    print(f"Failed: {total_tests - passed_tests}")
    print(f"Success Rate: {(passed_tests/total_tests*100):.1f}%\n")
    
    print("Detailed Results by Data Type:")
    print("-" * 80)
    
    for data_type, levels in results_by_type.items():
        type_passed = sum(1 for v in levels.values() if v)
        type_total = len(levels)
        status = "✓ PASS" if type_passed == type_total else "✗ FAIL"
        print(f"{data_type:15} {status} ({type_passed}/{type_total})")
        for level, success in levels.items():
            result_status = "✓" if success else "✗"
            csv_file = SIM_RESULTS_DIR / data_type / f"{data_type}_{level}.csv"
            csv_exists = csv_file.exists()
            vcd_file = VCD_RESULTS_DIR / data_type / f"{data_type}_{level}.vcd"
            vcd_exists = vcd_file.exists()
            print(f"  {level}: {result_status} {'CSV: ✓' if csv_exists else 'CSV: ✗'} {'VCD: ✓' if vcd_exists else 'VCD: ✗'}")
    
    print("-" * 80 + "\n")
    
    # Generate statistics for successful runs
    print("CSV Results Summary:")
    print("-" * 80)
    for data_type in TESTBENCHES.keys():
        type_dir = SIM_RESULTS_DIR / data_type
        if type_dir.exists():
            print(f"\n{data_type}:")
            for tb_config in TESTBENCHES[data_type]:
                level = tb_config["level"]
                csv_file = type_dir / f"{data_type}_{level}.csv"
                if not csv_file.exists():
                    print(f"  {csv_file.name}: missing")
                    continue
                try:
                    with open(csv_file, 'r') as f:
                        lines = f.readlines()
                    test_count = len(lines) - 1  # Exclude header
                    mean_error = calculate_mean_error(csv_file)
                    print(f"  {csv_file.name}: {test_count} test cases | Mean Error: {mean_error}")
                except Exception:
                    print(f"  {csv_file.name}: (unable to read)")
    
    print("-" * 80 + "\n")
    
    # Log files location
    print("Log Files Location:")
    print(f"  {SIM_LOG_DIR}\n")
    
    print("Results CSV Location:")
    print(f"  {SIM_RESULTS_DIR}\n")

    print("Results VCD Location:")
    print(f"  {VCD_RESULTS_DIR}\n")
    
    print("="*80)
    print(f"Completion Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*80 + "\n")
    
    # Return exit code based on results
    return 0 if passed_tests == total_tests else 1


if __name__ == "__main__":
    sys.exit(main())
