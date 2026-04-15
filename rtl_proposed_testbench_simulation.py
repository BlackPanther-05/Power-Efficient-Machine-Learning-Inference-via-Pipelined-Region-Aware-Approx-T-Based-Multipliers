#!/usr/bin/env python3
"""
RTL_proposed Testbench Simulation Runner
Executes 12 testbenches across 4 data types (unsigned_int, signed_int, fixed_point,
floating_point) with deterministic datasets and 3 precision levels each (L0, L1, L2).

Date: 2024
Description: Comprehensive simulation framework for RTL_proposed variant with
             leading_one_detector integration and CSV result aggregation.
"""

import os
import sys
import subprocess
import multiprocessing
import shutil
import time
import re
from pathlib import Path
from datetime import datetime
from tqdm import tqdm
from concurrent.futures import ThreadPoolExecutor, as_completed

# Define workspace and directories
WORKSPACE_ROOT = Path(__file__).parent.resolve()
TB_DIR = WORKSPACE_ROOT / "tb" / "RTL_proposed"
SIM_LOG_DIR = WORKSPACE_ROOT / "Simulation_log"
SIM_RESULTS_DIR = WORKSPACE_ROOT / "Simulation_Results" / "RTL_proposed"
VCD_RESULTS_DIR = WORKSPACE_ROOT / "Results_tabulation" / "vcd" / "RTL_proposed"

# Create directories if they don't exist
SIM_LOG_DIR.mkdir(parents=True, exist_ok=True)
SIM_RESULTS_DIR.mkdir(parents=True, exist_ok=True)
VCD_RESULTS_DIR.mkdir(parents=True, exist_ok=True)

# Define testbench configuration
TESTBENCHES = {
    "Unsigned_int": [
        {"level": "L0", "file": "tb_unsigned_int_L0.v", "conf": "6'b000001"},
        {"level": "L1", "file": "tb_unsigned_int_L1.v", "conf": "6'b000011"},
        {"level": "L2", "file": "tb_unsigned_int_L2.v", "conf": "6'b000111"},
    ],
    "Signed_int": [
        {"level": "L0", "file": "tb_signed_int_L0.v", "conf": "6'b000001"},
        {"level": "L1", "file": "tb_signed_int_L1.v", "conf": "6'b000011"},
        {"level": "L2", "file": "tb_signed_int_L2.v", "conf": "6'b000111"},
    ],
    "Fixed_point": [
        {"level": "L0", "file": "tb_fixed_point_L0.v", "conf": "6'b000001"},
        {"level": "L1", "file": "tb_fixed_point_L1.v", "conf": "6'b000011"},
        {"level": "L2", "file": "tb_fixed_point_L2.v", "conf": "6'b000111"},
    ],
    "Floating_point": [
        {"level": "L0", "file": "tb4float_L0.v", "conf": "6'b000001"},
        {"level": "L1", "file": "tb4float_L1.v", "conf": "6'b000011"},
        {"level": "L2", "file": "tb4float_L2.v", "conf": "6'b000111"},
    ],
}

# RTL module sources
RTL_SOURCES = [
    WORKSPACE_ROOT / "RTL_proposed" / "approx_t.v",
    WORKSPACE_ROOT / "RTL_proposed" / "bit_mask_sel.v",
    WORKSPACE_ROOT / "RTL_proposed" / "unsigned_int_mul.v",
    WORKSPACE_ROOT / "RTL_proposed" / "signed_int_mul.v",
    WORKSPACE_ROOT / "RTL_proposed" / "fixed_point_mul.v",
    WORKSPACE_ROOT / "RTL_proposed" / "floating_point_mul.v",
    WORKSPACE_ROOT / "RTL_proposed" / "leading_one_detector.v",
]


class TestbenchRunner:
    """Manages compilation and execution of individual testbenches."""
    
    def __init__(self, data_type, tb_config):
        self.data_type = data_type
        self.tb_config = tb_config
        self.level = tb_config["level"]
        self.file = tb_config["file"]
        self.conf = tb_config["conf"]
        self.tb_path = TB_DIR / data_type / self.file
        self.log_file = SIM_LOG_DIR / f"{data_type}_{self.level}.log"
        
        # Create output directory for results
        self.result_dir = SIM_RESULTS_DIR / data_type
        self.result_dir.mkdir(parents=True, exist_ok=True)
        self.vcd_dir = VCD_RESULTS_DIR / data_type
        self.vcd_dir.mkdir(parents=True, exist_ok=True)
        self.result_csv = self.result_dir / f"{data_type}_{self.level}_results.csv"
        self.vcd_file = self.vcd_dir / f"{data_type}_{self.level}.vcd"
    
    def compile(self):
        """Compile testbench using iVerilog."""
        if not self.tb_path.exists():
            print(f"ERROR: Testbench not found: {self.tb_path}")
            return False
        
        vvp_file = f"{self.data_type}_{self.level}.vvp"
        compile_cmd = ["iverilog", "-g2009", "-I", str(WORKSPACE_ROOT / "tb" / "common"), "-o", vvp_file]
        
        # Add all RTL sources in correct order (dependencies first)
        for src in RTL_SOURCES:
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
                    f.write(f"Compilation Error:\n{result.stderr}\nCommand: {' '.join(compile_cmd)}\n")
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

            # Execute testbench and capture output
            result = subprocess.run(
                ["vvp", str(vvp_file)],
                capture_output=True,
                text=True,
                cwd=WORKSPACE_ROOT,
                timeout=1200
            )
            
            with open(self.log_file, "a") as f:
                f.write(f"\nExecution Log:\n")
                f.write(f"Return Code: {result.returncode}\n")
                if result.stdout:
                    f.write(f"STDOUT:\n{result.stdout}\n")
                if result.stderr:
                    f.write(f"STDERR:\n{result.stderr}\n")

            if result.returncode == 0 and not self.vcd_file.exists():
                with open(self.log_file, "a") as f:
                    f.write(f"ERROR: Expected VCD file not found: {self.vcd_file}\n")
                return False
            
            # Verify CSV output was created
            if self.data_type == "floating_point":
                expected_csv = self.result_dir / f"Floating_point_{self.level}_results.csv"
            else:
                expected_csv = self.result_dir / f"{self.data_type.replace('_', ' ').title().replace(' ', '_')}_{self.level}_results.csv"
            
            # Check for any CSV file created
            csv_files = list(self.result_dir.glob("*_results.csv"))
            csv_created = any(self.level in str(f) for f in csv_files)
            
            if not csv_created and result.returncode == 0:
                # Sometimes file naming varies, just check if CSV exists
                self.log_file.write_text(self.log_file.read_text() + "\nWARNING: Expected CSV file not found, but execution completed.\n")
            
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


def calculate_mean_error(csv_file):
    """Calculate mean error percentage from a CSV file."""
    try:
        with open(csv_file, "r") as f:
            lines = f.readlines()

        if len(lines) <= 1:
            return "N/A"

        errors = []
        for line in lines[1:]:
            parts = line.strip().split(",")
            if len(parts) >= 9:
                try:
                    errors.append(float(parts[-1].strip()))
                except (ValueError, IndexError):
                    pass

        if not errors:
            return "N/A"
        return f"{sum(errors) / len(errors):.6f}%"
    except Exception:
        return "N/A"


def run_testbench(args):
    """Wrapper for parallel execution."""
    data_type, tb_config = args
    runner = TestbenchRunner(data_type, tb_config)
    success = runner.execute()
    return (f"{data_type}_{tb_config['level']}", success)


def main():
    """Main execution function."""
    print("\n" + "="*80)
    print("RTL_proposed TESTBENCH SIMULATION SUITE")
    print("="*80)
    print(f"Workspace: {WORKSPACE_ROOT}")
    print(f"Simulation Log Directory: {SIM_LOG_DIR}")
    print(f"Results Directory: {SIM_RESULTS_DIR}")
    print(f"VCD Directory: {VCD_RESULTS_DIR}")
    print(f"Start Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*80 + "\n")
    
    # Verify RTL sources exist
    missing_sources = [src for src in RTL_SOURCES if not src.exists()]
    if missing_sources:
        print("WARNING: Some RTL sources not found:")
        for src in missing_sources:
            print(f"  - {src}")
    
    # Build test queue
    test_queue = []
    for data_type, tb_list in TESTBENCHES.items():
        for tb_config in tb_list:
            test_queue.append((data_type, tb_config))
    
    print(f"Total testbenches to execute: {len(test_queue)}\n")
    print("Testbenches queued for execution:")
    print("-" * 80)
    for data_type, tb_config in test_queue:
        print(f"  {data_type:15} | Level {tb_config['level']} | Config: {tb_config['conf']} | File: {tb_config['file']}")
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
            csv_file = SIM_RESULTS_DIR / data_type / f"{data_type}_{level}_results.csv"
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
                csv_file = type_dir / f"{data_type}_{level}_results.csv"
                if not csv_file.exists():
                    print(f"  {csv_file.name}: missing")
                    continue
                try:
                    with open(csv_file, "r") as f:
                        lines = f.readlines()
                    test_count = len(lines) - 1
                    mean_error_pct = calculate_mean_error(csv_file)
                    print(f"  {csv_file.name}: {test_count} test cases | Mean Error: {mean_error_pct}")
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
