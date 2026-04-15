#!/usr/bin/env python3
"""
RTL_proposed_2 Testbench Simulation Runner
Executes 12 pipelined testbenches across 4 data types with deterministic datasets
and 3 precision levels each (L0, L1, L2).

Date: 2024
Description: Comprehensive simulation framework for RTL_proposed_2 variant with
             pipelined interfaces, CSV result aggregation, and VCD collection.
"""

import subprocess
import multiprocessing
from pathlib import Path
from datetime import datetime
from tqdm import tqdm
from concurrent.futures import ThreadPoolExecutor, as_completed

# Define workspace and directories
WORKSPACE_ROOT = Path(__file__).parent.resolve()
TB_DIR = WORKSPACE_ROOT / "tb" / "RTL_proposed_2"
SIM_LOG_DIR = WORKSPACE_ROOT / "Simulation_log"
SIM_RESULTS_DIR = WORKSPACE_ROOT / "Simulation_Results" / "RTL_proposed_2"
VCD_RESULTS_DIR = WORKSPACE_ROOT / "Results_tabulation" / "vcd" / "RTL_proposed_2"

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
    WORKSPACE_ROOT / "RTL_proposed_2" / "approx_t.v",
    WORKSPACE_ROOT / "RTL_proposed_2" / "bit_mask_sel.v",
    WORKSPACE_ROOT / "RTL_proposed_2" / "unsigned_int_mul.v",
    WORKSPACE_ROOT / "RTL_proposed_2" / "signed_int_mul.v",
    WORKSPACE_ROOT / "RTL_proposed_2" / "fixed_point_mul.v",
    WORKSPACE_ROOT / "RTL_proposed_2" / "floating_point_mul.v",
    WORKSPACE_ROOT / "RTL_proposed_2" / "leading_one_detector.v",
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
        self.log_file = SIM_LOG_DIR / f"{data_type}_{self.level}_rtl_proposed_2.log"

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
        compile_cmd = ["iverilog", "-g2012", "-I", str(WORKSPACE_ROOT / "tb" / "common"), "-o", vvp_file]

        for src in RTL_SOURCES:
            if src.exists():
                compile_cmd.append(str(src))
            else:
                with open(self.log_file, "w") as log_handle:
                    log_handle.write(f"Missing RTL source: {src}\n")

        compile_cmd.append(str(self.tb_path))

        try:
            result = subprocess.run(
                compile_cmd,
                capture_output=True,
                text=True,
                cwd=self.result_dir,
                timeout=60,
            )

            if result.returncode != 0:
                with open(self.log_file, "w") as log_handle:
                    log_handle.write(f"Compilation Error:\n{result.stderr}\nCommand: {' '.join(compile_cmd)}\n")
                return False

            with open(self.log_file, "w") as log_handle:
                log_handle.write("Compilation successful.\n")
            return True

        except subprocess.TimeoutExpired:
            with open(self.log_file, "w") as log_handle:
                log_handle.write("Compilation timed out.\n")
            return False
        except Exception as exc:
            with open(self.log_file, "w") as log_handle:
                log_handle.write(f"Compilation exception: {exc}\n")
            return False

    def run(self):
        """Execute compiled testbench using VVP."""
        vvp_file = self.result_dir / f"{self.data_type}_{self.level}.vvp"

        if not vvp_file.exists():
            with open(self.log_file, "a") as log_handle:
                log_handle.write(f"Error: VVP file not found: {vvp_file}\n")
            return False

        try:
            if self.vcd_file.exists():
                self.vcd_file.unlink()

            result = subprocess.run(
                ["vvp", str(vvp_file)],
                capture_output=True,
                text=True,
                cwd=WORKSPACE_ROOT,
                timeout=1200,
            )

            with open(self.log_file, "a") as log_handle:
                log_handle.write("\nExecution Log:\n")
                log_handle.write(f"Return Code: {result.returncode}\n")
                if result.stdout:
                    log_handle.write(f"STDOUT:\n{result.stdout}\n")
                if result.stderr:
                    log_handle.write(f"STDERR:\n{result.stderr}\n")

            if result.returncode == 0 and not self.vcd_file.exists():
                with open(self.log_file, "a") as log_handle:
                    log_handle.write(f"ERROR: Expected VCD file not found: {self.vcd_file}\n")
                return False

            csv_files = list(self.result_dir.glob("*_results.csv"))
            csv_created = any(self.level in str(path) for path in csv_files)
            if not csv_created and result.returncode == 0:
                self.log_file.write_text(self.log_file.read_text() + "\nWARNING: Expected CSV file not found, but execution completed.\n")

            return result.returncode == 0

        except subprocess.TimeoutExpired:
            with open(self.log_file, "a") as log_handle:
                log_handle.write("Execution timed out (1200s limit).\n")
            return False
        except Exception as exc:
            with open(self.log_file, "a") as log_handle:
                log_handle.write(f"Execution exception: {exc}\n")
            return False

    def execute(self):
        """Compile and run testbench."""
        if not self.compile():
            return False
        return self.run()


def calculate_mean_error(csv_file):
    """Calculate mean error percentage from a CSV file."""
    try:
        with open(csv_file, "r") as csv_handle:
            lines = csv_handle.readlines()

        if len(lines) <= 1:
            return "N/A"

        errors = []
        for line in lines[1:]:
            parts = line.strip().split(",")
            # Percentage_Error is the 9th column; later columns are region metadata
            if len(parts) >= 9:
                try:
                    errors.append(float(parts[8].strip()))
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
    print("\n" + "=" * 80)
    print("RTL_proposed_2 TESTBENCH SIMULATION SUITE")
    print("=" * 80)
    print(f"Workspace: {WORKSPACE_ROOT}")
    print(f"Simulation Log Directory: {SIM_LOG_DIR}")
    print(f"Results Directory: {SIM_RESULTS_DIR}")
    print(f"VCD Directory: {VCD_RESULTS_DIR}")
    print(f"Start Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 80 + "\n")

    missing_sources = [src for src in RTL_SOURCES if not src.exists()]
    if missing_sources:
        print("WARNING: Some RTL sources not found:")
        for src in missing_sources:
            print(f"  - {src}")

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

    max_workers = min(8, multiprocessing.cpu_count())
    print(f"Executing with {max_workers} parallel workers...\n")

    results = {}
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {executor.submit(run_testbench, (dt, tc)): (dt, tc) for dt, tc in test_queue}

        for future in tqdm(as_completed(futures), total=len(futures), desc="Testbenches", unit="test"):
            test_name, success = future.result()
            results[test_name] = success

    print("\n" + "=" * 80)
    print("SIMULATION RESULTS SUMMARY")
    print("=" * 80 + "\n")

    results_by_type = {}
    for data_type in TESTBENCHES.keys():
        results_by_type[data_type] = {}
        for tb_config in TESTBENCHES[data_type]:
            level = tb_config["level"]
            test_name = f"{data_type}_{level}"
            results_by_type[data_type][level] = results.get(test_name, False)

    total_tests = len(results)
    passed_tests = sum(1 for value in results.values() if value)

    print(f"Total Tests: {total_tests}")
    print(f"Passed: {passed_tests}")
    print(f"Failed: {total_tests - passed_tests}")
    print(f"Success Rate: {(passed_tests / total_tests * 100):.1f}%\n")

    print("Detailed Results by Data Type:")
    print("-" * 80)

    for data_type, levels in results_by_type.items():
        type_passed = sum(1 for value in levels.values() if value)
        type_total = len(levels)
        status = "PASS" if type_passed == type_total else "FAIL"
        print(f"{data_type:15} {status} ({type_passed}/{type_total})")
        for level, success in levels.items():
            result_status = "OK" if success else "ERR"
            csv_file = SIM_RESULTS_DIR / data_type / f"{data_type}_{level}_results.csv"
            csv_exists = csv_file.exists()
            mean_error = calculate_mean_error(csv_file) if csv_exists else "N/A"
            print(f"  {level}: {result_status} | CSV: {'YES' if csv_exists else 'NO'} | Mean Error: {mean_error}")
        print()

    print("Output Locations:")
    print(f"  Logs: {SIM_LOG_DIR}")
    print(f"  CSV Results: {SIM_RESULTS_DIR}")
    print(f"  VCD Files: {VCD_RESULTS_DIR}")


if __name__ == "__main__":
    main()
