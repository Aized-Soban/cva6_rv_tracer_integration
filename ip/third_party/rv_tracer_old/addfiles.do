project new . rv_tracer
project addfile .bender/git/checkouts/common_cells-186fa784a0cf8091/src/counter.sv
project addfile .bender/git/checkouts/common_cells-186fa784a0cf8091/src/cf_math_pkg.sv
project addfile .bender/git/checkouts/common_cells-186fa784a0cf8091/src/sync.sv
project addfile .bender/git/checkouts/common_cells-186fa784a0cf8091/src/sync_wedge.sv
project addfile .bender/git/checkouts/common_cells-186fa784a0cf8091/src/edge_detect.sv
project addfile .bender/git/checkouts/tech_cells_generic-fa17af1d6ab1fe36/src/rtl/tc_clk.sv
project addfile .bender/git/checkouts/tech_cells_generic-fa17af1d6ab1fe36/src/deprecated/pulp_clk_cells.sv
project addfile include/te_pkg.sv
project addfile rtl/te_branch_map.sv
project addfile rtl/te_filter.sv
project addfile rtl/te_packet_emitter.sv
project addfile rtl/lzc.sv
project addfile rtl/te_priority.sv
project addfile rtl/te_reg.sv
project addfile rtl/te_resync_counter.sv
project addfile rtl/rv_tracer.sv
project addfile tb/tb_te_priority.sv
project compileall
vsim -voptargs=+acc work.tb_te_priority
log -r /*
run 200
