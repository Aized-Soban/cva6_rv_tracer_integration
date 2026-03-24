# ============================================================
# integrate_cva6_tracer.tcl
#
# One Vivado project that includes:
#   - CVA6 RTL (same style as run_synth.tcl)
#   - tracer RTL (same files as tracer.tcl)
#   - integration wrapper (cva6_wrapper.sv)
#
# DOES NOT edit run_synth.tcl or tracer.tcl
# ============================================================

# ------------------------------------------------------------
# Work from repo root (this file is in vivado/)
# ------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
cd [file normalize "$script_dir/.."]

# ------------------------------------------------------------
# PART selection (prefer env override)
# ------------------------------------------------------------
if {[info exists ::env(PART)] && $::env(PART) ne ""} {
  set PART $::env(PART)
} else {
  # default used by your run_synth.tcl
  set PART "xc7z020clg400-1"
}

# ------------------------------------------------------------
# Create ONE project (integration owns the project)
# ------------------------------------------------------------
set PROJ_NAME "cva6_tracer_integration"
set BUILD_DIR [file normalize "./vivado_build_cva6_tracer"]

catch { close_project }
file mkdir $BUILD_DIR
create_project $PROJ_NAME $BUILD_DIR -part $PART -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# ============================================================
# 1) CVA6 SECTION (copied logic from run_synth.tcl, adapted paths)
# ============================================================

set TARGET_CFG "cv64a6_imafdc_sv39"

# repo root contains cva6/
############
# set CVA6_ROOT [file normalize "./cva6"]
############
# script_dir = .../vivado (or wherever this script lives)
# repo root   = one level above it
set repo_root [file normalize "$script_dir/.."]
set CVA6_ROOT [file normalize "$repo_root/cva6"]

############


set ::CVA6_ROOT     $CVA6_ROOT
set ::CVA6_REPO_DIR $CVA6_ROOT
set ::TARGET_CFG    $TARGET_CFG
set ::HPDCACHE_DIR  "$CVA6_ROOT/core/cache_subsystem/hpdcache"

set INC_DIRS {}
set DEFINES  {}
set RTL_FILES {}

proc parse_flist {flist_path base_dir} {
  upvar INC_DIRS INC_DIRS
  upvar DEFINES DEFINES
  upvar RTL_FILES RTL_FILES

  if {![file exists $flist_path]} { error "Flist not found: $flist_path" }

  set fp [open $flist_path r]
  while {[gets $fp line] >= 0} {
    set line [string trim $line]
    if {$line eq ""} continue
    if {[string match "//*" $line]} continue
    if {[string match "#*"  $line]} continue

    set line [string map [list \
      "\$CVA6_ROOT"         $::CVA6_ROOT \
      "\${CVA6_REPO_DIR}"   $::CVA6_REPO_DIR \
      "\${TARGET_CFG}"      $::TARGET_CFG \
      "\${HPDCACHE_DIR}"    $::HPDCACHE_DIR \
    ] $line]

    if {[string match "+incdir+*" $line]} {
      set dir [string range $line 8 end]
      set dir [file normalize [file join $base_dir $dir]]
      lappend INC_DIRS $dir
      continue
    }

    if {[string match "+define+*" $line]} {
      set def [string range $line 8 end]
      lappend DEFINES $def
      continue
    }

    if {[string match "-f *" $line]} {
      set subf [string trim [string range $line 2 end]]
      set subf [file normalize [file join $base_dir $subf]]
      if {[file exists $subf]} {
        parse_flist $subf [file dirname $subf]
      } else {
        puts "NOTE: nested flist not found (skipped): $subf"
      }
      continue
    }

    if {[regexp {(\.sv|\.v|\.svh)$} $line]} {
      set f [file normalize [file join $base_dir $line]]
      if {[file exists $f]} {
        lappend RTL_FILES $f
      } else {
        puts "NOTE: RTL file not found (skipped): $f"
      }
      continue
    }
  }
  close $fp
}

# Parse CVA6 flist (same file run_synth.tcl uses)
set flist_main [file normalize "$CVA6_ROOT/core/Flist.cva6"]
parse_flist $flist_main [file normalize "$CVA6_ROOT/core"]

# Force include dirs (same intent as run_synth.tcl)
lappend INC_DIRS [file normalize "$::HPDCACHE_DIR/rtl/include"]
lappend INC_DIRS [file normalize "$CVA6_ROOT/core/include"]
lappend INC_DIRS [file normalize "$CVA6_ROOT/common/local/util"]

# ============================================================
# 2) TRACER SECTION (copied file list from tracer.tcl)
# ============================================================

set deps_dir        "./deps"
set third_party_dir "./ip/third_party"
set top_dir         "./top_trace"

set rv_tracer_dir   "$third_party_dir/rv_tracer"
set rv_encap_dir    "$third_party_dir/rv_encapsulator"
set conn_dir        "$third_party_dir/cva6_te_connector"

# tracer include dirs (from tracer.tcl)
set tracer_inc_list [list \
  [file normalize "$rv_tracer_dir/include"] \
  [file normalize "$rv_encap_dir/src/include"] \
  [file normalize "$conn_dir/src/include"] \
]

# Combine include dirs: CVA6 + tracer
set all_inc_dirs [concat $INC_DIRS $tracer_inc_list]
set all_inc_dirs [lsort -unique $all_inc_dirs]

# Apply include dirs and defines ONCE
set_property include_dirs   $all_inc_dirs [current_fileset]
set_property verilog_define $DEFINES      [current_fileset]

# ============================================================
# 3) CVA6 STRICT COMPILE ORDER (copied behavior from run_synth.tcl)
# ============================================================

# ---- FPGA support RTL (SyncSpRamBeNx64 etc.) ----
# We force any SyncSpRam* files to be read BEFORE the wrapper.
set FPGA_MACROS {}
foreach f $RTL_FILES {
  if {[string match "*SyncSpRam*.sv" $f] || [string match "*SyncSpRam*.v" $f]} {
    lappend FPGA_MACROS $f
  }
}
set FPGA_MACROS [lsort -unique $FPGA_MACROS]
puts "INFO: FPGA macros matching SyncSpRam*: [llength $FPGA_MACROS]"

# Force FPGA version of tc_sram_wrapper
set FPGA_SRAM_WRAPPER [file normalize "$CVA6_ROOT/common/local/util/tc_sram_fpga_wrapper.sv"]

# Remove ASIC wrappers (avoid duplicates) — same intent as run_synth.tcl
set RTL_FILES_FILTERED {}
foreach f $RTL_FILES {
  if {[string match "*common/local/util/tc_sram_wrapper.sv" $f] ||
      [string match "*common/local/util/tc_sram_wrapper_cache_techno.sv" $f]} {
    continue
  }
  lappend RTL_FILES_FILTERED $f
}
set RTL_FILES $RTL_FILES_FILTERED

# Build "EARLY_FILES" list: SyncSpRam + FPGA wrapper + (any key packages already in list)
set EARLY_FILES {}
foreach f $FPGA_MACROS { lappend EARLY_FILES $f }
if {[file exists $FPGA_SRAM_WRAPPER]} {
  lappend EARLY_FILES $FPGA_SRAM_WRAPPER
}

set EARLY_FILES [lsort -unique $EARLY_FILES]

# Separate packages vs non-packages, while keeping early files first
set PKG_REST {}
foreach f $RTL_FILES {
  # crude but effective: treat files containing "_pkg" or "/pkg/" or "package" as package files
  if {[string match "*_pkg.sv" $f] || [string match "*/pkg/*" $f]} {
    if {[lsearch -exact $EARLY_FILES $f] < 0} { lappend PKG_REST $f }
  }
}
set PKG_REST [lsort -unique $PKG_REST]

set RTL_NO_PKG {}
foreach f $RTL_FILES {
  if {[lsearch -exact $EARLY_FILES $f] < 0 && [lsearch -exact $PKG_REST $f] < 0} {
    lappend RTL_NO_PKG $f
  }
}
set RTL_NO_PKG [lsort -unique $RTL_NO_PKG]

puts "EARLY_FILES : [llength $EARLY_FILES]"
puts "PKG(rest)   : [llength $PKG_REST]"
puts "RTL(no pkg) : [llength $RTL_NO_PKG]"

# Actually read CVA6 in strict order (like run_synth.tcl style)
if {[llength $EARLY_FILES] > 0} {
  foreach f $EARLY_FILES {
    if {[file exists $f]} {
      read_verilog -sv $f
    }
  }
}
if {[llength $PKG_REST] > 0} {
  read_verilog -sv $PKG_REST
}
if {[llength $RTL_NO_PKG] > 0} {
  read_verilog -sv $RTL_NO_PKG
}

# ============================================================
# 4) TRACER FILES (same order as tracer.tcl add_sv list)
# ============================================================

# deps/common_cells
read_verilog -sv [file normalize "$deps_dir/common_cells/src/fifo_v3.sv"]
read_verilog -sv [file normalize "$deps_dir/common_cells/src/delta_counter.sv"]
read_verilog -sv [file normalize "$deps_dir/common_cells/src/cf_math_pkg.sv"]
read_verilog -sv [file normalize "$deps_dir/common_cells/src/counter.sv"]
read_verilog -sv [file normalize "$deps_dir/common_cells/src/sync.sv"]
read_verilog -sv [file normalize "$deps_dir/common_cells/src/sync_wedge.sv"]
read_verilog -sv [file normalize "$deps_dir/common_cells/src/edge_detect.sv"]

# tech_cells_generic
read_verilog -sv [file normalize "$deps_dir/tech_cells_generic/src/rtl/tc_clk.sv"]

# connector + tracer + encapsulator (packages first)
read_verilog -sv [file normalize "$conn_dir/src/include/connector_pkg.sv"]

read_verilog -sv [file normalize "$rv_tracer_dir/include/te_pkg.sv"]
read_verilog -sv [file normalize "$rv_encap_dir/src/include/encap_pkg.sv"]

# connector RTL
read_verilog -sv [file normalize "$conn_dir/src/rtl/itype_detector.sv"]
read_verilog -sv [file normalize "$conn_dir/src/rtl/fsm.sv"]
read_verilog -sv [file normalize "$conn_dir/src/rtl/cva6_te_connector.sv"]

# rv_tracer RTL
read_verilog -sv [file normalize "$rv_tracer_dir/rtl/te_branch_map.sv"]
read_verilog -sv [file normalize "$rv_tracer_dir/rtl/te_filter.sv"]
read_verilog -sv [file normalize "$rv_tracer_dir/rtl/te_packet_emitter.sv"]
read_verilog -sv [file normalize "$rv_tracer_dir/rtl/lzc.sv"]
read_verilog -sv [file normalize "$rv_tracer_dir/rtl/te_priority.sv"]
read_verilog -sv [file normalize "$rv_tracer_dir/rtl/te_reg.sv"]
read_verilog -sv [file normalize "$rv_tracer_dir/rtl/te_resync_counter.sv"]
read_verilog -sv [file normalize "$rv_tracer_dir/rtl/rv_tracer.sv"]

# encapsulator RTL
read_verilog -sv [file normalize "$rv_encap_dir/src/rtl/encapsulator.sv"]
read_verilog -sv [file normalize "$rv_encap_dir/src/rtl/atb_transmitter.sv"]
read_verilog -sv [file normalize "$rv_encap_dir/src/rtl/slicer.sv"]
read_verilog -sv [file normalize "$rv_encap_dir/src/rtl/rv_encapsulator.sv"]

# tracer_top
read_verilog -sv [file normalize "$top_dir/rtl/tracer_top.sv"]

# ============================================================
# 5) YOUR WRAPPER (connects cva6_core <-> tracer_top)
# ============================================================

read_verilog -sv [file normalize "./integration/rtl/cva6_wrapper.sv"]

# ============================================================
# 6) SET TOP
# ============================================================

set_property top cva6_wrapper [current_fileset]

puts "INFO: Integration project created: $BUILD_DIR"
puts "INFO: Top set to: cva6_wrapper"
