# Approx-T Parallel Pipeline

Approx-T Parallel Pipeline is a research codebase for configurable approximate multipliers and their evaluation across RTL simulation, mantissa-region analysis, synthesis reporting, and application-level benchmarking.

The repository contains three RTL design families:

- `RTL/`: baseline Approx-T implementation
- `RTL_proposed/`: non-pipelined proposed design
- `RTL_proposed_2/`: pipelined proposed design

It also includes Python utilities for running Verilog testbenches, generating mantissa-region figures, producing synthesis visualizations, and benchmarking the multipliers inside BERT, HuBERT, and LeNet workloads.

## What Is In The Repo

- `Applications/multiplier_benchmark.py`: end-to-end application benchmark for `lenet`, `bert`, and `hubert`
- `mantissa_region_analysis.py`: generates mantissa-region and error-analysis figures for `RTL_proposed` and `RTL_proposed_2`
- `base_testbench_simulation.py`: runs the baseline `RTL/` simulation suite
- `rtl_proposed_testbench_simulation.py`: runs the `RTL_proposed/` simulation suite
- `rtl_proposed_2_testbench_simulation.py`: runs the `RTL_proposed_2/` simulation suite
- `run_rtl_proposed_tests.py`: small helper for updated `RTL_proposed` unsigned-integer runs
- `generate_synthesis_images.py`: generates synthesis/report-oriented figures
- `RTL/`, `RTL_proposed/`, `RTL_proposed_2/`: Verilog source trees
- `tb/`: testbenches, organized by variant and datatype
- `reports/`, `Simulation_log/`, `Simulation_Results/`, `Results_tabulation/`: generated outputs and aggregated results

## Repository Layout

```text
.
├── README.md
├── Applications/
│   ├── multiplier_benchmark.py
│   ├── bert_sst2/
│   ├── HuBert_model/
│   └── Lenet_5_MNIST/
├── RTL/
├── RTL_proposed/
├── RTL_proposed_2/
├── tb/
│   ├── Unsigned_int/
│   ├── Signed_int/
│   ├── Fixed_point/
│   ├── Floating_point/
│   ├── RTL_proposed/
│   ├── RTL_proposed_2/
│   └── common/
├── reports/
├── Results_tabulation/
├── Simulation_log/
├── Simulation_Results/
├── scripts/
├── model/
└── mantissa_region_analysis.py
```

## Main Workflows

### 1. RTL Simulation

Use the Python runners instead of shell scripts.

Baseline RTL:

```bash
python3 base_testbench_simulation.py
```

Proposed non-pipelined RTL:

```bash
python3 rtl_proposed_testbench_simulation.py
```

Proposed pipelined RTL:

```bash
python3 rtl_proposed_2_testbench_simulation.py
```

These runners compile testbenches with `iverilog`, execute them with `vvp`, and write outputs into:

- `Simulation_log/`
- `Simulation_Results/`
- `Results_tabulation/vcd/`

### 2. Mantissa Region Analysis

Generate mantissa-space plots and region-division figures:

```bash
python3 mantissa_region_analysis.py
```

This script generates figures for both `RTL_proposed` and `RTL_proposed_2`, including:

- region analysis plots
- contour plots
- error plots
- region-division plots
- detailed region breakdown plots

Typical outputs are written in the repository root, for example:

- `mantissa_rtl_proposed_region_divisions.png`
- `mantissa_rtl_proposed_2_region_divisions.png`

### 3. Application-Level Benchmarking

Run the multiplier benchmark on the supported ML models:

```bash
python3 Applications/multiplier_benchmark.py
```

Useful examples:

```bash
python3 Applications/multiplier_benchmark.py --models lenet
python3 Applications/multiplier_benchmark.py --models bert --device cpu
python3 Applications/multiplier_benchmark.py --models bert hubert --out_dir Results_tabulation
python3 Applications/multiplier_benchmark.py --models lenet bert hubert --numeric_modes fp32 int8
```

The benchmark currently supports:

- `lenet`
- `bert`
- `hubert`

Key command-line controls in `Applications/multiplier_benchmark.py` include:

- `--models`
- `--designs`
- `--device`
- `--batch_size`
- `--max_samples`
- `--level`
- `--nsga_pop`
- `--nsga_generations`
- `--nsga_mutation`
- `--search_workers`
- `--search_max_evals`
- `--search_max_seconds`
- `--search_layer_budget`
- `--hide_progress`
- `--numeric_modes`
- `--out_dir`

Outputs are written under the chosen output directory, by default `Results_tabulation/`, including per-model folders, plots, JSON summaries, CSV exports, and the NSGA-II workflow figure.

### 4. Synthesis Figure Generation

If you want report/synthesis-oriented images:

```bash
python3 generate_synthesis_images.py
```

Additional synthesis collateral also exists under:

- `scripts/`
- `constraints/`
- `reports/`

## Supported RTL Coverage

The repository includes simulation/testbench support for:

- unsigned integer multiplication
- signed integer multiplication
- fixed-point multiplication
- floating-point multiplication

The baseline `RTL/` tree includes testbenches across `L0` to `L5`.  
The `RTL_proposed/` and `RTL_proposed_2/` trees currently focus on `L0`, `L1`, and `L2`.

## Important Output Locations

- `Simulation_log/`: compile and run logs
- `Simulation_Results/`: CSV-style or run-specific simulation outputs
- `Results_tabulation/`: benchmark outputs, VCD outputs, and summary artifacts
- `reports/`: synthesis tabulations and reporting outputs
- `figures/`: figure assets and report-ready visuals

## Dependencies

The exact environment depends on the workflow you run.

Common requirements:

- `python3`
- `iverilog`
- `vvp`

For the ML benchmarking and plotting flows, the code uses packages including:

- `numpy`
- `matplotlib`
- `torch`
- `tqdm`
- `transformers`
- `datasets`
- `sympy`

Some application benchmarks expect local model weights and cached datasets already present in the paths referenced by the scripts.

## Notes On Current State

- The repository has been cleaned to keep a single main `README.md`.
- Older helper shell scripts were removed; use the Python entry points listed above.
- Several generated figures, logs, and result files are intentionally present in-tree as research outputs.
- `RTL_proposed.zip` is still present as a packaged artifact.

## Recommended Starting Points

If you are new to the repo:

1. Read this README.
2. Inspect `RTL_proposed/` and `RTL_proposed_2/` for the main Verilog implementations.
3. Run `python3 mantissa_region_analysis.py` to regenerate the paper-style mantissa figures.
4. Run one simulation workflow, for example `python3 rtl_proposed_testbench_simulation.py`.
5. Run `python3 Applications/multiplier_benchmark.py --models lenet` if you want to test the application benchmark path first.

## Troubleshooting

If RTL simulation fails:

```bash
which iverilog
which vvp
```

If application benchmarking fails because of missing cached assets, verify the local paths used by:

- `Applications/multiplier_benchmark.py`
- `Applications/bert_sst2/`
- `Applications/HuBert_model/`
- `Applications/Lenet_5_MNIST/`

If plotting produces matplotlib cache warnings in restricted environments, set:

```bash
export MPLCONFIGDIR=/tmp/matplotlib
```

## Related Files

- [Applications/multiplier_benchmark.py](Applications/multiplier_benchmark.py)
- [mantissa_region_analysis.py](mantissa_region_analysis.py)
- [MANTISSA_REGION_ANALYSIS.md](MANTISSA_REGION_ANALYSIS.md)
- [TESTBENCH_STANDARDIZATION.md](TESTBENCH_STANDARDIZATION.md)
