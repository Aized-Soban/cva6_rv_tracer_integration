// ============================================================
// cva6_wrapper.sv  (UPDATED for your tracer_top.sv)
// - Instantiates clean cva6_core (NO tracer/connector inside)
// - Extracts connector inputs from commit bundle in wrapper
// - Instantiates tracer_top (connector + tracer + encapsulator)
// ============================================================

`include "rvfi_types.svh"
`include "cvxif_types.svh"

module cva6_wrapper
  import ariane_pkg::*;
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = build_config_pkg::build_config(
        cva6_config_pkg::cva6_cfg
    ),

    parameter type rvfi_probes_instr_t = `RVFI_PROBES_INSTR_T(CVA6Cfg),
    parameter type rvfi_probes_csr_t   = `RVFI_PROBES_CSR_T(CVA6Cfg),
    parameter type rvfi_probes_t = struct packed {
      rvfi_probes_csr_t   csr;
      rvfi_probes_instr_t instr;
    },

    parameter type exception_t = struct packed {
      logic [CVA6Cfg.XLEN-1:0] cause;
      logic [CVA6Cfg.XLEN-1:0] tval;
      logic                    valid;
    },

    // tracer_top params
    parameter int unsigned N               = 1,
    parameter int unsigned FIFO_DEPTH      = 16,
    parameter int unsigned ONLY_BRANCHES   = 0,
    parameter int unsigned APB_ADDR_WIDTH  = 32,
    parameter int unsigned DATA_LEN        = 32,
    parameter int unsigned ENCAP_FIFO_DEPTH= 16
) (
    // --------------------
    // CVA6 external ports
    // --------------------
    input  logic                   clk_i,
    input  logic                   rst_ni,
    input  logic [CVA6Cfg.VLEN-1:0] boot_addr_i,
    input  logic [CVA6Cfg.XLEN-1:0] hart_id_i,
    input  logic [1:0]             irq_i,
    input  logic                   ipi_i,
    input  logic                   time_irq_i,
    input  logic                   debug_req_i,

    output rvfi_probes_t           rvfi_probes_o,

    output cvxif_req_t             cvxif_req_o,
    input  cvxif_resp_t            cvxif_resp_i,

    output noc_req_t               noc_req_o,
    input  noc_resp_t              noc_resp_i,

    // ============================================================
    // tracer_top extra inputs (these are NOT produced by CVA6 here)
    // You can tie them off initially or later export from CVA6 CSR.
    // ============================================================
    input  logic [te_pkg::TIME_LEN-1:0] time_i,
    input  logic [te_pkg::XLEN-1:0]     tvec_i,
    input  logic [te_pkg::XLEN-1:0]     epc_i,

    // APB interface into rv_tracer
    input  logic [APB_ADDR_WIDTH-1:0]   paddr_i,
    input  logic                        pwrite_i,
    input  logic                        psel_i,
    input  logic                        penable_i,
    input  logic [31:0]                 pwdata_i,
    output logic                        pready_o,
    output logic [31:0]                 prdata_o,

    // ATB-like output from encapsulator
    input  logic                        atready_i,
    input  logic                        afvalid_i,

    output logic [$clog2(DATA_LEN)-4:0] atbytes_o,
    output logic [DATA_LEN-1:0]         atdata_o,
    output logic [6:0]                  atid_o,
    output logic                        atvalid_o,
    output logic                        afready_o,

    output logic                        stall_o
);

  // ------------------------------------------------------------
  // Trace taps from CLEAN core
  // ------------------------------------------------------------
  localparam int unsigned NRET = CVA6Cfg.NrCommitPorts;

  riscv::priv_lvl_t                               priv_lvl;
  exception_t                                     ex_commit;
  bp_resolve_t                                    resolved_branch;
  logic             [NRET-1:0]                     commit_ack;
  scoreboard_entry_t [NRET-1:0]                    commit_instr;

  // Clean CVA6 core instance (you must rename clean module to cva6_core
  // and export these trace taps: priv_lvl_o, ex_commit_o, resolved_branch_o,
  // commit_ack_o, commit_instr_o)
  cva6 #(
    .CVA6Cfg(CVA6Cfg),
    .exception_t(exception_t)
  ) i_cva6_core (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .boot_addr_i(boot_addr_i),
    .hart_id_i(hart_id_i),
    .irq_i(irq_i),
    .ipi_i(ipi_i),
    .time_irq_i(time_irq_i),
    .debug_req_i(debug_req_i),

    .rvfi_probes_o(rvfi_probes_o),

    .cvxif_req_o(cvxif_req_o),
    .cvxif_resp_i(cvxif_resp_i),

    .noc_req_o(noc_req_o),
    .noc_resp_i(noc_resp_i),

    // trace taps
    .priv_lvl_o(priv_lvl),
    .ex_commit_o(ex_commit),
    .resolved_branch_o(resolved_branch),
    .commit_ack_o(commit_ack),
    .commit_instr_o(commit_instr)
  );

  ///////////////////////////////////////////////////////////////////////////////////////////
  // --------------------------------------------------
  // TE CONNECTOR SIGNAL EXTRACTION  (MOVED OUT OF CORE)
  // --------------------------------------------------
  ///////////////////////////////////////////////////////////////////////////////////////////
  logic [NRET-1:0][CVA6Cfg.XLEN-1:0] te_pc;
  connector_pkg::fu_op [NRET-1:0]    te_op;
  logic [NRET-1:0]                  te_is_compressed;

  for (genvar i = 0; i < NRET; i++) begin : gen_te_signals
    assign te_pc[i]            = commit_instr[i].pc;
    assign te_op[i]            = connector_pkg::fu_op'(commit_instr[i].op); // cast needed
    assign te_is_compressed[i] = commit_instr[i].is_compressed;
  end

  // IMPORTANT FIX: use final retire valid, not commit_ack_commit_id
  logic [NRET-1:0] te_valid;
  assign te_valid = commit_ack;

  // priv cast to connector width
  logic [connector_pkg::PRIV_LEN-1:0] te_priv_lvl;
  assign te_priv_lvl = logic'(priv_lvl);

  // ------------------------------------------------------------
  // tracer_top instance (PORTS MATCH YOUR tracer_top.sv)
  // ------------------------------------------------------------
  tracer_top #(
    .NRET            (NRET),
    .N               (N),
    .FIFO_DEPTH      (FIFO_DEPTH),
    .ONLY_BRANCHES   (ONLY_BRANCHES),
    .APB_ADDR_WIDTH  (APB_ADDR_WIDTH),
    .DATA_LEN        (DATA_LEN),
    .ENCAP_FIFO_DEPTH(ENCAP_FIFO_DEPTH)
  ) i_tracer_top (
    .clk_i                (clk_i),
    .rst_ni               (rst_ni),

    // 1) CPU -> connector
    .cpu_valid_i          (te_valid),
    .cpu_pc_i             (te_pc),
    .cpu_op_i             (te_op),
    .cpu_is_compressed_i  (te_is_compressed),

    .cpu_branch_valid_i   (resolved_branch.valid),
    .cpu_is_taken_i       (resolved_branch.is_taken),
    .cpu_cf_type_i        (resolved_branch.cf_type),
    .cpu_disc_pc_i        (resolved_branch.pc),

    .cpu_ex_valid_i       (ex_commit.valid),
    .cpu_tval_i           (ex_commit.tval),
    .cpu_cause_i          (ex_commit.cause),
    .cpu_priv_lvl_i       (te_priv_lvl),

    // 2) extra rv_tracer context
    .time_i               (time_i),
    .tvec_i               (tvec_i),
    .epc_i                (epc_i),

    // 3) APB
    .paddr_i              (paddr_i),
    .pwrite_i             (pwrite_i),
    .psel_i               (psel_i),
    .penable_i            (penable_i),
    .pwdata_i             (pwdata_i),
    .pready_o             (pready_o),
    .prdata_o             (prdata_o),

    // 4) ATB
    .atready_i            (atready_i),
    .afvalid_i            (afvalid_i),

    .atbytes_o            (atbytes_o),
    .atdata_o             (atdata_o),
    .atid_o               (atid_o),
    .atvalid_o            (atvalid_o),
    .afready_o            (afready_o),

    // misc
    .stall_o              (stall_o)
  );

endmodule
