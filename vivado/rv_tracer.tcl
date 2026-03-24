# ============================================================
# rv_tracer.tcl  (repo-root relative, robust)
#
# Repo root:
#   tracer_integration/
#     deps/
#     ip/third_party/rv_tracer/
#     top_trace/
#     vivado/rv_tracer_only.tcl   <-- this file
# ============================================================

# ------------------------------------------------------------
# Force working directory to repo root (one level above this TCL)
# ------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
cd [file normalize "$script_dir/.."]

set proj_name "rv_tracer_only"
set build_dir [file normalize "./vivado_build_rv_tracer_only"]

# FPGA part from env if provided, else default
if {[info exists ::env(PART)] && $::env(PART) ne ""} {
  set part_name $::env(PART)
} else {
  set part_name "xc7a35tcpg236-1"
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
proc add_sv_sim {p} {
  if {![file exists $p]} {
    puts "ERROR: Missing required SIM SV file: $p"
    exit 1
  }
  add_files -fileset sim_1 -norecurse [file normalize $p]
}

# ------------------------------------------------------------
# Fixed paths
# ------------------------------------------------------------
set deps_dir        "./deps"
set third_party_dir "./ip/third_party"
set rv_tracer_dir   "$third_party_dir/rv_tracer"
set top_dir         "./top_trace"

# ------------------------------------------------------------
# Sanity checks
# ------------------------------------------------------------
must_exist $deps_dir
must_exist "$deps_dir/common_cells"
must_exist "$deps_dir/tech_cells_generic"

must_exist $third_party_dir
must_exist $rv_tracer_dir

# TB location (you can keep tb under top_trace/tb)
must_exist $top_dir
must_exist "$top_dir/tb"

# ------------------------------------------------------------
# Create project
# ------------------------------------------------------------
file mkdir $build_dir
create_project $proj_name $build_dir -part $part_name -force

# ------------------------------------------------------------
# Include dirs (rv_tracer packages/includes)
# ------------------------------------------------------------
set inc_list [list \
  [file normalize "$rv_tracer_dir/include"] \
]

set_property include_dirs $inc_list [current_fileset]
set_property include_dirs $inc_list [get_filesets sim_1]

# ------------------------------------------------------------
# Add dependencies (common_cells + tech_cells_generic)
# ------------------------------------------------------------
add_sv "$deps_dir/common_cells/src/fifo_v3.sv"
add_sv "$deps_dir/common_cells/src/delta_counter.sv"
add_sv "$deps_dir/common_cells/src/cf_math_pkg.sv"
add_sv "$deps_dir/common_cells/src/counter.sv"
add_sv "$deps_dir/common_cells/src/sync.sv"
add_sv "$deps_dir/common_cells/src/sync_wedge.sv"
add_sv "$deps_dir/common_cells/src/edge_detect.sv"

add_sv "$deps_dir/tech_cells_generic/src/rtl/tc_clk.sv"

set pulp_clk_a "$deps_dir/tech_cells_generic/src/deprecated/pulp_clk_cells.sv"
set pulp_clk_b "$deps_dir/tech_cells_generic/src/rtl/pulp_clk_cells.sv"
if {[file exists $pulp_clk_a]} {
  add_sv $pulp_clk_a
} elseif {[file exists $pulp_clk_b]} {
  add_sv $pulp_clk_b
} else {
  puts "ERROR: Could not find pulp_clk_cells.sv"
  puts "Tried:"
  puts "  $pulp_clk_a"
  puts "  $pulp_clk_b"
  exit 1
}

# ------------------------------------------------------------
# Add rv_tracer RTL
# ------------------------------------------------------------
add_sv "$rv_tracer_dir/include/te_pkg.sv"
add_sv "$rv_tracer_dir/rtl/te_branch_map.sv"
add_sv "$rv_tracer_dir/rtl/te_filter.sv"
add_sv "$rv_tracer_dir/rtl/te_packet_emitter.sv"
add_sv "$rv_tracer_dir/rtl/lzc.sv"
add_sv "$rv_tracer_dir/rtl/te_priority.sv"
add_sv "$rv_tracer_dir/rtl/te_reg.sv"
add_sv "$rv_tracer_dir/rtl/te_resync_counter.sv"
add_sv "$rv_tracer_dir/rtl/rv_tracer.sv"


# ------------------------------------------------------------
# Add TB (simulation only)
# ------------------------------------------------------------
if {[file exists "$top_dir/tb/tb_rv_tracer_only.sv"]} {
  add_sv_sim "$top_dir/tb/tb_rv_tracer_only.sv"
  set_property top tb_rv_tracer_only [get_filesets sim_1]
} else {
  puts "WARNING: TB not found at $top_dir/tb/tb_rv_tracer_only.sv (skipping sim top)"
}


# ------------------------------------------------------------
# Compile order
# ------------------------------------------------------------
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "============================================================"
puts "rv_tracer-only project imported successfully."
puts "PWD:      [pwd]"
puts "Project:  $proj_name"
puts "Build:    $build_dir"
puts "Part:     $part_name"
puts "============================================================"
