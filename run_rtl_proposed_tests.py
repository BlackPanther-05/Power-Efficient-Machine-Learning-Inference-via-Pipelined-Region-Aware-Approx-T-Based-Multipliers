#!/usr/bin/env python3
"""Run RTL_proposed unsigned_int tests with updated corrections."""

import subprocess
import tempfile
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from tqdm import tqdm

ROOT = Path(__file__).resolve().parent
RTL_DIR = ROOT / "RTL_proposed"
LOG_DIR = ROOT / "Simulation_log"
RESULT_DIR = ROOT / "Simulation_Results" / "RTL_proposed" / "Unsigned_int"

SIMULATIONS = [
    ("tb/RTL_proposed/Unsigned_int/tb_unsigned_int_L0.v", "test_Unsigned_int_L0", "Unsigned_int_L0_results.csv"),
    ("tb/RTL_proposed/Unsigned_int/tb_unsigned_int_L1.v", "test_Unsigned_int_L1", "Unsigned_int_L1_results.csv"),
    ("tb/RTL_proposed/Unsigned_int/tb_unsigned_int_L2.v", "test_Unsigned_int_L2", "Unsigned_int_L2_results.csv"),
]


def run_iverilog_sim(testbench_rel, output_name, csv_name):
    testbench = ROOT / testbench_rel
    csv_path = RESULT_DIR / csv_name
    log_path = LOG_DIR / f"{output_name}_sim.log"

    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            executable = Path(temp_dir) / output_name
            compile_cmd = [
                "iverilog",
                "-g2012",
                "-o",
                str(executable),
                str(RTL_DIR / "unsigned_int_mul.v"),
                str(RTL_DIR / "approx_t.v"),
                str(RTL_DIR / "leading_one_detector.v"),
                str(RTL_DIR / "bit_mask_sel.v"),
                str(testbench),
            ]
            subprocess.run(compile_cmd, cwd=ROOT, check=True, capture_output=True, text=True)
            result = subprocess.run(
                ["vvp", str(executable)],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            log_path.write_text(result.stdout)
        return f"✓ {testbench_rel}"
    except subprocess.CalledProcessError as exc:
        details = exc.stderr or exc.stdout or str(exc)
        return f"✗ {testbench_rel}: {details.strip()[:100]}"


def main():
    RESULT_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Running {len(SIMULATIONS)} RTL_proposed Unsigned_int simulations...\n")

    with ThreadPoolExecutor(max_workers=min(3, len(SIMULATIONS))) as executor:
        futures = [executor.submit(run_iverilog_sim, *simulation) for simulation in SIMULATIONS]
        for future in tqdm(as_completed(futures), total=len(futures), desc="Simulating", unit="test"):
            tqdm.write(future.result())

    print("\nAll simulations completed.")


if __name__ == "__main__":
    main()
