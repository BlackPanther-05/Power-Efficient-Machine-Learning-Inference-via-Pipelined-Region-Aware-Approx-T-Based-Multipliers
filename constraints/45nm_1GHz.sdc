###############################################################################
# Technology  : GPDK45 (generic 45nm)
# Target freq: 1 GHz  (1.0 ns period)
# Scope      : Single-clock designs using port 'clk', active-low reset 'rst_n'
# Notes      : Keep simple, tech-agnostic values to let Genus elaborate cleanly.
###############################################################################

# Primary clock
create_clock -name clk -period 1.000 [get_ports clk]

# Clock uncertainty (jitter + skew allowance)
set_clock_uncertainty 0.05 [get_clocks clk]

# Input and output delays (budget 200 ps each side of the period)
set_input_delay  0.20 -clock clk [all_inputs]
set_output_delay 0.20 -clock clk [all_outputs]

# Reset: prevent false timing on async assertion
set_false_path -from [get_ports rst_n]

# Basic driving strength and load assumptions
set_drive 0   [all_inputs]
set_load  0.05 [all_outputs]

# Limit fanout to keep synthesis sane at 1 GHz
set_max_fanout 12 [current_design]

# Prevent aggressive buffer removal on the main clock
set_dont_touch_network [get_ports clk]

# Optional: preserve hierarchy during initial read
# set_ungroup [current_design]

###############################################################################
# End of file
###############################################################################
