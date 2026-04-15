# Batch Genus driver for running all multiplier datatypes across RTL variants.
# Drop this repo (RTL, RTL_proposed, RTL_proposed_2, constraints, scripts) into
# ~/Samsung_Chip_Desing_2 on the Cadence machine, then run:
#   env ROOT=~/Samsung_Chip_Desing_2 genus -batch -files scripts/batch_genus.tcl
# - ROOT        : optional; folder containing RTL/RTL_proposed/RTL_proposed_2/etc (defaults to pwd)
# - VCD_LEVELS  : optional; space/comma list of precision levels (e.g. "L0 L1 L2"). Default L0 L1 L2.
# - VCD_LEVEL   : legacy single precision level (fallback if VCD_LEVELS not set)
# - GUI         : set to 1 to launch gui_show for the last run.

# ---------- User knobs ----------
set root_dir  [file normalize [expr {[info exists ::env(ROOT)] ? $::env(ROOT) : [pwd]}]]
set tech_node "cadence_45nm"
set cell_types "fast_vdd1v0_basicCells.lib"
set qrc_file   "gpdk045.tch"        ;# resolved under $root_dir/pdks/$tech_node/qrc/
set constraint_file [file join $root_dir constraints 45nm_1GHz.sdc]
# VCD levels to sweep (defaults to L0 L1 L2). Override with VCD_LEVELS="L0 L1 L2" or legacy VCD_LEVEL="L2".
if {[info exists ::env(VCD_LEVELS)]} {
    # Accept space- or comma-separated list
    set vcd_levels [split [string map {"," " "} $::env(VCD_LEVELS)] " "]
} elseif {[info exists ::env(VCD_LEVEL)]} {
    set vcd_levels [list $::env(VCD_LEVEL)]
} else {
    set vcd_levels [list L0 L1 L2]
}
# Drop empty tokens if the env had extra spaces/commas
set _tmp_levels {}
foreach lvl $vcd_levels {
    if {$lvl eq ""} { continue }
    lappend _tmp_levels $lvl
}
set vcd_levels $_tmp_levels

# VCD location (prefer explicit env, then ~/Samsung_Chip_Desing_2/vcd, then Results_tabulation/vcd)
set vcd_base   ""
if {[info exists ::env(VCD_ROOT)]} {
    set vcd_base [file normalize $::env(VCD_ROOT)]
}
if {$vcd_base eq ""} {
    set candidate_local [file join $root_dir vcd]
    set candidate_results [file join $root_dir Results_tabulation vcd]
    if {[file exists $candidate_local]} {
        set vcd_base $candidate_local
    } elseif {[file exists $candidate_results]} {
        set vcd_base $candidate_results
    } else {
        # fall back to the Results_tabulation structure even if absent; per-run checks will warn
        set vcd_base $candidate_results
    }
}

# RTL variants to sweep (name = label used in output paths)
set variants {
    {name base          rtl_dir RTL             vcd_scope base}
    {name RTL_proposed  rtl_dir RTL_proposed    vcd_scope RTL_proposed}
    {name RTL_proposed_2 rtl_dir RTL_proposed_2 vcd_scope RTL_proposed_2}
}

# Datatype designs to sweep
set designs {
    {id unsigned_int   top unsigned_int_mul   vfile unsigned_int_mul.v   vcd_dir Unsigned_int}
    {id signed_int     top signed_int_mul     vfile signed_int_mul.v     vcd_dir Signed_int}
    {id fixed_point    top fixed_point_mul    vfile fixed_point_mul.v    vcd_dir Fixed_point}
    {id floating_point top floating_point_mul vfile floating_point_mul.v vcd_dir Floating_point}
    {id approx_t       top approx_t           vfile approx_t.v           vcd_dir Approx_t}
}

# Synthesis efforts
set generic_effort "high"
set map_effort     "high"
set opt_effort     "high"

# ---------- Helpers ----------
proc ensure_dirs {dirs} {
    foreach d $dirs {
        if {![file exists $d]} {file mkdir $d}
    }
}

proc run_one {root tech_node cell_types constraint_file qrc_file vcd_level vcd_base variant design generic_effort map_effort opt_effort} {
    array set v $variant
    array set d $design

    # Basic paths
    set rtl_dir [file join $root $v(rtl_dir)]
    set run_tag "${v(name)}__${d(id)}__${vcd_level}"
    set log_dir [file join $root genus logs]
    set rpt_root [file join $root genus reports $v(name) $d(id) $tech_node]
    set lec_root [file join $root genus lec     $v(name) $d(id) $tech_node]
    set syn_root [file join $root genus synthesis $v(name) $d(id) $tech_node]

    ensure_dirs [list $log_dir \
                      [file join $rpt_root design_check] \
                      [file join $rpt_root generic] \
                      [file join $rpt_root mapped] \
                      [file join $rpt_root opt] \
                      [file join $syn_root generic] \
                      [file join $syn_root mapped] \
                      [file join $syn_root opt] \
                      [file join $lec_root]]

    # Reset any previous design state
    reset_design

    # Core database knobs (kept close to the original genus_script.tcl)
    set_db hdl_unconnected_value 1
    set_db init_lib_search_path   [file join $root pdks $tech_node lib]
    set_db init_hdl_search_path   $rtl_dir
    set_db auto_ungroup none
    set_db information_level 7
    set log_file [file join $log_dir "${run_tag}.log"]
    set_db stdout_log $log_file
    set_db fail_on_error_mesg true
    set_db hdl_track_filename_row_col true
    set_db library $cell_types
    set_db hdl_parameter_naming_style _%s%d
    set_db auto_partition true
    set_db drc_first true
    set_db hdl_max_memory_address_range inf

    # Read HDL (pull all files in the chosen RTL folder so dependencies are covered)
    set hdl_files [glob -nocomplain [file join $rtl_dir *.v]]
    if {[llength $hdl_files] == 0} {
        puts "WARN: No HDL files found under $rtl_dir; skipping $run_tag"
        return
    }
    read_hdl -language sv $hdl_files
    set top_module $d(top)
    elaborate $top_module

    # Reports: unresolved references
    check_design -unresolved > [file join $rpt_root design_check design_check.rpt]

    # Constraints
    if {![file exists $constraint_file]} {
        puts "WARN: constraint file $constraint_file not found; continuing without SDC for $run_tag"
    } else {
        read_sdc $constraint_file
    }

    # Physical collateral
    read_physical -lefs      [glob -nocomplain [file join $root pdks $tech_node lef *tech.lef]]
    read_physical -add_lefs  [glob -nocomplain [file join $root pdks $tech_node lef *macro.lef]]
    set qrc_path [file join $root pdks $tech_node qrc $qrc_file]
    if {[file exists $qrc_path]} { read_qrc $qrc_path }

    # VCD for activity-based power
    set vcd_file [file join $vcd_base $v(vcd_scope) $d(vcd_dir) "${d(vcd_dir)}_${vcd_level}.vcd"]
    if {[file exists $vcd_file]} {
        puts "INFO: Using VCD $vcd_file"
        read_activity_file -format vcd -scope $top_module $vcd_file
    } else {
        puts "WARN: VCD not found ($vcd_file); power numbers for $run_tag will be vectorless."
    }

    # Generic synthesis
    set_db syn_generic_effort $generic_effort
    syn_generic
    write_hdl  > [file join $syn_root generic "${run_tag}_syn_generic.v"]
    write_sdc  > [file join $syn_root generic "${run_tag}_syn_generic.sdc"]
    report_power > [file join $rpt_root generic "${run_tag}_syn_generic_power.rpt"]
    write_snapshot -outdir [file join $rpt_root generic] -tag ${run_tag}_syn_generic

    # Mapping
    set_db syn_map_effort $map_effort
    syn_map
    write_hdl  > [file join $syn_root mapped "${run_tag}_syn_map.v"]
    write_sdc  > [file join $syn_root mapped "${run_tag}_syn_map.sdc"]
    report_power > [file join $rpt_root mapped "${run_tag}_syn_map_power.rpt"]
    write_snapshot -outdir [file join $rpt_root mapped] -tag ${run_tag}_syn_map
    write_hdl -lec > [file join $lec_root "${run_tag}_lec_pre_opt.v"]
    write_do_lec -golden_design rtl \
                 -revised_design [file join $lec_root "${run_tag}_lec_pre_opt.v"] \
                 > [file join $lec_root "${run_tag}_lec_pre_opt.do"]

    # Optimization
    set_db syn_opt_effort $opt_effort
    syn_opt -incr
    write_hdl  > [file join $syn_root opt "${run_tag}_syn_opt.v"]
    write_sdc  > [file join $syn_root opt "${run_tag}_syn_opt.sdc"]
    report_power > [file join $rpt_root opt "${run_tag}_syn_opt_power.rpt"]
    write_snapshot -outdir [file join $rpt_root opt] -tag ${run_tag}_syn_opt
    report_summary -directory $rpt_root
    report_timing -unconstrained > [file join $rpt_root opt "${run_tag}_syn_opt_timing_path.rpt"]
    write_hdl -lec > [file join $lec_root "${run_tag}_lec_opt.v"]
    write_do_lec -golden_design [file join $lec_root "${run_tag}_lec_pre_opt.v"] \
                 -revised_design [file join $lec_root "${run_tag}_lec_opt.v"] \
                 > [file join $lec_root "${run_tag}_lec_opt.do"]

    # Cleanup: remove the run-specific Genus log to keep the logs directory light.
    if {[file exists $log_file]} {
        file delete -force $log_file
    }
}

# ---------- Main loop ----------
foreach vcd_level $vcd_levels {
    foreach variant $variants {
        foreach design $designs {
            run_one $root_dir $tech_node $cell_types $constraint_file $qrc_file $vcd_level $vcd_base \
                    $variant $design $generic_effort $map_effort $opt_effort
        }
    }
}

if {[info exists ::env(GUI)] && $::env(GUI)} { gui_show }
exit
