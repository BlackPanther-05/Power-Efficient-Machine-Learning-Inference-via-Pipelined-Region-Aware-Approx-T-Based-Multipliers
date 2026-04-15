# Technology node parameters (folder name under pdks/)
set tech_node "cadence_45nm"

# Cell Type
set fast_cell_type    "fast_vdd1v0_basicCells.lib"
set slow_cell_type    "slow_vdd1v0_basicCells.lib"
# set typical_cell_type "fast_vdd1v0_basicCells.lib"
set cell_types        $fast_cell_type


# Default top (can be overridden by DESIGN env var in genus_script.tcl)
# Choose a design that exists in all RTL variants.
set hdl_file "unsigned_int_mul"

# QRC tech file name (under pdks/$tech_node/qrc/)
set qrc_file "gpdk045.tch"

# Synthesis efforts
set generic_effort "high"
set map_effort "high"
set opt_effort "high"

# Physical Design
set aspect_ratio_core 1
set utilization 0.7
set lmargin 10
set rmargin 10
set tmargin 10
set bmargin 10

