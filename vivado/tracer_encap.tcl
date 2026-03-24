# ============================================================
# tracer_encap.tcl
# Build project for: tracer_encap_top + tb_tracer_encap_top
# ============================================================

set script_dir [file dirname [file normalize [info script]]]
cd [file normalize "$script_dir/.."]

set proj_name "tracer_encap_setup"
set build_dir [file normalize "./vivado_build_encap"]

if {[info exists ::env(PART)] && $::env(PART) ne ""} {
  set part_name $::env(PART)
} else {
  set part_name "xc7a35tcpg236-1"
}

proc must_exist {p} {
  if {![file exists $p]} { puts "ERROR: Missing path: $p"; exit 1 }
}
proc add_sv {p} {
  if {![file exists $p]} { puts "ERROR: Missing SV: $p"; exit 1 }
  add_files -norecurse [file normalize $p]
}
proc add_sv_sim {p} {
  if {![file exists $p]} { puts "ERROR: Missing SIM SV: $p"; exit 1 }
  add_files -fileset sim_1 -norecurse [file normalize $p]
}

set deps_dir        "./deps"
set third_party_dir "./ip/third_party"
set top_dir         "./top_trace"

set rv_tracer_dir   "$third_party_dir/rv_tracer"
set rv_encap_dir    "$third_party_dir/rv_encapsulator"

must_exist $deps_dir
must_exist "$deps_dir/common_cells"
must_exist "$deps_dir/tech_cells_generic"
must_exist $rv_tracer_dir
must_exist $rv_encap_dir
must_exist "$top_dir/rtl"
must_exist "$top_dir/tb"

file mkdir $build_dir
create_project $proj_name $build_dir -part $part_name -force

# include dirs
set inc_list [list \
  [file normalize "$rv_tracer_dir/include"] \
  [file normalize "$rv_encap_dir/src/include"] \
]
set_property include_dirs $inc_list [current_fileset]
set_property include_dirs $inc_list [get_filesets sim_1]

# deps
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
if {[file exists $pulp_clk_a]} { add_sv $pulp_clk_a } elseif {[file exists $pulp_clk_b]} { add_sv $pulp_clk_b } else {
  puts "ERROR: Could not find pulp_clk_cells.sv"; exit 1
}

# rv_tracer
add_sv "$rv_tracer_dir/include/te_pkg.sv"
add_sv "$rv_tracer_dir/rtl/te_branch_map.sv"
add_sv "$rv_tracer_dir/rtl/te_filter.sv"
add_sv "$rv_tracer_dir/rtl/te_packet_emitter.sv"
add_sv "$rv_tracer_dir/rtl/lzc.sv"
add_sv "$rv_tracer_dir/rtl/te_priority.sv"
add_sv "$rv_tracer_dir/rtl/te_reg.sv"
add_sv "$rv_tracer_dir/rtl/te_resync_counter.sv"
add_sv "$rv_tracer_dir/rtl/rv_tracer.sv"

# rv_encapsulator
add_sv "$rv_encap_dir/src/include/encap_pkg.sv"
add_sv "$rv_encap_dir/src/rtl/encapsulator.sv"
add_sv "$rv_encap_dir/src/rtl/atb_transmitter.sv"
add_sv "$rv_encap_dir/src/rtl/slicer.sv"
add_sv "$rv_encap_dir/src/rtl/rv_encapsulator.sv"

# new top
add_sv "$top_dir/rtl/tracer_encap_top.sv"
set_property top tracer_encap_top [current_fileset]

# tb
add_sv_sim "$top_dir/tb/tb_tracer_encap_top.sv"
set_property top tb_tracer_encap_top [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "============================================================"
puts "Tracer+Encapsulator project imported successfully."
puts "PWD:      [pwd]"
puts "Project:  $proj_name"
puts "Build:    $build_dir"
puts "Part:     $part_name"
puts "============================================================"
