# ICCAD Rebuttal Addendum: Extensive Benchmarking and Genus Reports

This directory contains the expanded supplementary data generated explicitly to address reviewer comments for our ICCAD submission. We provide end-to-end hardware synthesis metrics as well as comprehensive neural-network application trace results comparing P-ALAM and ALAM architectures against state-of-the-art (SOTA) combinational approximate multipliers.

## Directory Structure

### `software_benchmarks/`
Contains the complete Pareto optimality analyses and sensitivity sweeps extracted from our NSGA-II search (`multiplier_benchmark.py`).
- **Energy Analysis:** `energy_summary.csv` and `energy_comparison.csv` aggregate the throughput-normalized energy results. They detail the energy-per-multiply (in pJ) and the total energy-per-inference (in µJ) across all tested models and precision levels.
- **Model Traces:** Subdirectories for `bert`, `hubert`, and `lenet` contain `*_pareto.csv` files defining the exact Pareto boundaries. As discussed in our rebuttal, P-ALAM robustly occupies the Pareto front while maintaining an accuracy drop of <1% with unparalleled steady-state throughput.

### `hardware_genus_reports/`
Contains the Cadence Genus 45nm synthesis data proving the hardware dominance of P-ALAM.
- **SOTA Reports:** Includes complete timing, area, and power metrics for baseline implementations as well as SOTA multipliers (ACBAM, OPACT, FPLNS, and scaleTRIM).
- **Summary Metrics:** Validation of P-ALAM’s strict timing closure at 1.0 GHz (1000ps path delay) across all datatypes (FP32, FP8, INT8, UINT8, Fixed8) along with precise component-level power breakdowns.

## Summary of Empirical Improvements
- **Throughput & Timing:** P-ALAM reliably scales to **1.0 GHz**, overcoming the severe combinational critical path bottlenecks of ALAM (~0.62–0.71 GHz) and competing SOTA designs.
- **Area & Power Efficiency:** For highly quantized logic (e.g., INT8, Fixed8), P-ALAM achieves an area reduction of over **50%** versus ALAM and curtails energy-per-multiply from 32.89 pJ (ALAM) to **1.08 pJ** (P-ALAM).
- **Integer Stability:** While SOTA architectures like scaleTRIM exhibit catastrophic numerical divergence in integer math (with mean errors ranging up to 131%), P-ALAM bounds this instability and preserves application accuracy inherently via region-aware pipelining.
