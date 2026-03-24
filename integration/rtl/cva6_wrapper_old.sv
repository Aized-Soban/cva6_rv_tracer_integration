`include "cvxif_types.svh"
import noc_axi_types_pkg::*;
module cva6_wrapper #(
  parameter config_pkg::cva6_cfg_t CVA6Cfg =
    build_config_pkg::build_config(cva6_config_pkg::cva6_cfg),

  // Exception type consistent with CVA6 instantiation in your repo
  parameter type exception_t = struct packed {
    logic [CVA6Cfg.XLEN-1:0] cause;
    logic [CVA6Cfg.XLEN-1:0] tval;
    logic                    valid;
  }
)(
  // -----------------------
  // Clock / Reset
  // -----------------------
  input  logic                   clk_i,
  input  logic                   rst_ni,

  // -----------------------
  // Boot / Identity
  // -----------------------
  input  logic [CVA6Cfg.VLEN-1:0] boot_addr_i,
  input  logic [CVA6Cfg.XLEN-1:0] hart_id_i,

  // -----------------------
  // External AXI/NoC master
  // -----------------------
  output noc_req_t               noc_req_o,
  input  noc_resp_t              noc_resp_i,

  // ============================================================
  // ONLY signals that go into tracer_top
  // ============================================================

  // Commit bundle
  output logic [CVA6Cfg.NrCommitPorts-1:0]                     cpu_valid_o,
  output logic [CVA6Cfg.NrCommitPorts-1:0][CVA6Cfg.XLEN-1:0]   cpu_pc_o,
  output connector_pkg::fu_op [CVA6Cfg.NrCommitPorts-1:0]      cpu_op_o,
  output logic [CVA6Cfg.NrCommitPorts-1:0]                     cpu_is_compressed_o,

  // Branch resolve
  output logic                                                  cpu_branch_valid_o,
  output logic                                                  cpu_is_taken_o,
  output ariane_pkg::cf_t cpu_cf_type_o,   // (replace cf_t with the actual enum name in ariane_pkg)
  //output logic [$bits(bp_resolve_t::cf_type)-1:0]              cpu_cf_type_o,
  output logic [CVA6Cfg.XLEN-1:0]                              cpu_disc_pc_o,

  // Exception commit
  output logic                                                  cpu_ex_valid_o,
  output logic [CVA6Cfg.XLEN-1:0]                              cpu_tval_o,
  output logic [CVA6Cfg.XLEN-1:0]                              cpu_cause_o,
  output logic [connector_pkg::PRIV_LEN-1:0]                   cpu_priv_lvl_o
);

  localparam int unsigned NRET = CVA6Cfg.NrCommitPorts;

  // -----------------------
  // Internal raw taps
  // -----------------------
  riscv::priv_lvl_t                               priv_lvl_int;
  exception_t                                     ex_commit_int;
  bp_resolve_t                                    resolved_branch_int;
  logic [NRET-1:0]                                commit_ack_int;
  scoreboard_entry_t [NRET-1:0]                   commit_instr_int;

  // -----------------------
  // Hardwired defaults (no-use case)
  // -----------------------
  logic [1:0] irq_tied       = 2'b00;
  logic       ipi_tied       = 1'b0;
  logic       time_irq_tied  = 1'b0;
  logic       debug_req_tied = 1'b0;

  // CVXIF tied off
  cvxif_resp_t cvxif_resp_tied = '0;
  cvxif_req_t  cvxif_req_unused;

  // -----------------------
  // CVA6 instance
  // -----------------------
  cva6 #(
    .CVA6Cfg(CVA6Cfg),
    .exception_t(exception_t)
  ) i_cva6 (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .boot_addr_i  (boot_addr_i),
    .hart_id_i    (hart_id_i),

    .irq_i        (irq_tied),
    .ipi_i        (ipi_tied),
    .time_irq_i   (time_irq_tied),
    .debug_req_i  (debug_req_tied),

    // ignore RVFI if present in your build
    .rvfi_probes_o(),

    // CVXIF not used
    .cvxif_req_o  (cvxif_req_unused),
    .cvxif_resp_i (cvxif_resp_tied),

    // memory interface
    .noc_req_o    (noc_req_o),
    .noc_resp_i   (noc_resp_i),

    // raw trace taps (INTERNAL)
    .priv_lvl_o        (priv_lvl_int),
    .ex_commit_o       (ex_commit_int),
    .resolved_branch_o (resolved_branch_int),
    .commit_ack_o      (commit_ack_int),
    .commit_instr_o    (commit_instr_int)
  );

  // -----------------------
  // Derivations for tracer_top inputs
  // -----------------------

  // Commit-related
  assign cpu_valid_o = commit_ack_int;

  for (genvar i = 0; i < NRET; i++) begin : gen_commit_to_tracer
    assign cpu_pc_o[i]            = commit_instr_int[i].pc;
    assign cpu_op_o[i]            = connector_pkg::fu_op'(commit_instr_int[i].op);
    assign cpu_is_compressed_o[i] = commit_instr_int[i].is_compressed;
  end

  // Branch-related
  assign cpu_branch_valid_o = resolved_branch_int.valid;
  assign cpu_is_taken_o     = resolved_branch_int.is_taken;
  assign cpu_cf_type_o      = resolved_branch_int.cf_type;
  assign cpu_disc_pc_o      = resolved_branch_int.pc;

  // Exception-related
  assign cpu_ex_valid_o   = ex_commit_int.valid;
  assign cpu_tval_o       = ex_commit_int.tval;
  assign cpu_cause_o      = ex_commit_int.cause;
  assign cpu_priv_lvl_o   = logic'(priv_lvl_int);

endmodule
