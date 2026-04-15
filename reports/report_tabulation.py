#!/usr/bin/env python3
"""
Generate a single segmented CSV from Cadence synthesis reports.

This script scans the report folders dynamically, extracts metrics from the
stage-specific report set (default: opt), and writes one CSV file containing:
1. An "all designs" table
2. Separate tables for each multiplier family

Design label mapping:
  p_0 -> [1]
  p_1 -> p1
  p_2 -> p2
"""

from __future__ import annotations

import argparse
import csv
import os
import re
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

os.environ.setdefault("MPLCONFIGDIR", "/tmp/matplotlib")

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


REPORT_NAME_RE = re.compile(
    r"^(?P<family>unsigned_int|signed_int|fixed_point|floating_point)"
    r"_mul_(?P<design>p_\d+)_(?P<level>L\d+)$"
)

TOP_AREA_RE = re.compile(
    r"^\s*(?P<module>\S+)\s+"
    r"(?P<cell_count>[\d,]+)\s+"
    r"(?P<cell_area>[\d,]+(?:\.\d+)?)\s+"
    r"(?P<net_area>[\d,]+(?:\.\d+)?)\s+"
    r"(?P<total_area>[\d,]+(?:\.\d+)?)\s*$"
)

SUBTOTAL_POWER_RE = re.compile(
    r"^\s*Subtotal\s+"
    r"(?P<leakage>[+-]?\d+(?:\.\d+)?e[+-]?\d+|[+-]?\d+(?:\.\d+)?)\s+"
    r"(?P<internal>[+-]?\d+(?:\.\d+)?e[+-]?\d+|[+-]?\d+(?:\.\d+)?)\s+"
    r"(?P<switching>[+-]?\d+(?:\.\d+)?e[+-]?\d+|[+-]?\d+(?:\.\d+)?)\s+"
    r"(?P<total>[+-]?\d+(?:\.\d+)?e[+-]?\d+|[+-]?\d+(?:\.\d+)?)"
)

FINAL_VALUE_RE = re.compile(r"([+-]?[\d,]+(?:\.\d+)?)")
PATH_HEADER_RE = re.compile(
    r"^Path\s+1:\s+(?P<status>\S+)\s+\((?P<slack>[+-]?\d+)\s+ps\)"
)
DATA_PATH_RE = re.compile(r"^\s*Data Path:-\s*(?P<data_path>[+-]?\d+)")


FAMILY_LABELS = {
    "unsigned_int": "Unsigned Integer",
    "signed_int": "Signed Integer",
    "fixed_point": "Fixed Point",
    "floating_point": "Floating Point",
}

DESIGN_LABELS = {
    "p_0": "[1]",
    "p_1": "p1",
    "p_2": "p2",
}

DESIGN_SORT_ORDER = {
    "p_0": 0,
    "p_1": 1,
    "p_2": 2,
}

DESIGN_COLORS = {
    "[1]": "#1f77b4",
    "p1": "#d62728",
    "p2": "#2ca02c",
}

POWER_PLOT_SPECS = [
    ("leakage_power_w", "Leakage Power", "power_leakage_by_family"),
    ("switching_power_w", "Switching Power", "power_switching_by_family"),
    ("total_power_w", "Total Power", "power_total_by_family"),
]

REFERENCE_FREQUENCY_GHZ = 1.0
REFERENCE_PERIOD_PS = 1000.0

CSV_COLUMNS = [
    ("family", "Family", "-"),
    ("module_name", "Module Name", "-"),
    ("level", "Level", "-"),
    ("design_raw", "Design Raw", "-"),
    ("design_label", "Design Label", "-"),
    ("stage", "Stage", "-"),
    ("area_total", "Total Area", "um^2"),
    ("cell_area", "Cell Area", "um^2"),
    ("net_area", "Net Area", "um^2"),
    ("cell_count", "Cell Count", "count"),
    ("leaf_instances", "Leaf Instances", "count"),
    ("total_instances", "Total Instances", "count"),
    ("leakage_power_w", "Leakage Power", "W"),
    ("internal_power_w", "Internal Power", "W"),
    ("switching_power_w", "Switching Power", "W"),
    ("total_power_w", "Total Power", "W"),
    ("slack_ps", "Slack", "ps"),
    ("path_delay_ps", "Path Delay", "ps"),
    ("operational_frequency_ghz", "Operational Frequency", "GHz"),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract area, power, timing, and instance metrics into one CSV."
    )
    parser.add_argument(
        "--reports-root",
        type=Path,
        default=Path(__file__).resolve().parent,
        help="Root directory that contains synthesis report folders.",
    )
    parser.add_argument(
        "--stage",
        default="opt",
        help="Report stage to parse. Default: opt",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parent / "multiplier_report_tabulation.csv",
        help="Output CSV path.",
    )
    parser.add_argument(
        "--plot-dir",
        type=Path,
        default=Path(__file__).resolve().parent / "plots",
        help="Directory for generated power plots.",
    )
    return parser.parse_args()


def parse_number(value: str) -> float:
    return float(value.replace(",", ""))


def parse_int(value: str) -> int:
    return int(float(value.replace(",", "")))


def extract_last_value(line: str) -> Optional[str]:
    matches = FINAL_VALUE_RE.findall(line)
    return matches[-1] if matches else None


def parse_area_report(area_path: Path, expected_module: str) -> Dict[str, float]:
    for line in area_path.read_text().splitlines():
        match = TOP_AREA_RE.match(line)
        if match and match.group("module") == expected_module:
            return {
                "cell_count": parse_int(match.group("cell_count")),
                "cell_area": parse_number(match.group("cell_area")),
                "net_area": parse_number(match.group("net_area")),
                "area_total": parse_number(match.group("total_area")),
            }
    raise ValueError(f"Top-level area row not found in {area_path}")


def parse_power_report(power_path: Path) -> Dict[str, float]:
    for line in power_path.read_text().splitlines():
        match = SUBTOTAL_POWER_RE.match(line)
        if match:
            return {
                "leakage_power_w": float(match.group("leakage")),
                "internal_power_w": float(match.group("internal")),
                "switching_power_w": float(match.group("switching")),
                "total_power_w": float(match.group("total")),
            }
    raise ValueError(f"Subtotal power row not found in {power_path}")


def parse_time_report(time_path: Path) -> Dict[str, int]:
    slack_ps: Optional[int] = None
    path_delay_ps: Optional[int] = None

    for line in time_path.read_text().splitlines():
        if slack_ps is None:
            path_match = PATH_HEADER_RE.match(line)
            if path_match:
                slack_ps = int(path_match.group("slack"))
                continue

        if path_delay_ps is None:
            data_path_match = DATA_PATH_RE.match(line)
            if data_path_match:
                path_delay_ps = int(data_path_match.group("data_path"))
                if slack_ps is not None:
                    break

    if slack_ps is None:
        raise ValueError(f"Path 1 slack not found in {time_path}")
    if path_delay_ps is None:
        raise ValueError(f"Path 1 data path not found in {time_path}")

    return {
        "slack_ps": slack_ps,
        "path_delay_ps": path_delay_ps,
    }


def calculate_operational_frequency_ghz(slack_ps: int) -> float:
    """
    Derive the achievable operating frequency using 1 GHz / 1 ns as the reference.

    If slack is zero or positive, timing meets the 1 GHz target and we keep the
    operational frequency at 1.0 GHz.

    If slack is negative, the required clock period increases by |slack|:
      actual_period_ps = reference_period_ps - slack_ps
    since slack_ps is negative in that case.
    """
    if slack_ps >= 0:
        return REFERENCE_FREQUENCY_GHZ

    actual_period_ps = REFERENCE_PERIOD_PS - float(slack_ps)
    if actual_period_ps <= 0:
        raise ValueError(f"Invalid derived clock period for slack {slack_ps} ps")

    return REFERENCE_PERIOD_PS / actual_period_ps


def parse_final_report(final_path: Path) -> Dict[str, int]:
    leaf_instances: Optional[int] = None
    total_instances: Optional[int] = None

    for line in final_path.read_text().splitlines():
        if "Leaf Instances:" in line:
            value = extract_last_value(line)
            if value is not None:
                leaf_instances = parse_int(value)
        elif "Total Instances:" in line:
            value = extract_last_value(line)
            if value is not None:
                total_instances = parse_int(value)

    if leaf_instances is None or total_instances is None:
        raise ValueError(f"Instance counts not found in {final_path}")

    return {
        "leaf_instances": leaf_instances,
        "total_instances": total_instances,
    }


def find_report_set(base_dir: Path, stage: str, module_name: str) -> Tuple[Path, Path, Path, Path]:
    stage_dir = base_dir / "cadence_45nm" / stage
    if not stage_dir.is_dir():
        raise FileNotFoundError(f"Stage directory not found: {stage_dir}")

    area_path = stage_dir / f"{module_name}_syn_{stage}_area.rpt"
    power_path = stage_dir / f"{module_name}_syn_{stage}_power.rpt"
    time_path = stage_dir / f"{module_name}_syn_{stage}_time.rpt"
    final_path = stage_dir / "final.rpt"

    for path in (area_path, power_path, time_path, final_path):
        if not path.exists():
            raise FileNotFoundError(f"Missing report file: {path}")

    return area_path, power_path, time_path, final_path


def collect_rows(reports_root: Path, stage: str) -> List[Dict[str, object]]:
    rows: List[Dict[str, object]] = []

    for module_dir in sorted(path for path in reports_root.iterdir() if path.is_dir()):
        match = REPORT_NAME_RE.match(module_dir.name)
        if not match:
            continue

        module_name = module_dir.name
        area_path, power_path, time_path, final_path = find_report_set(
            module_dir, stage, module_name
        )

        row: Dict[str, object] = {
            "family": FAMILY_LABELS[match.group("family")],
            "module_name": module_name,
            "level": match.group("level"),
            "design_raw": match.group("design"),
            "design_label": DESIGN_LABELS.get(match.group("design"), match.group("design")),
            "stage": stage,
        }
        row.update(parse_area_report(area_path, module_name))
        row.update(parse_final_report(final_path))
        row.update(parse_power_report(power_path))
        row.update(parse_time_report(time_path))
        row["operational_frequency_ghz"] = calculate_operational_frequency_ghz(
            int(row["slack_ps"])
        )
        rows.append(row)

    rows.sort(
        key=lambda row: (
            row["family"],
            int(str(row["level"]).lstrip("L")),
            DESIGN_SORT_ORDER.get(str(row["design_raw"]), 99),
        )
    )
    return rows


def write_segmented_csv(output_path: Path, rows: Iterable[Dict[str, object]]) -> None:
    rows = list(rows)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    csv_headers = [header for _, header, _ in CSV_COLUMNS]
    csv_units = [unit for _, _, unit in CSV_COLUMNS]
    csv_keys = [key for key, _, _ in CSV_COLUMNS]

    with output_path.open("w", newline="") as handle:
        writer = csv.writer(handle)

        writer.writerow(["All Designs"])
        writer.writerow(csv_headers)
        writer.writerow(csv_units)
        for row in rows:
            writer.writerow([row.get(key, "") for key in csv_keys])

        for family in FAMILY_LABELS.values():
            family_rows = [row for row in rows if row["family"] == family]
            if not family_rows:
                continue

            writer.writerow([])
            writer.writerow([family])
            writer.writerow(csv_headers)
            writer.writerow(csv_units)
            for row in family_rows:
                writer.writerow([row.get(key, "") for key in csv_keys])


def apply_publication_style() -> None:
    plt.rcParams.update(
        {
            "font.family": "serif",
            "font.serif": ["Times New Roman", "Times", "DejaVu Serif"],
            "font.size": 9,
            "axes.labelsize": 9,
            "axes.titlesize": 10,
            "legend.fontsize": 8,
            "xtick.labelsize": 8,
            "ytick.labelsize": 8,
            "axes.linewidth": 0.8,
            "grid.linewidth": 0.5,
            "grid.alpha": 0.25,
            "savefig.bbox": "tight",
            "savefig.pad_inches": 0.03,
        }
    )


def level_key(level: str) -> int:
    return int(level.lstrip("L"))


def watts_to_mw(value: float) -> float:
    return value * 1e3


def group_rows_by_family(rows: Iterable[Dict[str, object]]) -> Dict[str, List[Dict[str, object]]]:
    grouped: Dict[str, List[Dict[str, object]]] = {family: [] for family in FAMILY_LABELS.values()}
    for row in rows:
        grouped[str(row["family"])].append(row)
    for family_rows in grouped.values():
        family_rows.sort(
            key=lambda row: (level_key(str(row["level"])), DESIGN_SORT_ORDER.get(str(row["design_raw"]), 99))
        )
    return grouped


def save_figure(fig: plt.Figure, output_stem: Path) -> None:
    fig.savefig(output_stem.with_suffix(".pdf"))
    fig.savefig(output_stem.with_suffix(".png"), dpi=400)
    plt.close(fig)


def clean_plot_dir(plot_dir: Path) -> None:
    expected_stems = {file_stem for _, _, file_stem in POWER_PLOT_SPECS}
    for path in plot_dir.glob("*"):
        if not path.is_file():
            continue
        if path.suffix.lower() not in {".pdf", ".png"}:
            continue
        if path.stem not in expected_stems:
            path.unlink()


def plot_power_metric(
    rows: List[Dict[str, object]],
    plot_dir: Path,
    metric_key: str,
    metric_title: str,
    file_stem: str,
) -> None:
    grouped = group_rows_by_family(rows)
    fig, axes = plt.subplots(2, 2, figsize=(7.2, 5.0), sharex=False, sharey=False)
    axes_flat = list(axes.flat)

    for ax, family in zip(axes_flat, FAMILY_LABELS.values()):
        family_rows = grouped[family]
        if not family_rows:
            ax.axis("off")
            continue

        design_rows: Dict[str, List[Dict[str, object]]] = {}
        for row in family_rows:
            design_rows.setdefault(str(row["design_label"]), []).append(row)

        for design_label in ("[1]", "p1", "p2"):
            rows_for_design = sorted(design_rows.get(design_label, []), key=lambda row: level_key(str(row["level"])))
            if not rows_for_design:
                continue
            x_vals = [level_key(str(row["level"])) for row in rows_for_design]
            y_vals = [watts_to_mw(float(row[metric_key])) for row in rows_for_design]
            ax.plot(
                x_vals,
                y_vals,
                marker="o",
                markersize=4,
                linewidth=1.7,
                color=DESIGN_COLORS[design_label],
                label=design_label,
            )

        ax.set_title(family)
        ax.set_xlabel("Approximation Level")
        ax.set_ylabel(f"{metric_title} (mW)")
        ax.set_xticks(sorted({level_key(str(row["level"])) for row in family_rows}))
        ax.grid(True, axis="y")
        ax.spines["top"].set_visible(False)
        ax.spines["right"].set_visible(False)

    handles, labels = axes_flat[0].get_legend_handles_labels()
    if handles:
        fig.legend(handles, labels, loc="upper center", ncol=3, frameon=False, bbox_to_anchor=(0.5, 1.02))
    fig.suptitle(f"{metric_title} Across Multiplier Families", y=1.06, fontsize=10)
    fig.tight_layout()
    save_figure(fig, plot_dir / file_stem)


def generate_power_plots(rows: List[Dict[str, object]], plot_dir: Path) -> None:
    plot_dir.mkdir(parents=True, exist_ok=True)
    clean_plot_dir(plot_dir)
    apply_publication_style()
    for metric_key, metric_title, file_stem in POWER_PLOT_SPECS:
        plot_power_metric(rows, plot_dir, metric_key, metric_title, file_stem)


def main() -> None:
    args = parse_args()
    rows = collect_rows(args.reports_root, args.stage)
    if not rows:
        raise SystemExit(f"No matching reports found under {args.reports_root}")
    write_segmented_csv(args.output, rows)
    generate_power_plots(rows, args.plot_dir)
    print(f"Wrote {len(rows)} rows to {args.output}")
    print(f"Generated plots in {args.plot_dir}")


if __name__ == "__main__":
    main()
