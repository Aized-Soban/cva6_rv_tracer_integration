# ============================================================
# atb_funnel_fixed.tcl  (repo-root relative, robust)
#
# Repo root:
#   tracer_integration/
#     deps/
#     atb_funnel/
#     vivado/atb_funnel_fixed.tcl   <-- this file
#
# Usage:
#   vivado -mode batch -source vivado/atb_funnel_fixed.tcl
#   PART=xc7a35tcpg236-1 vivado -mode batch -source vivado/atb_funnel_fixed.tcl
#   SIM_TOP=tb_atb_priority_mux vivado -mode batch -source vivado/atb_funnel_fixed.tcl
# ============================================================

# ------------------------------------------------------------
# Force working directory to repo root (one level above this TCL)
# ------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
cd [file normalize "$script_dir/.."]

set proj_name "atb_funnel_setup"
set build_dir [file normalize "./vivado_build_atb_funnel"]

# Set FPGA part from env if provided, else use a sensible default
if {[info exists ::env(PART)] && $::env(PART) ne ""} {
  set part_name $::env(PART)
} else {
  # Original auto-generated script used xc7vx485tffg1157-1
  set part_name "xc7vx485tffg1157-1"
}

# Optional sim top override
if {[info exists ::env(SIM_TOP)] && $::env(SIM_TOP) ne ""} {
  set sim_top_name $::env(SIM_TOP)
} else {
  set sim_top_name "tb_atb_funnel_top"
}

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
proc must_exist {p} {
  if {![file exists $p]} {
    puts "ERROR: Missing required path: $p"
    exit 1
  }
}
proc add_sv {p} {
  if {![file exists $p]} {
    puts "ERROR: Missing required SV file: $p"
    exit 1
  }
  add_files -norecurse [file normalize $p]
}
proc add_sv_if_exists {p} {
  if {[file exists $p]} {
    add_files -norecurse [file normalize $p]
    return 1
  }
  return 0
}
proc add_sv_sim_if_exists {p} {
  if {[file exists $p]} {
    add_files -fileset sim_1 -norecurse [file normalize $p]
    return 1
  }
  return 0
}

# ------------------------------------------------------------
# Fixed paths based on repo tree
# ------------------------------------------------------------
set deps_dir   "./deps"
set funnel_dir "./atb_funnel"

# ------------------------------------------------------------
# Sanity checks
# ------------------------------------------------------------
must_exist $deps_dir
must_exist "$deps_dir/common_cells"
must_exist $funnel_dir
must_exist "$funnel_dir/rtl"
must_exist "$funnel_dir/tb"

# Top-level RTL expected by original script
must_exist "$funnel_dir/rtl/atb_flush_ctrl.sv"
must_exist "$funnel_dir/rtl/atb_priority_mux.sv"
must_exist "$funnel_dir/rtl/atb_funnel_top.sv"

# ------------------------------------------------------------
# Create project
# ------------------------------------------------------------
file mkdir $build_dir
create_project $proj_name $build_dir -part $part_name -force

# Set simulator language explicitly; design is SV-only here
set_property simulator_language Mixed [current_project]
set_property default_lib xil_defaultlib [current_project]

# ------------------------------------------------------------
# Add common_cells dependencies
# ------------------------------------------------------------
add_sv "$deps_dir/common_cells/src/cdc_2phase.sv"
add_sv "$deps_dir/common_cells/src/cdc_fifo_2phase.sv"
add_sv "$deps_dir/common_cells/src/edge_detect.sv"
add_sv "$deps_dir/common_cells/src/fifo_v3.sv"
add_sv "$deps_dir/common_cells/src/sync.sv"
add_sv "$deps_dir/common_cells/src/sync_wedge.sv"

# pulp_clock_gating lives in common_cells in your generated project
add_sv "$deps_dir/common_cells/src/pulp_clock_gating.sv"

# ------------------------------------------------------------
# Add funnel RTL
# ------------------------------------------------------------
add_sv "$funnel_dir/rtl/atb_flush_ctrl.sv"
add_sv "$funnel_dir/rtl/atb_priority_mux.sv"
add_sv "$funnel_dir/rtl/atb_funnel_top.sv"

set_property top atb_funnel_top [current_fileset]

# ------------------------------------------------------------
# Add testbenches (simulation only)
# ------------------------------------------------------------
set found_any_tb 0

if {[add_sv_sim_if_exists "$funnel_dir/tb/tb_atb_funnel_top.sv"]} {
  set found_any_tb 1
}
if {[add_sv_sim_if_exists "$funnel_dir/tb/tb_atb_funnel_pre_fifo_top.sv"]} {
  set found_any_tb 1
}
if {[add_sv_sim_if_exists "$funnel_dir/tb/tb_atb_priority_mux.sv"]} {
  set found_any_tb 1
}
if {[add_sv_sim_if_exists "$funnel_dir/tb/tb_atb_flush_ctrl.sv"]} {
  set found_any_tb 1
}

if {$found_any_tb} {
  if {[llength [get_files -quiet -of_objects [get_filesets sim_1]]] > 0} {
    set_property top $sim_top_name [get_filesets sim_1]
    set_property xsim.simulate.runtime 4000ns [get_filesets sim_1]
  }
} else {
  puts "WARNING: No testbench files found under $funnel_dir/tb"
}

# ------------------------------------------------------------
# Compile order
# ------------------------------------------------------------
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "============================================================"
puts "ATB funnel project imported successfully."
puts "PWD:      [pwd]"
puts "Project:  $proj_name"
puts "Build:    $build_dir"
puts "Part:     $part_name"
puts "RTL top:  atb_funnel_top"
if {$found_any_tb} {
  puts "SIM top:  $sim_top_name"
} else {
  puts "SIM top:  <none found>"
}
puts "============================================================"
