# RTL_proposed Design Changes

## Overview
Redesigned the approximation multiplier to use a **four-region piecewise linear approximation** at Level 0, with region-based internal divisions for Levels 1-5.

## Changes Made

### 1. Deleted RTL_proposed_2 and Related Files
- Removed `/RTL_proposed_2/` directory
- Removed `/tb/RTL_proposed_2/` testbench directory  
- Removed `rtl_proposed_2_testbench_simulation.py`

### 2. Redesigned Level 0 (delta_f0)

**Old Design:** Single global approximation
```
f₀(x,y) = 1.5(x+y) - 0.375
```

**New Design:** Four independent regions based on x[WIDTH-2] and y[WIDTH-2]

#### Region Division
Each region uses center point (a, b) with equation: **f'(x,y) = b·x + a·y - a·b**

| Region | Condition | Center (a,b) | Equation |
|--------|-----------|--------------|----------|
| 00 | x<0.5, y<0.5 | (0.25, 0.25) | 0.25x + 0.25y - 0.0625 |
| 01 | x<0.5, y≥0.5 | (0.25, 0.75) | 0.75x + 0.25y - 0.1875 |
| 10 | x≥0.5, y<0.5 | (0.75, 0.25) | 0.25x + 0.75y - 0.1875 |
| 11 | x≥0.5, y≥0.5 | (0.75, 0.75) | 0.75x + 0.75y - 0.5625 |

### 3. Redesigned Levels 1-5 (Internal Divisions)

**New Design:** Region-aware internal division using region center points (a_in, b_in)

Internal division formula alternates between x and y differences:

| Level | Formula | Divisor |
|-------|---------|---------|
| 1 | (x - a_in) / 2² | 2² |
| 2 | (y - b_in) / 2³ | 2³ |
| 3 | (x - a_in) / 2⁴ | 2⁴ |
| 4 | (y - b_in) / 2⁵ | 2⁵ |
| 5 | (x - a_in) / 2⁶ | 2⁶ |

Where:
- a_in = 0.75 if x[WIDTH-2]=1, else 0.25
- b_in = 0.75 if y[WIDTH-2]=1, else 0.25

### 4. Implementation Details

**Key Features:**
- Each region operates independently with its own local center points
- Internal divisions are computed relative to region centers
- All six levels (0-5) use the new region-aware logic
- Maintains backward compatibility with existing bit_mask_sel and testbenches

**Module Interface:** (Unchanged)
- Input: x[WIDTH-2:0], y[WIDTH-2:0] - 7-bit inputs for WIDTH=8
- Input: Conf_Bit_Mask[WIDTH-3:0] - Configuration for level selection
- Output: f[2*WIDTH-1:0] - 16-bit result for WIDTH=8

## Design Motivation

The four-region division enables more accurate piecewise linear approximation of multiplication across the input space. By dividing the 2D domain into four equal quadrants and using region-specific center points, the linear approximation (Taylor expansion) in each region is more accurate than using a single global center point.

## Testing

Existing testbenches in `/tb/RTL_proposed/` for:
- Fixed-point multiplication
- Floating-point multiplication  
- Signed integer multiplication
- Unsigned integer multiplication

All testbenches remain compatible with the new `approx_t.v` module.

## File Structure

```
RTL_proposed/
├── approx_t.v (REDESIGNED)
├── bit_mask_sel.v (unchanged)
├── fixed_point_mul.v
├── floating_point_mul.v
├── leading_one_detector.v
├── signed_int_mul.v
├── unsigned_int_mul.v
├── README
└── README.md
```

## Notes

- The design maintains the same hardware interface and parameterization as before
- The bit width calculations and sign extension patterns follow the existing code style
- Configuration bits (Conf_Bit_Mask) work identically to select precision levels
- The module generates 6 refinement levels (delta_f0 through delta_f5) for flexible precision
