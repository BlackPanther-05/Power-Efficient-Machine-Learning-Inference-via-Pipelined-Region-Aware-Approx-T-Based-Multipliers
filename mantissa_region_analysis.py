#!/usr/bin/env python3
"""
Mantissa Multiplication Region Analysis for Approx-T Modules.
Analyzes [1,2) * [1,2) regions for all precision levels and emits
variant-specific reports for RTL_proposed and RTL_proposed_2.
Date: 2024
"""

import shutil

import matplotlib.pyplot as plt
import numpy as np
import sympy as sp

plt.rcParams.update({
    'axes.titlesize': 11,
    'axes.labelsize': 11,
    'xtick.labelsize': 10,
    'ytick.labelsize': 10,
    'figure.facecolor': 'white',
    'axes.facecolor': '#fcfcfd',
    'savefig.facecolor': 'white',
    'savefig.bbox': 'tight',
    'savefig.pad_inches': 0.06,
    'grid.alpha': 0.22,
})

# Define symbolic variables
x_sym, y_sym = sp.symbols('x y', real=True)

# Approximation formulas for each level
# These correspond to the current delta_f functions in RTL_proposed/approx_t.v
# and RTL_proposed_2/approx_t.v. RTL_proposed_2 adds pipelining and per-region
# enable/config selection, but the underlying regional approximation equations
# are unchanged.


def approx_l0(x, y):
    """
    L0: Four-region first-order Taylor approximation.
    Each region uses its own center:
      (1.25, 1.25), (1.25, 1.75), (1.75, 1.25), (1.75, 1.75)
    """
    result = np.zeros_like(x, dtype=float)
    x_high = x >= 1.5
    y_high = y >= 1.5

    mask = (~x_high) & (~y_high)
    result[mask] = 1.25 * x[mask] + 1.25 * y[mask] - 1.25 * 1.25

    mask = (~x_high) & y_high
    result[mask] = 1.75 * x[mask] + 1.25 * y[mask] - 1.25 * 1.75

    mask = x_high & (~y_high)
    result[mask] = 1.25 * x[mask] + 1.75 * y[mask] - 1.75 * 1.25

    mask = x_high & y_high
    result[mask] = 1.75 * x[mask] + 1.75 * y[mask] - 1.75 * 1.75

    return result


def approx_l1(x, y):
    """
    L1: L0 plus region-local compensation.
    The coarse region is split along x at quarter points, and the
    correction is +/- (y - b0) / 8 based on x's quarter-region.
    """
    base = approx_l0(x, y)
    delta_f1 = np.zeros_like(x, dtype=float)

    b0 = np.where(y >= 1.5, 1.75, 1.25)

    positive_mask = ((x >= 1.25) & (x < 1.5)) | (x >= 1.75)
    delta_f1[positive_mask] = (y[positive_mask] - b0[positive_mask]) / 8.0
    delta_f1[~positive_mask] = -(y[~positive_mask] - b0[~positive_mask]) / 8.0

    return base + delta_f1


def approx_l2(x, y):
    """
    L2: L1 plus second region-local compensation.
    After the x-local split, each subregion is refined along y and the
    correction is +/- (x - a1) / 8 based on y's quarter-region.
    """
    base = approx_l1(x, y)
    delta_f2 = np.zeros_like(x, dtype=float)

    a1 = np.select(
        [x < 1.25, x < 1.5, x < 1.75],
        [1.125, 1.375, 1.625],
        default=1.875,
    )

    positive_mask = ((y >= 1.25) & (y < 1.5)) | (y >= 1.75)
    delta_f2[positive_mask] = (x[positive_mask] - a1[positive_mask]) / 8.0
    delta_f2[~positive_mask] = -(x[~positive_mask] - a1[~positive_mask]) / 8.0

    return base + delta_f2


class MantissaRegionAnalyzer:
    """Analyzes mantissa multiplication regions for different approximation levels."""

    def __init__(self, variant='RTL_proposed', resolution=50):
        self.variant = variant
        self.resolution = resolution
        self.x_range = np.linspace(1.0, 1.99999, resolution)
        self.y_range = np.linspace(1.0, 1.99999, resolution)
        self.X, self.Y = np.meshgrid(self.x_range, self.y_range)
        self.output_prefix = f"mantissa_{self.variant.lower()}"

        self.results = {}
        self.variant_notes = {
            'RTL_proposed': (
                'Combinational four-region Approx-T with shared configurable '
                'precision mask.'
            ),
            'RTL_proposed_2': (
                'Pipelined four-region Approx-T with per-region enable and '
                'per-region configuration mask selection.'
            ),
        }

        self.region_boundaries = {
            'L0': {
                'teps': [(1.25, 1.25), (1.25, 1.75), (1.75, 1.25), (1.75, 1.75)],
                'x_dividers': [1.5],
                'y_dividers': [1.5],
                'regions': 4,
                'description': '4 TEPs at region centers: (1.25,1.25), (1.25,1.75), (1.75,1.25), (1.75,1.75)',
            },
            'L1': {
                'teps': [(1.25, 1.25), (1.25, 1.75), (1.75, 1.25), (1.75, 1.75)],
                'x_dividers': [1.25, 1.5, 1.75],
                'y_dividers': [1.5],
                'regions': 8,
                'description': 'L0 + delta_f1: 8 regions, x-local sign, y-offset correction',
            },
            'L2': {
                'teps': [(1.25, 1.25), (1.25, 1.75), (1.75, 1.25), (1.75, 1.75)],
                'x_dividers': [1.25, 1.5, 1.75],
                'y_dividers': [1.25, 1.5, 1.75],
                'regions': 16,
                'description': 'L1 + delta_f2: 16 regions, y-local sign, x-offset correction',
            },
        }

    def compute_regions(self):
        """Compute output regions for all approximation levels."""
        self.results['Exact'] = self.exact_multiply(self.X, self.Y)

        for level, approx_fn in [('L0', self.approx_l0), ('L1', self.approx_l1), ('L2', self.approx_l2)]:
            self.results[level] = approx_fn(self.X, self.Y)
            self.results[f'{level}_error'] = np.abs(self.results[level] - self.results['Exact'])
            self.results[f'{level}_rel_error'] = (
                np.abs(
                    self.results[f'{level}_error']
                    / np.where(self.results['Exact'] != 0, self.results['Exact'], 1e-10)
                )
                * 100
            )

    def exact_multiply(self, x, y):
        return x * y

    def _style_axes(self, ax, xlabel, ylabel, is_3d=False):
        ax.set_xlabel(xlabel, fontsize=11, fontweight='semibold', labelpad=8)
        ax.set_ylabel(ylabel, fontsize=11, fontweight='semibold', labelpad=8)
        if is_3d:
            ax.zaxis.label.set_size(11)
            ax.zaxis.label.set_fontweight('semibold')
            ax.tick_params(axis='z', labelsize=9, pad=2)
        ax.tick_params(labelsize=9)
        ax.grid(True, alpha=0.18, linestyle=':')

    def _save_figure(self, fig, output_path):
        fig.savefig(output_path, dpi=450, bbox_inches='tight', pad_inches=0.05)
        print(f"✓ Plot saved as '{output_path}'")
        plt.close(fig)

    def approx_l0(self, x, y):
        return approx_l0(x, y)

    def approx_l1(self, x, y):
        return approx_l1(x, y)

    def approx_l2(self, x, y):
        return approx_l2(x, y)

    def print_statistics(self):
        print("\n" + "=" * 80)
        print(f"MANTISSA MULTIPLICATION REGION ANALYSIS - {self.variant} Approx-T")
        print("=" * 80 + "\n")
        print(f"Variant note: {self.variant_notes.get(self.variant, 'Shared Approx-T formulation.')}\n")

        print("Input Range: [1.0, 2.0) × [1.0, 2.0)")
        print("Output Range: [1.0, 4.0) (Exact)")
        print(f"Resolution: {self.resolution}×{self.resolution} points\n")

        print("-" * 80)
        print("EXACT MULTIPLICATION STATISTICS:")
        print("-" * 80)
        print(f"Min Output: {np.min(self.results['Exact']):.6f}")
        print(f"Max Output: {np.max(self.results['Exact']):.6f}")
        print(f"Mean Output: {np.mean(self.results['Exact']):.6f}\n")

        for level in ['L0', 'L1', 'L2']:
            print("-" * 80)
            print(f"{level} - APPROXIMATION STATISTICS:")
            print("-" * 80)
            print(f"Min Output:                {np.min(self.results[level]):.6f}")
            print(f"Max Output:                {np.max(self.results[level]):.6f}")
            print(f"Mean Output:               {np.mean(self.results[level]):.6f}")
            print("\nError Statistics:")
            print(f"  Min Absolute Error:      {np.min(self.results[f'{level}_error']):.8f}")
            print(f"  Max Absolute Error:      {np.max(self.results[f'{level}_error']):.8f}")
            print(f"  Mean Absolute Error:     {np.mean(self.results[f'{level}_error']):.8f}")
            print(f"  Min Relative Error (%):  {np.min(self.results[f'{level}_rel_error']):.6f}")
            print(f"  Max Relative Error (%):  {np.max(self.results[f'{level}_rel_error']):.6f}")
            print(f"  Mean Relative Error (%): {np.mean(self.results[f'{level}_rel_error']):.6f}")
            print()

    def plot_regions(self):
        fig = plt.figure(figsize=(21, 15), constrained_layout=True)

        ax1 = fig.add_subplot(3, 4, 1, projection='3d')
        surf1 = ax1.plot_surface(self.X, self.Y, self.results['Exact'], cmap='viridis', alpha=0.8)
        self._style_axes(ax1, 'x', 'y', is_3d=True)
        ax1.set_zlabel('f(x,y)')
        ax1.set_zlim([1, 4])
        fig.colorbar(surf1, ax=ax1, shrink=0.58, pad=0.02, fraction=0.05)

        ax2 = fig.add_subplot(3, 4, 2, projection='3d')
        surf2 = ax2.plot_surface(self.X, self.Y, self.results['L0'], cmap='viridis', alpha=0.8)
        self._style_axes(ax2, 'x', 'y', is_3d=True)
        ax2.set_zlabel('f(x,y)')
        ax2.set_zlim([1, 4])
        fig.colorbar(surf2, ax=ax2, shrink=0.58, pad=0.02, fraction=0.05)

        ax3 = fig.add_subplot(3, 4, 3, projection='3d')
        surf3 = ax3.plot_surface(self.X, self.Y, self.results['L1'], cmap='viridis', alpha=0.8)
        self._style_axes(ax3, 'x', 'y', is_3d=True)
        ax3.set_zlabel('f(x,y)')
        ax3.set_zlim([1, 4])
        fig.colorbar(surf3, ax=ax3, shrink=0.58, pad=0.02, fraction=0.05)

        ax4 = fig.add_subplot(3, 4, 4, projection='3d')
        surf4 = ax4.plot_surface(self.X, self.Y, self.results['L2'], cmap='viridis', alpha=0.8)
        self._style_axes(ax4, 'x', 'y', is_3d=True)
        ax4.set_zlabel('f(x,y)')
        ax4.set_zlim([1, 4])
        fig.colorbar(surf4, ax=ax4, shrink=0.58, pad=0.02, fraction=0.05)

        ax5 = fig.add_subplot(3, 4, 5, projection='3d')
        surf5 = ax5.plot_surface(self.X, self.Y, self.results['L0_error'], cmap='hot', alpha=0.8)
        self._style_axes(ax5, 'x', 'y', is_3d=True)
        ax5.set_zlabel('Absolute Error')
        fig.colorbar(surf5, ax=ax5, shrink=0.58, pad=0.02, fraction=0.05)

        ax6 = fig.add_subplot(3, 4, 6, projection='3d')
        surf6 = ax6.plot_surface(self.X, self.Y, self.results['L1_error'], cmap='hot', alpha=0.8)
        self._style_axes(ax6, 'x', 'y', is_3d=True)
        ax6.set_zlabel('Absolute Error')
        fig.colorbar(surf6, ax=ax6, shrink=0.58, pad=0.02, fraction=0.05)

        ax7 = fig.add_subplot(3, 4, 7, projection='3d')
        surf7 = ax7.plot_surface(self.X, self.Y, self.results['L2_error'], cmap='hot', alpha=0.8)
        self._style_axes(ax7, 'x', 'y', is_3d=True)
        ax7.set_zlabel('Absolute Error')
        fig.colorbar(surf7, ax=ax7, shrink=0.58, pad=0.02, fraction=0.05)

        ax8 = fig.add_subplot(3, 4, 8, projection='3d')
        error_diff = self.results['L0_error'] - self.results['L1_error']
        surf8 = ax8.plot_surface(self.X, self.Y, error_diff, cmap='RdBu_r', alpha=0.8)
        self._style_axes(ax8, 'x', 'y', is_3d=True)
        ax8.set_zlabel('Error Reduction')
        fig.colorbar(surf8, ax=ax8, shrink=0.58, pad=0.02, fraction=0.05)

        ax9 = fig.add_subplot(3, 4, 9)
        im9 = ax9.contourf(self.X, self.Y, self.results['L0_rel_error'], levels=20, cmap='hot')
        self._style_axes(ax9, 'x', 'y')
        fig.colorbar(im9, ax=ax9, pad=0.02, fraction=0.05)

        ax10 = fig.add_subplot(3, 4, 10)
        im10 = ax10.contourf(self.X, self.Y, self.results['L1_rel_error'], levels=20, cmap='hot')
        self._style_axes(ax10, 'x', 'y')
        fig.colorbar(im10, ax=ax10, pad=0.02, fraction=0.05)

        ax11 = fig.add_subplot(3, 4, 11)
        im11 = ax11.contourf(self.X, self.Y, self.results['L2_rel_error'], levels=20, cmap='hot')
        self._style_axes(ax11, 'x', 'y')
        fig.colorbar(im11, ax=ax11, pad=0.02, fraction=0.05)

        ax12 = fig.add_subplot(3, 4, 12)
        slice_y = 1.5
        idx = np.argmin(np.abs(self.y_range - slice_y))
        ax12.plot(self.x_range, self.results['Exact'][idx, :], 'k-', linewidth=2.5, label='Exact')
        ax12.plot(self.x_range, self.results['L0'][idx, :], 'r--', linewidth=2, label='L0')
        ax12.plot(self.x_range, self.results['L1'][idx, :], 'g--', linewidth=2, label='L1')
        ax12.plot(self.x_range, self.results['L2'][idx, :], 'b--', linewidth=2, label='L2')
        self._style_axes(ax12, 'x', 'f(x, 1.5)')
        ax12.legend(loc='upper left', fontsize=8, framealpha=0.9, ncol=2)
        ax12.grid(True, alpha=0.3)

        output_path = f'{self.output_prefix}_regions_analysis.png'
        self._save_figure(fig, output_path)

    def plot_contour_comparison(self):
        fig, axes = plt.subplots(2, 2, figsize=(17, 13), constrained_layout=True)

        ax = axes[0, 0]
        contour = ax.contourf(self.X, self.Y, self.results['Exact'], levels=15, cmap='viridis')
        ax.contour(self.X, self.Y, self.results['Exact'], levels=15, colors='black', alpha=0.3, linewidths=0.5)
        self._style_axes(ax, 'x (input mantissa)', 'y (input mantissa)')
        ax.set_aspect('equal')
        plt.colorbar(contour, ax=ax, label='Output', pad=0.02, fraction=0.046)

        ax = axes[0, 1]
        contour = ax.contourf(self.X, self.Y, self.results['L0'], levels=15, cmap='viridis')
        ax.contour(self.X, self.Y, self.results['L0'], levels=15, colors='black', alpha=0.3, linewidths=0.5)
        self._style_axes(ax, 'x (input mantissa)', 'y (input mantissa)')
        ax.set_aspect('equal')
        plt.colorbar(contour, ax=ax, label='Output', pad=0.02, fraction=0.046)

        ax = axes[1, 0]
        contour = ax.contourf(self.X, self.Y, self.results['L1'], levels=15, cmap='viridis')
        ax.contour(self.X, self.Y, self.results['L1'], levels=15, colors='black', alpha=0.3, linewidths=0.5)
        self._style_axes(ax, 'x (input mantissa)', 'y (input mantissa)')
        ax.set_aspect('equal')
        plt.colorbar(contour, ax=ax, label='Output', pad=0.02, fraction=0.046)

        ax = axes[1, 1]
        contour = ax.contourf(self.X, self.Y, self.results['L2'], levels=15, cmap='viridis')
        ax.contour(self.X, self.Y, self.results['L2'], levels=15, colors='black', alpha=0.3, linewidths=0.5)
        self._style_axes(ax, 'x (input mantissa)', 'y (input mantissa)')
        ax.set_aspect('equal')
        plt.colorbar(contour, ax=ax, label='Output', pad=0.02, fraction=0.046)

        output_path = f'{self.output_prefix}_regions_contour.png'
        self._save_figure(fig, output_path)

    def plot_error_comparison(self):
        fig, axes = plt.subplots(2, 3, figsize=(19, 11), constrained_layout=True)

        for idx, level in enumerate(['L0', 'L1', 'L2']):
            ax = axes[0, idx]
            im = ax.contourf(self.X, self.Y, self.results[f'{level}_error'], levels=15, cmap='hot')
            self._style_axes(ax, 'x', 'y')
            ax.set_aspect('equal')
            plt.colorbar(im, ax=ax, label='Error', pad=0.02, fraction=0.046)

        for idx, level in enumerate(['L0', 'L1', 'L2']):
            ax = axes[1, idx]
            rel_error_clipped = np.minimum(self.results[f'{level}_rel_error'], 5.0)
            im = ax.contourf(self.X, self.Y, rel_error_clipped, levels=15, cmap='RdYlGn_r')
            self._style_axes(ax, 'x', 'y')
            ax.set_aspect('equal')
            plt.colorbar(im, ax=ax, label='Error %', pad=0.02, fraction=0.046)

        output_path = f'{self.output_prefix}_regions_error.png'
        self._save_figure(fig, output_path)

    def plot_region_divisions(self):
        fig, axes = plt.subplots(3, 1, figsize=(7.2, 15.8))

        colors_grid = ['#FFE0B2', '#BBDEFB', '#C8E6C9', '#F8BBD0']
        teps = [(1.25, 1.25), (1.25, 1.75), (1.75, 1.25), (1.75, 1.75)]

        for idx, level in enumerate(['L0', 'L1', 'L2']):
            ax = axes[idx]
            x_dividers = self.region_boundaries[level]['x_dividers']
            y_dividers = self.region_boundaries[level]['y_dividers']

            ax.set_xlim(0.95, 2.05)
            ax.set_ylim(0.95, 2.05)
            ax.set_aspect('equal')

            all_x = [1.0] + x_dividers + [2.0]
            all_y = [1.0] + y_dividers + [2.0]

            color_idx = 0
            for i in range(len(all_x) - 1):
                for j in range(len(all_y) - 1):
                    rect_x = [all_x[i], all_x[i + 1], all_x[i + 1], all_x[i], all_x[i]]
                    rect_y = [all_y[j], all_y[j], all_y[j + 1], all_y[j + 1], all_y[j]]
                    ax.fill(
                        rect_x,
                        rect_y,
                        color=colors_grid[color_idx % len(colors_grid)],
                        alpha=0.72,
                        edgecolor='black',
                        linewidth=2.2,
                    )

                    region_x = (all_x[i] + all_x[i + 1]) / 2
                    region_y = (all_y[j] + all_y[j + 1]) / 2
                    ax.text(region_x, region_y, f'R{color_idx + 1}',
                            ha='center', va='center', fontsize=10.5, fontweight='bold')
                    color_idx += 1

            for x_div in x_dividers:
                ax.axvline(x=x_div, color='red', linestyle='--', linewidth=2.2, alpha=0.8)
                ax.text(
                    x_div,
                    2.065,
                    f'x={x_div:g}',
                    ha='center',
                    fontsize=9.5,
                    fontweight='bold',
                    bbox=dict(boxstyle='round,pad=0.2', facecolor='yellow', alpha=0.82),
                )

            for y_div in y_dividers:
                ax.axhline(y=y_div, color='blue', linestyle='--', linewidth=2.2, alpha=0.8)
                ax.text(
                    1.985,
                    y_div + 0.01,
                    f'y={y_div:g}',
                    ha='right',
                    fontsize=9.5,
                    fontweight='bold',
                    bbox=dict(boxstyle='round,pad=0.2', facecolor='cyan', alpha=0.82),
                )

            if level == 'L0':
                for tep_idx, point in enumerate(teps, start=1):
                    ax.plot(point[0], point[1], 'r*', markersize=25, zorder=5)
                    ax.text(
                        point[0] + 0.015,
                        point[1] - 0.06,
                        f'TEP{tep_idx} = ({point[0]:.2f}, {point[1]:.2f})',
                        ha='left',
                        va='top',
                        fontsize=8.8,
                        fontweight='bold',
                        bbox=dict(boxstyle='round,pad=0.24', facecolor='white', edgecolor='#991b1b', alpha=0.94),
                    )
                ax.text(
                    1.02,
                    1.985,
                    '4 region-specific TEPs',
                    fontsize=10.2,
                    fontweight='bold',
                    bbox=dict(boxstyle='round,pad=0.24', facecolor='yellow', alpha=0.86),
                )
            elif level == 'L1':
                for tep_idx, point in enumerate(teps, start=1):
                    ax.plot(point[0], point[1], 'r*', markersize=22, zorder=5)
                    ax.text(
                        point[0] + 0.015,
                        point[1] - 0.05,
                        f'TEP{tep_idx}: ({point[0]:.2f}, {point[1]:.2f})',
                        ha='left',
                        va='top',
                        fontsize=8.4,
                        bbox=dict(boxstyle='round,pad=0.22', facecolor='white', edgecolor='#991b1b', alpha=0.9),
                    )
                ax.text(
                    1.02,
                    1.985,
                    '4 TEPs + x-local sign / y-offset',
                    fontsize=10.0,
                    fontweight='bold',
                    bbox=dict(boxstyle='round,pad=0.24', facecolor='lightgreen', alpha=0.86),
                )
            else:
                for tep_idx, point in enumerate(teps, start=1):
                    ax.plot(point[0], point[1], 'r*', markersize=22, zorder=5)
                    ax.text(
                        point[0] + 0.015,
                        point[1] - 0.05,
                        f'TEP{tep_idx}: ({point[0]:.2f}, {point[1]:.2f})',
                        ha='left',
                        va='top',
                        fontsize=8.4,
                        bbox=dict(boxstyle='round,pad=0.22', facecolor='white', edgecolor='#991b1b', alpha=0.9),
                    )
                ax.text(
                    1.02,
                    1.985,
                    '4 TEPs + x/y local refinements',
                    fontsize=10.0,
                    fontweight='bold',
                    bbox=dict(boxstyle='round,pad=0.24', facecolor='lightblue', alpha=0.86),
                )

            self._style_axes(ax, 'x (Operand 1 Mantissa)', 'y (Operand 2 Mantissa)')

            ax.grid(True, alpha=0.32, linestyle=':')
            ax.set_xticks(np.arange(1.0, 2.1, 0.25))
            ax.set_yticks(np.arange(1.0, 2.1, 0.25))
            ax.tick_params(labelsize=10.5)

        plt.tight_layout(pad=2.1, h_pad=2.6)
        output_path = f'{self.output_prefix}_region_divisions.png'
        self._save_figure(fig, output_path)

    def plot_detailed_region_analysis(self):
        fig = plt.figure(figsize=(18, 14))

        x_dividers = [1.25, 1.5, 1.75]
        y_dividers = [1.25, 1.5, 1.75]
        all_x = [1.0] + x_dividers + [2.0]
        all_y = [1.0] + y_dividers + [2.0]

        axes = []
        for i in range(4):
            row = []
            for j in range(4):
                row.append(fig.add_subplot(4, 4, i * 4 + j + 1))
            axes.append(row)

        colors = plt.cm.Set3(np.linspace(0, 1, 16))

        for i in range(4):
            for j in range(4):
                ax = axes[i][j]
                x_min, x_max = all_x[i], all_x[i + 1]
                y_min, y_max = all_y[j], all_y[j + 1]

                mask = (self.X >= x_min) & (self.X < x_max) & (self.Y >= y_min) & (self.Y < y_max)
                l2_error_region = np.where(mask, self.results['L2_error'], np.nan)

                if np.any(~np.isnan(l2_error_region)):
                    ax.contourf(self.X, self.Y, l2_error_region, levels=10, cmap='RdYlGn_r')
                    ax.contour(self.X, self.Y, l2_error_region, levels=5, colors='black', alpha=0.3, linewidths=0.5)

                ax.axvline(x=x_min, color='red', linestyle='-', linewidth=1.5, alpha=0.5)
                ax.axvline(x=x_max, color='red', linestyle='-', linewidth=1.5, alpha=0.5)
                ax.axhline(y=y_min, color='blue', linestyle='-', linewidth=1.5, alpha=0.5)
                ax.axhline(y=y_max, color='blue', linestyle='-', linewidth=1.5, alpha=0.5)

                if np.any(mask):
                    region_error = self.results['L2_error'][mask]
                    region_rel_error = self.results['L2_rel_error'][mask]
                    stat_text = f'R{i * 4 + j + 1}\n'
                    stat_text += f'[{x_min:.2f},{x_max:.2f}) x [{y_min:.2f},{y_max:.2f})\n'
                    stat_text += f'Max: {np.max(region_error):.4f}\n'
                    stat_text += f'Avg: {np.mean(region_error):.4f}\n'
                    stat_text += f'Rel: {np.mean(region_rel_error):.2f}%'

                    ax.text(
                        0.03,
                        0.97,
                        stat_text,
                        transform=ax.transAxes,
                        fontsize=7,
                        verticalalignment='top',
                        ha='left',
                        bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.8),
                    )

                ax.set_xlim(0.95, 2.05)
                ax.set_ylim(0.95, 2.05)
                ax.set_aspect('equal')

                if i == 3:
                    ax.set_xlabel('x', fontsize=10, fontweight='semibold')
                if j == 0:
                    ax.set_ylabel('y', fontsize=10, fontweight='semibold')

                ax.set_xticks([])
                ax.set_yticks([])
                ax.set_facecolor(colors[i * 4 + j])

        plt.tight_layout(pad=1.8, w_pad=1.5, h_pad=1.8)
        output_path = f'{self.output_prefix}_region_detailed_analysis.png'
        self._save_figure(fig, output_path)

    def export_legacy_filenames(self):
        """Mirror RTL_proposed outputs to historical filenames for compatibility."""
        if self.variant != 'RTL_proposed':
            return []

        legacy_mapping = {
            f'{self.output_prefix}_regions_analysis.png': 'mantissa_regions_analysis.png',
            f'{self.output_prefix}_regions_contour.png': 'mantissa_regions_contour.png',
            f'{self.output_prefix}_regions_error.png': 'mantissa_regions_error.png',
            f'{self.output_prefix}_region_divisions.png': 'mantissa_region_divisions.png',
            f'{self.output_prefix}_region_detailed_analysis.png': 'mantissa_region_detailed_analysis.png',
        }

        copied = []
        for source, target in legacy_mapping.items():
            shutil.copyfile(source, target)
            copied.append(target)

        return copied


def run_analysis_for_variant(variant, resolution=50):
    """Run the full analysis flow for one RTL variant."""
    print("\n" + "=" * 80)
    print(f"MANTISSA MULTIPLICATION REGION ANALYZER - {variant}")
    print("=" * 80)

    analyzer = MantissaRegionAnalyzer(variant=variant, resolution=resolution)

    print("\nComputing approximation regions...")
    analyzer.compute_regions()
    print("✓ Regions computed successfully\n")

    analyzer.print_statistics()

    print("\nGenerating visualizations...")
    analyzer.plot_regions()
    analyzer.plot_contour_comparison()
    analyzer.plot_error_comparison()

    print("\nGenerating region division visualizations...")
    analyzer.plot_region_divisions()
    analyzer.plot_detailed_region_analysis()

    legacy_files = analyzer.export_legacy_filenames()
    generated_files = [
        f"{analyzer.output_prefix}_regions_analysis.png",
        f"{analyzer.output_prefix}_regions_contour.png",
        f"{analyzer.output_prefix}_regions_error.png",
        f"{analyzer.output_prefix}_region_divisions.png",
        f"{analyzer.output_prefix}_region_detailed_analysis.png",
    ]

    print("\n" + "=" * 80)
    print(f"{variant} Analysis Complete!")
    print("=" * 80)
    print("\nGenerated files:")
    for idx, path in enumerate(generated_files, start=1):
        print(f"  {idx}. {path}")

    if legacy_files:
        print("\nLegacy compatibility files refreshed:")
        for path in legacy_files:
            print(f"  • {path}")

    print("\nThese visualizations show the mantissa multiplication regions for:")
    print("  • L0: 4 coarse Taylor regions")
    print("  • L1: 8 regions with x-local sign and y-offset correction")
    print("  • L2: 16 regions with y-local sign and x-offset correction")
    print("\n" + "=" * 80 + "\n")

    return analyzer


def main():
    """Main execution function."""
    for variant in ['RTL_proposed', 'RTL_proposed_2']:
        run_analysis_for_variant(variant, resolution=50)


if __name__ == "__main__":
    main()
