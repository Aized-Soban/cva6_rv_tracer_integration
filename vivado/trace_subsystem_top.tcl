# ============================================================
# trace_subsystem_top.tcl
#
# Repo-root relative, robust Vivado import script for the
# integrated trace subsystem top.
#
# Expected repo root:
#   tracer_integration/
#     deps/
#     cva6/
#     ip/
#     atb_funnel/
#     Enc_trace_top/
#     integration/
#     vivado/
#
# Recommended usage:
#   vivado -mode batch -source vivado/trace_subsystem_top.tcl
#   PART=xc7a35tcpg236-1 vivado -mode batch -source vivado/trace_subsystem_top.tcl
# ============================================================

# ------------------------------------------------------------
# Force working directory to repo root (one level above vivado/)
# ------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
cd [file normalize "$script_dir/.."]

set proj_name  "trace_subsystem_setup"
set build_dir  [file normalize "./vivado_build_trace_subsystem"]

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
    puts "ERROR: Missing required SystemVerilog file: $p"
    exit 1
  }
  add_files -norecurse [file normalize $p]
}

proc add_vh_global {p} {
  if {![file exists $p]} {
    puts "ERROR: Missing required header file: $p"
    exit 1
  }
  add_files -norecurse [file normalize $p]
  set f [get_files -of_objects [get_filesets sources_1] [list "*[file normalize $p]"]]
  if {$f ne ""} {
    set_property file_type "Verilog Header" $f
    set_property is_global_include 1 $f
  }
}

proc first_existing_path {paths} {
  foreach p $paths {
    if {[file exists $p]} {
      return [file normalize $p]
    }
  }
  puts "ERROR: None of the candidate paths exist:"
  foreach p $paths {
    puts "  $p"
  }
  exit 1
}

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------
set deps_dir       "./deps"
set cva6_dir       "./cva6"
set ip_dir         "./ip"
set funnel_dir     "./atb_funnel"
set enc_dir        "./Enc_trace_top"
set integ_dir      "./integration"

set trace_top_file [first_existing_path [list \
  "$integ_dir/rtl/trace_subsystem_top.sv" \
  "$integ_dir/trace_subsystem_top.sv" \
  "./trace_subsystem_top.sv" \
]]

set enc_top_file [first_existing_path [list \
  "$enc_dir/rtl/Enc_trace_top.sv" \
  "$enc_dir/Enc_trace_top.sv" \
  "./Enc_trace_top.sv" \
]]

set connector_file [first_existing_path [list \
  "$ip_dir/third_party/ITI/cva6_iti/cva6_te_connector.sv" \
  "$ip_dir/cva6_te_connector.sv" \
  "./cva6_te_connector.sv" \
]]

set rv_tracer_file [first_existing_path [list \
  "$ip_dir/third_party/rv_tracer/rtl/rv_tracer.sv" \
  "$ip_dir/rv_tracer.sv" \
  "./rv_tracer.sv" \
]]

set rv_encap_file [first_existing_path [list \
  "$ip_dir/third_party/rv_encapsulator/src/rtl/rv_encapsulator.sv" \
  "$ip_dir/rv_encapsulator.sv" \
  "./rv_encapsulator.sv" \
]]

# ------------------------------------------------------------
# Sanity checks for repo layout
# ------------------------------------------------------------
must_exist $deps_dir
must_exist "$deps_dir/common_cells"
must_exist "$deps_dir/tech_cells_generic"
must_exist $cva6_dir
must_exist "$cva6_dir/core/include"
must_exist $ip_dir
must_exist $funnel_dir
must_exist "$funnel_dir/rtl"

# ------------------------------------------------------------
# Create project
# ------------------------------------------------------------
file mkdir $build_dir
create_project $proj_name $build_dir -part $part_name -force

set_property simulator_language Mixed [current_project]
set_property default_lib xil_defaultlib [current_project]

# Include dirs for packages / headers
set_property include_dirs [list \
  [file normalize "$cva6_dir/core/include"] \
  [file normalize "$ip_dir/third_party/ITI/include"] \
  [file normalize "$ip_dir/third_party/rv_tracer/include"] \
  [file normalize "$ip_dir/third_party/rv_encapsulator/src/include"] \
] [get_filesets sources_1]

# ------------------------------------------------------------
# Global headers first
# ------------------------------------------------------------
add_vh_global "$cva6_dir/core/include/rvfi_types.svh"
add_vh_global "$ip_dir/third_party/ITI/include/iti_types.svh"

# ------------------------------------------------------------
# Packages / common deps
# ------------------------------------------------------------

add_sv "$deps_dir/common_cells/src/cf_math_pkg.sv"
add_sv "$deps_dir/common_cells/src/delta_counter.sv"
add_sv "$deps_dir/common_cells/src/cdc_2phase.sv"
add_sv "$deps_dir/common_cells/src/cdc_fifo_2phase.sv"
add_sv "$deps_dir/common_cells/src/edge_detect.sv"
add_sv "$deps_dir/common_cells/src/fifo_v3.sv"
add_sv "$deps_dir/common_cells/src/sync.sv"
add_sv "$deps_dir/common_cells/src/sync_wedge.sv"
add_sv "$deps_dir/common_cells/src/pulp_clock_gating.sv"

add_sv "$deps_dir/tech_cells_generic/src/rtl/tc_clk.sv"
add_sv "$deps_dir/tech_cells_generic/src/deprecated/pulp_clk_cells.sv"

# ------------------------------------------------------------
# Encoder trace packages / RTL
# ------------------------------------------------------------
add_sv "$ip_dir/third_party/ITI/include/iti_pkg.sv"
add_sv "$ip_dir/third_party/rv_tracer/include/te_pkg.sv"
add_sv "$ip_dir/third_party/rv_encapsulator/src/include/encap_pkg.sv"

add_sv "$ip_dir/third_party/ITI/cva6_iti/block_retirement.sv"
add_sv "$ip_dir/third_party/ITI/cva6_iti/single_retirement.sv"
add_sv "$ip_dir/third_party/ITI/cva6_iti/itype_detector.sv"
add_sv $connector_file

add_sv "$ip_dir/third_party/rv_tracer/rtl/lzc.sv"
add_sv "$ip_dir/third_party/rv_tracer/rtl/te_branch_map.sv"
add_sv "$ip_dir/third_party/rv_tracer/rtl/te_filter.sv"
add_sv "$ip_dir/third_party/rv_tracer/rtl/te_packet_emitter.sv"
add_sv "$ip_dir/third_party/rv_tracer/rtl/te_priority.sv"
add_sv "$ip_dir/third_party/rv_tracer/rtl/te_resync_counter.sv"
add_sv "$ip_dir/third_party/rv_tracer/rtl/te_reg.sv"
add_sv $rv_tracer_file

add_sv "$ip_dir/third_party/rv_encapsulator/src/rtl/slicer.sv"
add_sv "$ip_dir/third_party/rv_encapsulator/src/rtl/encapsulator.sv"
add_sv "$ip_dir/third_party/rv_encapsulator/src/rtl/atb_transmitter.sv"
add_sv $rv_encap_file

add_sv $enc_top_file

# ------------------------------------------------------------
# Funnel RTL
# ------------------------------------------------------------
add_sv "$funnel_dir/rtl/atb_flush_ctrl.sv"
add_sv "$funnel_dir/rtl/atb_priority_mux.sv"
add_sv "$funnel_dir/rtl/atb_funnel_src_path.sv"
add_sv "$funnel_dir/rtl/atb_funnel_pre_fifo_top.sv"
add_sv "$funnel_dir/rtl/atb_funnel_top.sv"

# ------------------------------------------------------------
# Integrated top
# ------------------------------------------------------------
add_sv $trace_top_file
set_property top trace_subsystem_top [current_fileset]

# ------------------------------------------------------------
# Compile order
# ------------------------------------------------------------
update_compile_order -fileset sources_1

puts "============================================================"
puts "Trace subsystem project imported successfully."
puts "PWD:      [pwd]"
puts "Project:  $proj_name"
puts "Build:    $build_dir"
puts "Part:     $part_name"
puts "RTL top:  trace_subsystem_top"
puts "Top file: $trace_top_file"
puts "============================================================"
