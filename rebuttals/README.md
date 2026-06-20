# Extended Benchmarking and Genus Reports

This directory contains expanded supplementary data and code generated to provide comprehensive benchmarking and hardware evaluation metrics. To facilitate rapid verification, we have organized the direct results and source codes below.

## ⚡ Direct Access: Energy CSV Files (energy_summary.csv)
We have evaluated throughput-normalized energy (Energy-per-Multiply and Energy-per-Inference) for **P-ALAM** against exact baselines and SOTA designs. You can view the raw aggregated data directly via the CSV links below:
- **[Average Energy Summary (energy_summary.csv)](./software_benchmarks/energy_summary.csv)**
- **[Detailed Energy Comparison (energy_comparison.csv)](./software_benchmarks/energy_comparison.csv)**
- **[Hardware Genus Synthesis Metrics (multiplier_report_tabulation.csv)](./hardware_genus_reports/multiplier_report_tabulation.csv)**

*Additional raw model traces (Pareto boundaries) for BERT, HuBERT, and LeNet-5 can be found in the [`software_benchmarks/`](./software_benchmarks/) directory.*

## 💻 Direct Access: P-ALAM and ALAM RTL Codes & Testbenches
The underlying Verilog modules containing our 3-stage pipelined architecture and operand isolation gating (as detailed in the rebuttal) are provided here:
- **[P-ALAM Source Code (RTL_proposed_2)](./hardware_RTL/RTL_proposed_2/)**: Contains the fully pipelined, region-aware approximate multiplier modules.
- **[ALAM Source Code (RTL_proposed)](./hardware_RTL/RTL_proposed/)**: The foundational, unpipelined variant.
- **[Simulation Testbenches](./testbenches/)**: Exhaustive verification environments corresponding to the proposed hardware.

## Summary of Empirical Improvements
- **Throughput & Timing:** The pipelined P-ALAM reliably scales to **1.0 GHz**, entirely overcoming the combinational critical path bottlenecks that plague ALAM (~0.62–0.71 GHz) and competing SOTA structures.
- **Area & Power Efficiency:** For highly quantized logic (e.g., INT8, Fixed8), P-ALAM achieves an area reduction of over **50%** versus ALAM and curtails energy-per-multiply from 32.89 pJ (ALAM) down to just **1.08 pJ**.
- **Integer Stability:** While un-gated SOTA architectures (e.g., scaleTRIM) exhibit catastrophic numerical divergence in integer math (with mean errors ranging up to 131%), P-ALAM bounds this instability and preserves application accuracy inherently via its region-aware logic.
