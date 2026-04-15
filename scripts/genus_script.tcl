###############################################################################
# Dynamic single-run Genus script
# Usage (examples):
#   env ROOT=~/Samsung_Chip_Desing_2 VARIANT=RTL DESIGN=unsigned_int_mul genus -batch -files scripts/genus_script.tcl
#   env VARIANT=RTL_proposed_2 DESIGN=floating_point_mul genus -batch -files scripts/genus_script.tcl
#
# ROOT   : project root containing RTL/, RTL_proposed/, RTL_proposed_2/, constraints/, pdks/, scripts/
# VARIANT: which RTL folder to use (RTL | RTL_proposed | RTL_proposed_2). Default RTL.
# DESIGN : top module name. Default comes from config_script.tcl variable hdl_file.
# CONSTRAINT: override constraint file path. Default ROOT/constraints/45nm_1GHz.sdc.
# VCD    : optional activity file path. If provided and exists, it is loaded for power.
###############################################################################

source ./scripts/config_script.tcl

set DATE [clock format [clock seconds] -format "%b%d-%T"] 

# Resolve root and variant
set root_dir  [file normalize [expr {[info exists ::env(ROOT)] ? $::env(ROOT) : [pwd]}]]
set variant   [expr {[info exists ::env(VARIANT)] ? $::env(VARIANT) : "RTL"}]
set design    [expr {[info exists ::env(DESIGN)] ? $::env(DESIGN) : $hdl_file}]

# Derived paths
set rtl_dir   [file join $root_dir $variant]
set constr_default [file join $root_dir constraints 45nm_1GHz.sdc]
set constraint_file [expr {[info exists ::env(CONSTRAINT)] ? $::env(CONSTRAINT) : $constr_default}]
set vcd_file  [expr {[info exists ::env(VCD)] ? $::env(VCD) : ""}]

# Ensure output dirs
set log_dir   [file join $root_dir genus logs]
set rpt_root  [file join $root_dir genus reports $variant $design $tech_node]
set lec_root  [file join $root_dir genus lec $variant $design $tech_node]
set syn_root  [file join $root_dir genus synthesis $variant $design $tech_node]
foreach d [list $log_dir \
                [file join $rpt_root design_check] \
                [file join $rpt_root generic] \
                [file join $rpt_root mapped] \
                [file join $rpt_root opt] \
                $lec_root \
                [file join $syn_root generic] \
                [file join $syn_root mapped] \
                [file join $syn_root opt]] {
    if {![file exists $d]} { file mkdir $d }
}

set_db hdl_unconnected_value 1 
#set_db timing_report_unconstrained true

# Directory to search for .lib (Library) files
set_db init_lib_search_path [file join $root_dir pdks $tech_node lib]

# Directory to search RTL files
set_db init_hdl_search_path $rtl_dir

# unflatten: individual optimization
set_db auto_ungroup none

# Verbose info level 0-9 (Recommended-6, Max-9)
set_db information_level 7

# Write log file for each run
set log_file [file join $log_dir "${variant}_${design}.log"]
set_db stdout_log $log_file

# Stop genus from executing when it encounters error
set_db fail_on_error_mesg true

# This attribute enables Genus to keep track of filenames, line numbers, and column numbers
# for all instances before optimization. Genus also uses this information in subsequent error
# and warning messages.
set_db hdl_track_filename_row_col true



# This is for timing optimization read genus legacy UI documentation if results are worst
#set_db tns_opto true /

# Choose the lib cell type
set_db library $cell_types 


# Naming style used in rtl
set_db hdl_parameter_naming_style _%s%d 

# Automatically partition the design and run fast in genus
set_db auto_partition true

# Check DRC & force Genus to fix DRCs, even at the expense of timing, with the drc_first attribute.
set_db drc_first true 

#Solve maximum memory address range issue
set_db hdl_max_memory_address_range inf
# Read verilog file ( if it is sv just replace the extension)
# Read *all* RTL under the selected variant so shared deps are picked up.
set hdl_files [glob -nocomplain [file join $rtl_dir *.v]]
if {[llength $hdl_files] == 0} {
    puts "ERROR: No RTL files found in $rtl_dir"
    exit 1
}
read_hdl -language sv $hdl_files
set top_module $design

# Elaborate the design
elaborate

# Check for unresolved refernces # Technology independent
check_design -unresolved > [file join $rpt_root design_check design_check.rpt]


# Read the constraint file # Technology Independent
if {[file exists $constraint_file]} {
    read_sdc $constraint_file
} else {
    puts "WARN: constraint file $constraint_file not found; continuing without SDC"
}


# LEF file
read_physical -lefs [glob -nocomplain [file join $root_dir pdks $tech_node lef *tech.lef]]
read_physical -add_lefs [glob -nocomplain [file join $root_dir pdks $tech_node lef *macro.lef]]

#QRC file
set qrc_path [file join $root_dir pdks $tech_node qrc $qrc_file]
if {[file exists $qrc_path]} { read_qrc $qrc_path }

# Define cost groups (clk-clk, clk-output, input-clk, input-output)
#define_cost_group -name I2C -design $hdl_file
#define_cost_group -name C2O -design $hdl_file
#define_cost_group -name C2C -design $hdl_file
#define_cost_group -name I2O -design $hdl_file

#path_group -from [all_registers] -to [all_registers] -group C2C -name C2C
#path_group -from [all_registers] -to [all_outputs] -group C2O -name C2O
#path_group -from [all_inputs] -to [all_registers] -group I2C -name I2C
#path_group -from [all_inputs] -to [all_outputs] -group I2O -name I2O

#set file_rpt "./genus/reports/$hdl_file/$tech_node/presynth/${hdl_file}_presynth.rpt"
#set file_gtd "./genus/reports/$hdl_file/$tech_node/presynth/${hdl_file}_presynth.gtd"

#if {[file exists $file_rpt]} {
#	file delete $file_rpt
#}

#if {[file exists $file_gtd]} {
#	file delete $file_gtd
#}

#foreach cg [vfind / -cost_group *] {
#	report_timing -group [list $cg] -output_format gtd >> ./genus/reports/$hdl_file/$tech_node/presynth/${hdl_file}_presynth.gtd
#	report_timing -group [list $cg] >> "./genus/reports/$hdl_file/$tech_node/presynth/${hdl_file}_presynth.rpt"
#}


# Set the top module name in hierarchical design if the modules are not in same rtl file
#set top_module sigmoid_float_0_1


# Analytical optimization identifies connected, cross-hierarchy regions of the datapath logic, and
# selects the best architecture for each region within the context of the full design. This optimization
# explores multiple architectures for each region by applying a range of constraints

# The best area results are obtained, at the possible expense of timing.
#set_db dp_analytical_opt extreme

# To turn off carry-save transformations
#set_db dp_csa none


# If the user_sub_arch attribute is specified on a multiplier, it will take precedence over the
# apply_booth_encoding setting.

# Booth encoding options {nonbooth | auto_bitwidth | auto_togglerate | manual | inherited}
#set_db apply_booth_encoding auto_togglerate

# Report Datapath Operators
#report_dp -all -print_inferred > ./genus/reports/$hdl_file/$tech_node/post_elaboration/syn_generic_datapath_report.rpt


# VCD activity (optional)
if {$vcd_file ne "" && [file exists $vcd_file]} {
    read_activity_file -format vcd -scope $top_module $vcd_file
}

# Generic Synthesis
set_db syn_generic_effort $generic_effort
syn_generic 
write_hdl > [file join $syn_root generic "${design}_syn_generic.v"]
write_sdc > [file join $syn_root generic "${design}_syn_generic.sdc"]
report_power > [file join $rpt_root generic "${design}_syn_generic_power.rpt"]
write_snapshot -outdir [file join $rpt_root generic] -tag ${design}_syn_generic
report_power > [file join $rpt_root generic "${design}_syn_generic_power.rpt"]

# Mapping 
set_db syn_map_effort $map_effort
syn_map
time_info MAPPED
write_hdl > [file join $syn_root mapped "${design}_syn_map.v"]
write_sdc > [file join $syn_root mapped "${design}_syn_map.sdc"]
report_power > [file join $rpt_root mapped "${design}_syn_map_power.rpt"]
write_snapshot -outdir [file join $rpt_root mapped] -tag ${design}_syn_map
report_power > [file join $rpt_root mapped "${design}_syn_map_power.rpt"]
# step 1 LEC do file generation
write_hdl -lec > [file join $lec_root "${design}_lec_pre_opt.v"]
write_do_lec -golden_design rtl -revised_design [file join $lec_root "${design}_lec_pre_opt.v"] > [file join $lec_root "${design}_lec_pre_opt.do"]


# Incremental performs area and power optimization

# Optimized
set_db syn_opt_effort $opt_effort
syn_opt -incr
time_info OPT
write_hdl > [file join $syn_root opt "${design}_syn_opt.v"]
write_sdc > [file join $syn_root opt "${design}_syn_opt.sdc"]
report_power > [file join $rpt_root opt "${design}_syn_opt_power.rpt"]
write_snapshot -outdir [file join $rpt_root opt] -tag ${design}_syn_opt
report_summary -directory $rpt_root
report_timing -unconstrained  > [file join $rpt_root opt "${design}_syn_opt_timing_path.rpt"]
report_power > [file join $rpt_root opt "${design}_syn_opt_power.rpt"]
# step 2 LEC do file generation for synthesized netlist
write_hdl -lec > [file join $lec_root "${design}_lec_opt.v"]
write_do_lec -golden_design [file join $lec_root "${design}_lec_pre_opt.v"] -revised_design [file join $lec_root "${design}_lec_opt.v"] > [file join $lec_root "${design}_lec_opt.do"]

# Report design rules
#uncomment
#report_design_rules > ./genus/reports/$hdl_file/$tech_node/des-Rules.rpt

#set file_rpt "./genus/reports/$hdl_file/$tech_node/postsynth/${hdl_file}_post_opt.rpt"
#set file_gtd "./genus/reports/$hdl_file/$tech_node/postsynth/${hdl_file}_post_opt.gtd"

#if {[file exists $file_rpt]} {
#	file delete $file_rpt
#}

#if {[file exists $file_gtd]} {
#	file delete $file_gtd
#}

#foreach cg [vfind / -cost_group *] {
#	puts [list $cg]
#	report_timing -group [list $cg] >> ./genus/reports/$hdl_file/$tech_node/postsynth/${hdl_file}_post_opt.rpt
#	report_timing -group [list $cg] -output_format gtd >> ./genus/reports/$hdl_file/$tech_node/postsynth/${hdl_file}_post_opt.gtd
#}



# Display in gui window
gui_show
if {[file exists $log_file]} { file delete -force $log_file }
exit
