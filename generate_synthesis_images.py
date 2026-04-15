#!/usr/bin/env python3
"""
Generate polished high-level RTL visualization images for the Approx-T Verilog codebase.

This script does not run logic synthesis. Instead, it reads the RTL source and creates:
1. IEEE-style overview posters for each RTL variant
2. Datatype-centric architecture flow diagrams
3. Module interface cards for every Verilog module in the target folders
4. A simple HTML gallery tying everything together

Target folders:
    - RTL
    - RTL_proposed
    - RTL_proposed_2
"""

from __future__ import annotations

import html
import math
import re
import textwrap
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Tuple
import subprocess
import shutil

import matplotlib.pyplot as plt
from matplotlib import patheffects
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.patches import Circle, FancyArrowPatch, FancyBboxPatch, Polygon
from matplotlib.patches import Rectangle


BASE_DIR = Path(__file__).resolve().parent
RTL_VARIANTS = ["RTL", "RTL_proposed", "RTL_proposed_2"]
DATATYPE_MODULES = [
    "unsigned_int_mul",
    "signed_int_mul",
    "fixed_point_mul",
    "floating_point_mul",
]
BLOCK_MODULES = DATATYPE_MODULES + ["approx_t"]
SHARED_MODULES = ["approx_t", "bit_mask_sel", "leading_one_detector"]
OUTPUT_ROOT = BASE_DIR / "figures"
BLOCK_DIR = OUTPUT_ROOT / "block"
OVERVIEW_DIR = OUTPUT_ROOT / "overview"
DATATYPE_DIR = OUTPUT_ROOT / "flow"
MODULE_DIR = OUTPUT_ROOT / "cards"
REPORT_DIR = OUTPUT_ROOT / "report"
SHOW_TITLES = False
YOSYS_DIR = OUTPUT_ROOT / "yosys"
YOSYS_BIN = shutil.which("yosys")

FILE_HEADER_RE = re.compile(r"^\s*module\s+(\w+)", re.MULTILINE)
PORT_BLOCK_RE = re.compile(r"module\s+\w+(?:\s*#\([\s\S]*?\))?\s*\(([\s\S]*?)\);\s*", re.MULTILINE)
PORT_RE = re.compile(r"\b(input|output|inout)\b\s*(?:reg|wire|signed)?\s*(\[[^\]]+\])?\s*([A-Za-z_]\w*)")
INSTANCE_RE = re.compile(r"^\s*(\w+)\s*(?:#\s*\([\s\S]*?\))?\s+\w+\s*\(", re.MULTILINE)
LOCALPARAM_RE = re.compile(r"\blocalparam\b")
ALWAYS_RE = re.compile(r"\balways\s*@")
ASSIGN_RE = re.compile(r"\bassign\b")


PALETTE = {
    "navy": "#14324B",
    "blue": "#1D5D9B",
    "cyan": "#2E8BC0",
    "teal": "#1F8A70",
    "mint": "#BCE3D6",
    "gold": "#D8A31A",
    "sand": "#F4EBD0",
    "coral": "#C45C4E",
    "slate": "#4A5A6A",
    "ink": "#1D1F23",
    "white": "#FFFFFF",
    "panel": "#F9FBFD",
    "line": "#D6E0E8",
}


@dataclass
class ModuleInfo:
    variant: str
    file_path: Path
    module_name: str
    ports: List[Tuple[str, str, str]] = field(default_factory=list)
    instances: List[str] = field(default_factory=list)
    lines: int = 0
    assign_count: int = 0
    always_count: int = 0
    localparam_count: int = 0
    is_pipelined: bool = False
    valid_signals: List[str] = field(default_factory=list)
    clocked_signals: List[str] = field(default_factory=list)


def ensure_dirs() -> None:
    for path in [OUTPUT_ROOT, BLOCK_DIR, OVERVIEW_DIR, DATATYPE_DIR, MODULE_DIR, REPORT_DIR, YOSYS_DIR]:
        path.mkdir(parents=True, exist_ok=True)
    for variant in RTL_VARIANTS:
        (BLOCK_DIR / variant).mkdir(exist_ok=True)
        (DATATYPE_DIR / variant).mkdir(exist_ok=True)
        (MODULE_DIR / variant).mkdir(exist_ok=True)
        (YOSYS_DIR / variant).mkdir(exist_ok=True)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def parse_module(file_path: Path, variant: str) -> ModuleInfo:
    content = read_text(file_path)
    header = FILE_HEADER_RE.search(content)
    module_name = header.group(1) if header else file_path.stem

    ports: List[Tuple[str, str, str]] = []
    port_block = PORT_BLOCK_RE.search(content)
    if port_block:
        for direction, width, name in PORT_RE.findall(port_block.group(1)):
            ports.append((direction, width.strip() if width else "", name))

    raw_instances = INSTANCE_RE.findall(content)
    instances = [
        mod for mod in raw_instances
        if mod not in {"module", "if", "for", "case", "assign", "always"}
        and mod != module_name
    ]

    valid_signals = sorted(set(re.findall(r"\bvalid(?:_[A-Za-z0-9]+|[A-Za-z0-9_]*)\b", content)))
    clocked_signals = sorted(set(re.findall(r"\b(clk|clock|rst|rst_n)\b", content)))
    is_pipelined = bool({"clk", "valid_in", "valid_out"} & set(valid_signals + clocked_signals)) and bool(ALWAYS_RE.search(content))

    return ModuleInfo(
        variant=variant,
        file_path=file_path,
        module_name=module_name,
        ports=ports,
        instances=instances,
        lines=len(content.splitlines()),
        assign_count=len(ASSIGN_RE.findall(content)),
        always_count=len(ALWAYS_RE.findall(content)),
        localparam_count=len(LOCALPARAM_RE.findall(content)),
        is_pipelined=is_pipelined,
        valid_signals=valid_signals,
        clocked_signals=clocked_signals,
    )


def discover_modules() -> Dict[str, Dict[str, ModuleInfo]]:
    data: Dict[str, Dict[str, ModuleInfo]] = defaultdict(dict)
    for variant in RTL_VARIANTS:
        for file_path in sorted((BASE_DIR / variant).glob("*.v")):
            info = parse_module(file_path, variant)
            data[variant][info.module_name] = info
    return data


def wrapped(text: str, width: int) -> str:
    return "\n".join(textwrap.wrap(text, width=width, break_long_words=False))


def bullet_lines(items: List[str], width: int) -> List[str]:
    lines: List[str] = []
    for item in items:
        chunks = textwrap.wrap(item, width=width, break_long_words=False)
        if not chunks:
            continue
        lines.append(f"• {chunks[0]}")
        for chunk in chunks[1:]:
            lines.append(f"  {chunk}")
    return lines


def set_ieee_style() -> None:
    """Global Matplotlib style tuned for IEEE paper figures."""
    plt.rcParams.update(
        {
            "font.family": "serif",
            "font.serif": ["Times New Roman", "Times", "DejaVu Serif"],
            "font.size": 10,
            "axes.titlesize": 10,
            "axes.labelsize": 9,
            "figure.dpi": 220,
            "savefig.dpi": 300,
            "figure.facecolor": "white",
            "axes.facecolor": "white",
            "axes.edgecolor": "#111111",
            "xtick.color": "#111111",
            "ytick.color": "#111111",
        }
    )


def add_gradient_background(ax, top: str = "#FFFFFF", bottom: str = "#EAF2F8") -> None:
    # Use solid white to match IEEE print expectations.
    ax.set_facecolor("white")


def add_title(ax, title: str, subtitle: str) -> None:
    if not SHOW_TITLES:
        return
    ax.text(
        0.05, 0.94, title,
        fontsize=22, fontweight="bold", color=PALETTE["navy"], ha="left", va="top",
        transform=ax.transAxes,
    )
    ax.text(
        0.05, 0.90, subtitle,
        fontsize=10.0, color=PALETTE["slate"], ha="left", va="top",
        transform=ax.transAxes,
    )
    ax.plot([0.05, 0.95], [0.875, 0.875], color=PALETTE["line"], lw=2, transform=ax.transAxes)


def panel(ax, x: float, y: float, w: float, h: float, fc: str = PALETTE["white"], ec: str = PALETTE["line"], radius: float = 0.02, alpha: float = 1.0) -> FancyBboxPatch:
    box = FancyBboxPatch(
        (x, y), w, h,
        boxstyle=f"round,pad=0.012,rounding_size={radius}",
        linewidth=1.4, edgecolor=ec, facecolor=fc, alpha=alpha,
        transform=ax.transAxes, zorder=2
    )
    box.set_path_effects([patheffects.withSimplePatchShadow(offset=(2, -2), alpha=0.10)])
    ax.add_patch(box)
    return box


def label(ax, x: float, y: float, text: str, size: float = 10, color: str = PALETTE["ink"], weight: str = "normal", ha: str = "left", va: str = "center") -> None:
    ax.text(x, y, text, fontsize=size, color=color, fontweight=weight, ha=ha, va=va, transform=ax.transAxes, zorder=3)


def arrow(ax, x1: float, y1: float, x2: float, y2: float, color: str = PALETTE["blue"], lw: float = 2.0, text: str = "") -> None:
    patch = FancyArrowPatch(
        (x1, y1), (x2, y2),
        arrowstyle="-|>", mutation_scale=14, lw=lw, color=color,
        transform=ax.transAxes, zorder=3,
        connectionstyle="arc3,rad=0.0"
    )
    ax.add_patch(patch)


def summarize_variant(modules: Dict[str, ModuleInfo]) -> List[str]:
    approx = modules.get("approx_t")
    unsigned = modules.get("unsigned_int_mul")
    floating = modules.get("floating_point_mul")
    facts = []
    if approx:
        if approx.is_pipelined:
            facts.append("Three-stage registered Approx-T core with valid-aligned datapath")
        elif approx.localparam_count >= 5:
            facts.append("Region-aware Approx-T core using localparam-selected centers and constants")
        else:
            facts.append("Combinational Approx-T core with configurable precision contributions")
    if unsigned:
        facts.append("Unsigned datapath normalizes inputs with leading-one detection before approximate multiply")
    if floating:
        facts.append("Floating-point path isolates sign/exponent handling from mantissa approximation")
    if any(m.is_pipelined for m in modules.values()):
        facts.append("Pipeline-friendly structure aimed at higher throughput and timing closure")
    else:
        facts.append("Single-cycle style datapath favors simplicity and direct combinational interpretation")
    return facts[:4]


def variant_tagline(variant: str, modules: Dict[str, ModuleInfo]) -> str:
    if variant == "RTL":
        return "Baseline architecture poster for the original Approx-T family"
    if variant == "RTL_proposed":
        return "Region-refined architecture poster for the improved combinational variant"
    if any(m.is_pipelined for m in modules.values()):
        return "Pipeline-oriented architecture poster for the staged high-throughput variant"
    return "High-level architecture poster"


def draw_overview_poster(variant: str, modules: Dict[str, ModuleInfo], output_path: Path) -> None:
    fig, ax = plt.subplots(figsize=(18, 10), dpi=220)
    ax.set_axis_off()
    add_gradient_background(ax, "#FDFEFE", "#EAF2F8")
    add_title(ax, f"{variant}  •  RTL Architecture Overview", variant_tagline(variant, modules))

    panel(ax, 0.05, 0.62, 0.26, 0.20, fc="#F7FBFF")
    label(ax, 0.07, 0.785, "Design Notes", size=12, weight="bold", color=PALETTE["navy"])
    for idx, fact in enumerate(bullet_lines(summarize_variant(modules), 32)[:6]):
        label(ax, 0.075, 0.75 - idx * 0.034, fact, size=8.5, color=PALETTE["slate"])

    panel(ax, 0.05, 0.20, 0.14, 0.26, fc="#FFFDF7")
    label(ax, 0.07, 0.41, "Inputs", size=12, weight="bold", color=PALETTE["navy"])
    for idx, text in enumerate(["Unsigned A,B", "Signed A,B", "Fixed A,B", "Float A,B", "Region_Enable", "Region_Conf_Mask"]):
        label(ax, 0.075, 0.37 - idx * 0.042, text, size=8.7)

    panel(ax, 0.22, 0.20, 0.16, 0.26, fc="#F4FAF7")
    label(ax, 0.24, 0.41, "Preprocess", size=12, weight="bold", color=PALETTE["navy"])
    prep = ["Sign extraction", "Leading-one detect", "Normalize / shift", "Exponent path"]
    if any(m.is_pipelined for m in modules.values()):
        prep.append("Valid alignment")
    for idx, text in enumerate(prep):
        label(ax, 0.245, 0.37 - idx * 0.042, text, size=8.6)

    core_fc = "#F3F8FD" if variant != "RTL_proposed_2" else "#F1F8F4"
    panel(ax, 0.44, 0.18, 0.22, 0.30, fc=core_fc, ec="#3A6EA5")
    label(ax, 0.55, 0.42, "Approx-T Core", size=15, weight="bold", color=PALETTE["navy"], ha="center")
    core_lines = [
        "L0 piecewise approximation",
        "L1 local correction",
        "L2 refinement term",
        "Mask-based contribution select",
    ]
    if variant == "RTL_proposed_2":
        core_lines = [
            "Stage 1: register inputs",
            "Stage 2: region + corrections",
            "Stage 3: accumulate result",
            "per-region cfg + gating",
        ]
    elif variant == "RTL_proposed":
        core_lines = [
            "4-region Level-0 base",
            "Local x/y refinements",
            "Compact L1 / L2 adds",
            "Mask-controlled sum",
        ]
    for idx, line in enumerate(core_lines):
        label(ax, 0.55, 0.36 - idx * 0.048, line, size=8.6, color=PALETTE["slate"], ha="center")

    panel(ax, 0.72, 0.20, 0.18, 0.26, fc="#FAF4FF")
    label(ax, 0.74, 0.41, "Outputs", size=12, weight="bold", color=PALETTE["navy"])
    out_lines = ["Unsigned R", "Signed R", "Fixed-point R", "Float R"]
    if any(m.is_pipelined for m in modules.values()):
        out_lines.append("valid_out")
    for idx, text in enumerate(out_lines):
        label(ax, 0.745, 0.37 - idx * 0.042, text, size=8.7)

    arrow(ax, 0.19, 0.32, 0.22, 0.32)
    arrow(ax, 0.38, 0.32, 0.44, 0.32)
    arrow(ax, 0.66, 0.32, 0.72, 0.32)

    panel(ax, 0.05, 0.52, 0.85, 0.06, fc=PALETTE["navy"], ec=PALETTE["navy"])
    label(ax, 0.07, 0.545, "Datatypes", size=11, weight="bold", color="white")
    x_positions = [0.30, 0.46, 0.62, 0.78]
    titles = ["Unsigned", "Signed", "Fixed", "Float"]
    colors = ["#F6C667", "#E98E7D", "#77CBB9", "#7FB3D5"]
    for x, title_text, color in zip(x_positions, titles, colors):
        panel(ax, x - 0.06, 0.525, 0.11, 0.035, fc=color, ec=color, radius=0.01)
        label(ax, x - 0.005, 0.54, title_text, size=8.4, weight="bold", color=PALETTE["ink"], ha="center")

    panel(ax, 0.72, 0.62, 0.20, 0.18, fc="#FFFFFF")
    label(ax, 0.74, 0.76, "Metrics", size=12, weight="bold", color=PALETTE["navy"])
    metrics = [
        f"Modules: {len(modules)}",
        f"Clocked: {sum(1 for m in modules.values() if m.is_pipelined)}",
        f"Assigns: {sum(m.assign_count for m in modules.values())}",
        f"Always: {sum(m.always_count for m in modules.values())}",
    ]
    for idx, metric in enumerate(metrics):
        label(ax, 0.745, 0.72 - idx * 0.04, metric, size=8.7, color=PALETTE["slate"])

    fig.savefig(output_path, bbox_inches="tight", facecolor="white", pad_inches=0.18)
    plt.close(fig)


def datatype_description(module_name: str, variant: str) -> List[str]:
    if module_name == "unsigned_int_mul":
        desc = [
            "Leading-one detectors estimate operand magnitudes",
            "Operands are normalized before entering Approx-T",
            "Post-scaling reconstructs the magnitude-domain result",
        ]
    elif module_name == "signed_int_mul":
        desc = [
            "Sign path is separated from magnitude path",
            "Magnitude multiplication reuses unsigned datapath",
            "Final sign restoration reconstructs signed product",
        ]
    elif module_name == "fixed_point_mul":
        desc = [
            "Signed inputs are converted to magnitude form",
            "Approximate multiplication runs on normalized unsigned data",
            "Arithmetic right shift re-applies the binary point",
        ]
    else:
        desc = [
            "Sign, exponent, and mantissa are processed separately",
            "Approx-T multiplies mantissas while exponent path stays exact",
            "Overflow/underflow and renormalization rebuild IEEE-like output",
        ]
    if variant == "RTL_proposed_2":
        desc.append("Pipeline registers maintain throughput and result validity")
    elif variant == "RTL_proposed":
        desc.append("Refined region partitioning improves approximation fidelity")
    else:
        desc.append("Compact direct datapath highlights the baseline approximation flow")
    return desc


def datatype_steps(module_name: str, variant: str) -> List[Tuple[str, str, str]]:
    if module_name == "unsigned_int_mul":
        return [
            ("Input Capture", "Receive A, B and region config", "#F6C667"),
            ("Magnitude Analysis", "Leading-one detector finds dominant bit positions", "#F0D89B"),
            ("Normalization", "Shift operands into Approx-T-friendly range", "#8CC7E8"),
            ("Approx-T Evaluation", "Per-region L0/L1/L2 via Region_Conf_Mask", "#5EA3D8"),
            ("Output Scaling", "Shift result back using accumulated leading-one position", "#77CBB9"),
        ]
    if module_name == "signed_int_mul":
        return [
            ("Sign Split", "Extract sign and convert inputs to magnitudes", "#F4B6A6"),
            ("Unsigned Core", "Reuse unsigned approximate multiplier datapath", "#8CC7E8"),
            ("Sign Restore", "Apply two's-complement restoration to result", "#77CBB9"),
        ]
    if module_name == "fixed_point_mul":
        return [
            ("Fixed Input Decode", "Separate sign and fixed-point magnitudes", "#F4B6A6"),
            ("Unsigned Core", "Approximate magnitude multiplication", "#8CC7E8"),
            ("Binary-Point Reinsert", "Arithmetic shift by DEC_POINT_POS", "#77CBB9"),
        ]
    steps = [
        ("Field Split", "Decode sign, exponent, and mantissa fields", "#F6C667"),
        ("Mantissa Approximation", "Multiply mantissas through Approx-T", "#8CC7E8"),
        ("Renormalization", "Inspect shift bits and choose mantissa slice", "#5EA3D8"),
        ("Exponent Control", "Add exponents and detect over/underflow", "#F0D89B"),
        ("Field Merge", "Recombine sign, exponent, and mantissa", "#77CBB9"),
    ]
    if variant == "RTL_proposed_2":
        steps.insert(2, ("Pipeline Alignment", "Delay exponent/sign fields to match mantissa core latency", "#C9D7F8"))
    return steps


def module_port_summary(info: ModuleInfo) -> Tuple[List[str], List[str], List[str]]:
    inputs = []
    outputs = []
    bidir = []
    for direction, width, name in info.ports:
        token = f"{name} {width}".strip()
        if direction == "input":
            inputs.append(token)
        elif direction == "output":
            outputs.append(token)
        else:
            bidir.append(token)
    return inputs[:8], outputs[:8], bidir[:8]


def block_stage_text(module_name: str, variant: str) -> List[Tuple[str, str]]:
    if module_name == "unsigned_int_mul":
        return [
            ("Input", "A, B, region cfg"),
            ("LOD", "find MSB positions"),
            ("Normalize", "shift into core range"),
            ("Approx-T", "L0 / L1 / L2 per region"),
            ("Scale", "restore output magnitude"),
        ]
    if module_name == "signed_int_mul":
        return [
            ("Input", "signed A, B, region cfg"),
            ("Sign/Mag", "extract sign, abs"),
            ("Unsigned Core", "reuse unsigned path"),
            ("Sign Restore", "2's complement if needed"),
        ]
    if module_name == "fixed_point_mul":
        return [
            ("Input", "fixed A, B, region cfg"),
            ("Sign/Mag", "magnitude conversion"),
            ("Unsigned Core", "approx multiply"),
            ("Shift", "apply DEC_POINT_POS"),
        ]
    if module_name == "approx_t":
        if variant == "RTL_proposed_2":
            return [
            ("Stage1 REG", "capture x,y,region cfg"),
            ("Stage2 Region", "L0 region select"),
            ("Stage2 Corr", "delta_f1/2"),
            ("Stage3 REG", "accumulate + output"),
        ]
    return [
        ("Inputs", "x,y,region cfg"),
        ("L0", "piecewise base"),
        ("L1", "local correction"),
        ("L2", "refinement add"),
    ]
    blocks = [
        ("Input", "float A, B, region cfg"),
        ("Field Split", "sign / exp / mantissa"),
        ("Approx-T", "mantissa product"),
        ("Renorm", "mantissa select + shift"),
        ("Exp Logic", "overflow / underflow"),
        ("Pack", "rebuild result"),
    ]
    if variant == "RTL_proposed_2":
        blocks.insert(3, ("Align", "pipeline match"))
    return blocks


def draw_block_diagram(variant: str, info: ModuleInfo, output_path: Path) -> None:
    fig, ax = plt.subplots(figsize=(18, 6.8), dpi=240)
    ax.set_axis_off()
    add_gradient_background(ax, "#FFFFFF", "#FFFFFF")
    add_title(ax, f"{variant}  •  {info.module_name}  •  Block Diagram", "Hardware-style pipeline view (no overlaps)")

    # Special detailed view for pipelined approx_t
    if info.module_name == "approx_t" and variant == "RTL_proposed_2":
        draw_approx_t_pipelined(ax)
        fig.savefig(output_path, bbox_inches="tight", facecolor="white", pad_inches=0.18)
        plt.close(fig)
        return

    # Define fixed 4-stage hardware pipeline: IN -> PRE -> CORE -> OUT
    stages = [
        ("IN", "Inputs / Region cfg"),
        ("PRE", "Normalize\nLOD / Sign"),
        ("CORE", "Approx-T\nL0/L1/L2"),
        ("OUT", "Scale / Pack"),
    ]
    # For floating point, rename PRE/OUT
    if info.module_name == "floating_point_mul":
        stages = [
            ("IN", "Sign/Exp/Mantissa"),
            ("PRE", "Align fields"),
            ("CORE", "Approx-T\nMantissa"),
            ("OUT", "Renorm/Pack"),
        ]
    # positions
    left = 0.10
    total_width = 0.80
    gap = 0.05
    box_w = (total_width - gap * (len(stages) - 1)) / len(stages)
    y = 0.40
    box_h = 0.22

    # Draw data baseline
    ax.plot([left - 0.04, left + total_width + 0.04], [y + box_h / 2, y + box_h / 2],
            transform=ax.transAxes, color="#222222", lw=1.6, zorder=1)
    # Draw clock rail with taps at each register boundary
    clk_y = y + box_h + 0.08
    ax.plot([left - 0.04, left + total_width + 0.04], [clk_y, clk_y],
            transform=ax.transAxes, color="#555555", lw=1.2, zorder=1)
    label(ax, left - 0.06, clk_y, "clk", size=9, color="#111111", ha="right")

    # Place stages
    reg_positions = []
    for idx, (title, desc) in enumerate(stages):
        x = left + idx * (box_w + gap)
        panel(ax, x, y, box_w, box_h, fc="#F2F4F7", ec="#222222", radius=0.016)
        label(ax, x + box_w / 2, y + box_h * 0.68, title, size=10, weight="bold", color="#111111", ha="center")
        label(ax, x + box_w / 2, y + box_h * 0.38, wrapped(desc, 16), size=8.0, color="#222222", ha="center")
        if idx < len(stages) - 1:
            arrow(ax, x + box_w, y + box_h / 2, x + box_w + gap, y + box_h / 2)
            reg_positions.append(x + box_w + gap / 2)

    # Pipeline registers for RTL_proposed_2
    if variant == "RTL_proposed_2":
        # place registers at every boundary for clarity
        for reg_x in reg_positions:
            ax.add_patch(FancyBboxPatch((reg_x - 0.006, y + 0.04), 0.012, box_h - 0.08,
                                        boxstyle="round,pad=0.002", fc="#111111", ec="#111111",
                                        transform=ax.transAxes, zorder=3))
            label(ax, reg_x, y + box_h * 0.92, "REG", size=7.5, color="#111111", ha="center")
            # clock tap
            ax.plot([reg_x, reg_x], [clk_y, y + box_h], transform=ax.transAxes, color="#555555", lw=1.0, zorder=2)

    # Notes band
    panel(ax, 0.08, 0.14, 0.84, 0.12, fc="#F8FBFE")
    notes = [
        f"Pipeline: {'yes' if info.is_pipelined else 'no'}",
        f"Source: {info.file_path.name}",
        f"Instances: {', '.join(info.instances[:3]) if info.instances else 'None'}",
    ]
    label(ax, 0.10, 0.22, "Notes", size=11, weight="bold", color=PALETTE["navy"])
    label(ax, 0.10, 0.18, "   ".join(notes), size=8.4, color=PALETTE["slate"])

    fig.savefig(output_path, bbox_inches="tight", facecolor="white", pad_inches=0.18)
    plt.close(fig)


def draw_approx_t_pipelined(ax):
    """
    Draw detailed hardware-style diagram for RTL_proposed_2 approx_t pipeline.
    """
    # Layout coordinates
    left = 0.08
    width = 0.82
    y_mid = 0.42
    h = 0.20
    gap = 0.05
    box_w = (width - gap * 3) / 4

    # Data path baseline
    ax.plot([left - 0.03, left + width + 0.03], [y_mid, y_mid], transform=ax.transAxes,
            color="#222222", lw=1.6, zorder=1)
    # Clock rail
    clk_y = y_mid + h + 0.08
    ax.plot([left - 0.03, left + width + 0.03], [clk_y, clk_y], transform=ax.transAxes,
            color="#555555", lw=1.2, zorder=1)
    label(ax, left - 0.04, clk_y, "clk", size=9, color="#111111", ha="right")

    def rect(x, title, lines):
        panel(ax, x, y_mid - h/2, box_w, h, fc="#FFFFFF", ec="#222222", radius=0.012)
        label(ax, x + box_w/2, y_mid + h*0.25, title, size=10, weight="bold", color="#111111", ha="center")
        for i, ln in enumerate(lines[:3]):
            label(ax, x + box_w/2, y_mid - h*0.05 - i*0.06, ln, size=8.1, color="#222222", ha="center")

    # Stage 1: input reg + normalize
    x1 = left
    rect(x1, "Stage1 REG", ["capture x,y,region cfg", "normalize inputs"])
    reg1 = x1 + box_w
    ax.add_patch(Rectangle((reg1-0.004, y_mid-h/2+0.02), 0.008, h-0.04, transform=ax.transAxes,
                           facecolor="#111111", edgecolor="#111111", zorder=3))
    ax.plot([reg1, reg1], [clk_y, y_mid+h/2], transform=ax.transAxes, color="#555555", lw=1.0)

    # Stage 2: region + delta
    x2 = x1 + box_w + gap
    rect(x2, "Stage2 Region", ["L0 region", "delta_f1 / delta_f2"])
    reg2 = x2 + box_w
    ax.add_patch(Rectangle((reg2-0.004, y_mid-h/2+0.02), 0.008, h-0.04, transform=ax.transAxes,
                           facecolor="#111111", edgecolor="#111111", zorder=3))
    ax.plot([reg2, reg2], [clk_y, y_mid+h/2], transform=ax.transAxes, color="#555555", lw=1.0)

    # Stage 3: mask select sum
    x3 = x2 + box_w + gap
    rect(x3, "Stage3 Sum", ["region-select L0/L1/L2", "accumulate"])
    reg3 = x3 + box_w
    ax.add_patch(Rectangle((reg3-0.004, y_mid-h/2+0.02), 0.008, h-0.04, transform=ax.transAxes,
                           facecolor="#111111", edgecolor="#111111", zorder=3))
    ax.plot([reg3, reg3], [clk_y, y_mid+h/2], transform=ax.transAxes, color="#555555", lw=1.0)

    # Stage 4: output reg
    x4 = x3 + box_w + gap
    rect(x4, "Stage4 REG", ["registered f", "valid_out"])
    reg4 = x4 + box_w
    ax.add_patch(Rectangle((reg4-0.004, y_mid-h/2+0.02), 0.008, h-0.04, transform=ax.transAxes,
                           facecolor="#111111", edgecolor="#111111", zorder=3))
    ax.plot([reg4, reg4], [clk_y, y_mid+h/2], transform=ax.transAxes, color="#555555", lw=1.0)

    # Arrows between stages
    for bx in [reg1, reg2, reg3]:
        arrow(ax, bx, y_mid, bx + gap, y_mid)

    # Notes band
    panel(ax, 0.10, 0.12, 0.80, 0.10, fc="#F8FBFE")
    label(ax, 0.12, 0.18, "RTL_proposed_2 Approx-T: clocked 3-stage datapath with per-region config + gating for L0/L1/L2 contributions.", size=8.3, color=PALETTE["slate"])


def draw_datatype_flowchart(variant: str, info: ModuleInfo, modules: Dict[str, ModuleInfo], output_path: Path) -> None:
    fig, ax = plt.subplots(figsize=(18, 9.5), dpi=220)
    ax.set_axis_off()
    add_gradient_background(ax, "#FFFFFF", "#EEF5FB")
    title = f"{variant}  •  {info.module_name}  •  High-Level Datapath"
    subtitle = "Source-derived functional flowchart for understanding the RTL at a glance"
    add_title(ax, title, subtitle)

    panel(ax, 0.05, 0.72, 0.90, 0.09, fc=PALETTE["navy"], ec=PALETTE["navy"])
    label(ax, 0.07, 0.745, "Interpretation", size=12, weight="bold", color=PALETTE["white"])
    label(ax, 0.07, 0.708, "Architectural reading of the RTL; whitespace increased to avoid overlap in print.", size=9.0, color="#E9F2FA")

    steps = datatype_steps(info.module_name, variant)
    total = len(steps)
    available = 0.84
    gap = 0.030
    step_w = min(0.13, (available - gap * (total - 1)) / max(total, 1))
    start_x = 0.07 + max(0.0, (available - (step_w * total + gap * (total - 1))) / 2)
    y = 0.41
    centers = []
    for idx, (name, desc, color) in enumerate(steps):
        x = start_x + idx * (step_w + gap)
        panel(ax, x, y, step_w, 0.19, fc=color, ec="#4A5A6A", radius=0.02)
        label(ax, x + step_w / 2, y + 0.122, wrapped(name, 14), size=9.2, weight="bold", color=PALETTE["ink"], ha="center")
        label(ax, x + step_w / 2, y + 0.05, wrapped(desc, 13), size=7.3, color=PALETTE["ink"], ha="center")
        centers.append((x + step_w / 2, y + 0.085))

    for idx in range(len(centers) - 1):
        arrow(ax, centers[idx][0] + 0.055, centers[idx][1], centers[idx + 1][0] - 0.055, centers[idx + 1][1])

    panel(ax, 0.05, 0.10, 0.37, 0.21, fc="#FFF9EE")
    label(ax, 0.07, 0.27, "RTL Clues", size=12.5, weight="bold", color=PALETTE["navy"])
    clues = [
        f"Instances: {', '.join(info.instances) if info.instances else 'none'}",
        f"Assign statements: {info.assign_count}",
        f"Always blocks: {info.always_count}",
        f"Pipelined: {'yes' if info.is_pipelined else 'no'}",
    ]
    for idx, clue in enumerate(clues):
        label(ax, 0.075, 0.225 - idx * 0.040, wrapped(clue, 34), size=8.8, color=PALETTE["slate"])

    panel(ax, 0.46, 0.10, 0.49, 0.21, fc="#F7FBFF")
    label(ax, 0.48, 0.27, "Design Reading", size=12.5, weight="bold", color=PALETTE["navy"])
    for idx, text in enumerate(bullet_lines(datatype_description(info.module_name, variant), 48)[:7]):
        label(ax, 0.485, 0.225 - idx * 0.030, text, size=8.3, color=PALETTE["slate"])

    dep_names = [dep for dep in info.instances if dep in modules]
    if dep_names:
        panel(ax, 0.66, 0.60, 0.29, 0.08, fc="#F8F0FB")
        label(ax, 0.68, 0.645, "Referenced Modules", size=11, weight="bold", color=PALETTE["navy"])
        label(ax, 0.68, 0.617, wrapped(", ".join(dep_names), 34), size=8.6, color=PALETTE["slate"])

    fig.savefig(output_path, bbox_inches="tight", facecolor="white", pad_inches=0.18)
    plt.close(fig)


def draw_module_card(info: ModuleInfo, output_path: Path) -> None:
    fig, ax = plt.subplots(figsize=(14, 8.0), dpi=220)
    ax.set_axis_off()
    add_gradient_background(ax, "#FFFFFF", "#F3F7FB")
    add_title(ax, f"{info.variant}  •  {info.module_name}", f"Compact module summary for {info.file_path.name}")

    panel(ax, 0.05, 0.67, 0.90, 0.16, fc=PALETTE["navy"], ec=PALETTE["navy"])
    label(ax, 0.07, 0.765, "Module Snapshot", size=13, weight="bold", color=PALETTE["white"])
    summary = [
        f"File: {info.file_path.name}",
        f"Lines: {info.lines}",
        f"Assigns: {info.assign_count}",
        f"Always: {info.always_count}",
        f"localparams: {info.localparam_count}",
        f"Pipeline: {'yes' if info.is_pipelined else 'no'}",
    ]
    for idx, item in enumerate(summary):
        x = 0.07 + (idx % 3) * 0.28
        y = 0.72 - (idx // 3) * 0.05
        label(ax, x, y, wrapped(item, 22), size=8.8, color="#E9F2FA")

    inputs, outputs, bidir = module_port_summary(info)
    panel(ax, 0.05, 0.12, 0.24, 0.46, fc="#FFF9EE")
    panel(ax, 0.38, 0.12, 0.24, 0.46, fc="#EEF7FF")
    panel(ax, 0.71, 0.12, 0.24, 0.46, fc="#F2FBF6")
    label(ax, 0.07, 0.54, "Inputs", size=12.5, weight="bold", color=PALETTE["navy"])
    label(ax, 0.40, 0.54, "Outputs", size=12.5, weight="bold", color=PALETTE["navy"])
    label(ax, 0.73, 0.54, "Structure", size=12.5, weight="bold", color=PALETTE["navy"])

    for idx, item in enumerate(inputs[:6] or ["No explicit inputs parsed"]):
        label(ax, 0.075, 0.49 - idx * 0.057, wrapped(item, 18), size=8.3, color=PALETTE["slate"])
    for idx, item in enumerate(outputs[:6] or ["No explicit outputs parsed"]):
        label(ax, 0.405, 0.49 - idx * 0.057, wrapped(item, 18), size=8.3, color=PALETTE["slate"])

    structure_lines = [
        f"Instances: {', '.join(info.instances[:4]) if info.instances else 'None'}",
        f"Clock/reset: {', '.join(info.clocked_signals[:4]) if info.clocked_signals else 'None'}",
        f"Valid: {', '.join(info.valid_signals[:4]) if info.valid_signals else 'None'}",
    ]
    for idx, item in enumerate(structure_lines):
        label(ax, 0.735, 0.49 - idx * 0.095, wrapped(item, 18), size=8.3, color=PALETTE["slate"])

    center_panel = panel(ax, 0.32, 0.26, 0.36, 0.18, fc="#FFFFFF", ec=PALETTE["cyan"])
    label(ax, 0.50, 0.35, info.module_name, size=15, weight="bold", color=PALETTE["navy"], ha="center")
    label(ax, 0.50, 0.30, "RTL abstraction node", size=10, color=PALETTE["slate"], ha="center")
    arrow(ax, 0.29, 0.35, 0.32, 0.35)
    arrow(ax, 0.68, 0.35, 0.62, 0.35)

    fig.savefig(output_path, bbox_inches="tight", facecolor="white", pad_inches=0.18)
    plt.close(fig)


def generate_yosys_schematic(info: ModuleInfo, output_path: Path) -> bool:
    """Run yosys to create a schematic PNG for a module, if yosys is available."""
    if not YOSYS_BIN:
        return False
    output_path.parent.mkdir(parents=True, exist_ok=True)
    prefix = output_path.with_suffix("")
    script = "\n".join(
        [
            f"read_verilog {info.file_path}",
            f"hierarchy -top {info.module_name}",
            # light processing, keep hierarchy for high-level view
            "proc; opt; fsm; opt; clean",
            f"show -format png -prefix {prefix} -colors 1 -notitle",
        ]
    )
    try:
        subprocess.run([YOSYS_BIN, "-q", "-p", script], check=True, cwd=BASE_DIR)
        return output_path.exists()
    except subprocess.CalledProcessError:
        return False


def generate_html_report(modules_by_variant: Dict[str, Dict[str, ModuleInfo]]) -> Path:
    report_path = REPORT_DIR / "index.html"

    sections = []
    for variant in RTL_VARIANTS:
        overview_name = f"{variant}_overview.png"
        block_cards = []
        datatype_cards = []
        for module_name in DATATYPE_MODULES:
            if module_name in modules_by_variant[variant]:
                rel = f"../block/{variant}/{module_name}.png"
                block_cards.append(
                    f"""
                    <div class="card">
                        <img src="{rel}" alt="{variant} {module_name} block diagram">
                        <div class="caption">{variant} • {module_name} • block</div>
                    </div>
                    """
                )
        for module_name in DATATYPE_MODULES:
            if module_name in modules_by_variant[variant]:
                rel = f"../flow/{variant}/{module_name}.png"
                datatype_cards.append(
                    f"""
                    <div class="card">
                        <img src="{rel}" alt="{variant} {module_name}">
                        <div class="caption">{variant} • {module_name}</div>
                    </div>
                    """
                )
        sections.append(
            f"""
            <section class="section">
                <h2>{variant}</h2>
                <div class="hero">
                    <img src="../overview/{overview_name}" alt="{variant} overview">
                </div>
                <h3>Block-Level Diagrams</h3>
                <div class="gallery">
                    {''.join(block_cards)}
                </div>
                <h3>Flow Diagrams</h3>
                <div class="gallery">
                    {''.join(datatype_cards)}
                </div>
            </section>
            """
        )

    html_text = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Approx-T RTL Visualization Atlas</title>
  <style>
    body {{
      margin: 0;
      font-family: "Segoe UI", Arial, sans-serif;
      background: linear-gradient(180deg, #eef4f9 0%, #ffffff 100%);
      color: #1d1f23;
    }}
    .wrap {{
      max-width: 1360px;
      margin: 0 auto;
      padding: 32px 24px 64px;
    }}
    h1 {{
      font-size: 2.3rem;
      margin-bottom: 8px;
      color: #14324B;
    }}
    .sub {{
      color: #4A5A6A;
      margin-bottom: 28px;
      line-height: 1.6;
    }}
    .section {{
      background: white;
      border-radius: 18px;
      padding: 24px;
      box-shadow: 0 12px 36px rgba(20, 50, 75, 0.10);
      margin-bottom: 26px;
    }}
    h2 {{
      color: #1D5D9B;
      margin-top: 0;
    }}
    .hero img {{
      width: 100%;
      border-radius: 12px;
      border: 1px solid #d6e0e8;
    }}
    .gallery {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(340px, 1fr));
      gap: 18px;
      margin-top: 18px;
    }}
    .card {{
      background: #f9fbfd;
      border: 1px solid #d6e0e8;
      border-radius: 14px;
      overflow: hidden;
    }}
    .card img {{
      width: 100%;
      display: block;
    }}
    .caption {{
      padding: 12px 14px;
      font-weight: 600;
      color: #14324B;
    }}
    code {{
      background: #eef4f9;
      padding: 2px 6px;
      border-radius: 6px;
    }}
  </style>
</head>
<body>
  <div class="wrap">
    <h1>Approx-T RTL Visuals</h1>
    <div class="sub">
      High-level, presentation-ready RTL diagrams generated from the Verilog source in
      <code>RTL</code>, <code>RTL_proposed</code>, and <code>RTL_proposed_2</code>.
      These figures are architectural interpretations rather than synthesis netlists.
      Generated from the current RTL source tree.
    </div>
    {''.join(sections)}
  </div>
</body>
</html>
"""
    report_path.write_text(html_text, encoding="utf-8")
    return report_path


def generate_all() -> None:
    ensure_dirs()
    set_ieee_style()
    modules_by_variant = discover_modules()

    print("=" * 88)
    print("Approx-T RTL Visuals")
    print("=" * 88)
    print(f"Output folder: {OUTPUT_ROOT}")
    print()

    for variant, modules in modules_by_variant.items():
        print(f"[{variant}] generating overview poster")
        draw_overview_poster(variant, modules, OVERVIEW_DIR / f"{variant}_overview.png")

        print(f"[{variant}] generating block diagrams")
        for module_name in BLOCK_MODULES:
            info = modules.get(module_name)
            if not info:
                continue
            draw_block_diagram(
                variant,
                info,
                BLOCK_DIR / variant / f"{module_name}.png",
            )

        print(f"[{variant}] generating datatype flowcharts")
        for module_name in DATATYPE_MODULES:
            info = modules.get(module_name)
            if not info:
                continue
            draw_datatype_flowchart(
                variant,
                info,
                modules,
                DATATYPE_DIR / variant / f"{module_name}.png",
            )

        print(f"[{variant}] generating module cards")
        for module_name, info in sorted(modules.items()):
            draw_module_card(info, MODULE_DIR / variant / f"{module_name}.png")

        if YOSYS_BIN:
            print(f"[{variant}] generating yosys schematics")
            for module_name, info in sorted(modules.items()):
                generate_yosys_schematic(info, YOSYS_DIR / variant / f"{module_name}.png")
        else:
            print(f"[{variant}] skipping yosys (not installed)")

    report_path = generate_html_report(modules_by_variant)

    print()
    print("Generated assets:")
    print(f"  - Block diagrams: {BLOCK_DIR}")
    print(f"  - Overview posters: {OVERVIEW_DIR}")
    print(f"  - Datatype flowcharts: {DATATYPE_DIR}")
    print(f"  - Module cards: {MODULE_DIR}")
    print(f"  - HTML gallery: {report_path}")
    print()
    print("Done.")


if __name__ == "__main__":
    generate_all()
