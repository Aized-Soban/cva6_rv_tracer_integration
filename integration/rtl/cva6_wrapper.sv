// axi_ariane_req --> axi_master_connect --> cva6_axi_bus --> axi2mem --> sram --> back.

`include "cvxif_types.svh"
`include "rvfi_types.svh"
module cva6_wrapper #(
  parameter config_pkg::cva6_cfg_t CVA6Cfg =
    build_config_pkg::build_config(cva6_config_pkg::cva6_cfg),

  // Keep these as parameters (types), do NOT typedef here
  parameter type rvfi_instr_t    = `RVFI_INSTR_T(CVA6Cfg),
  parameter type rvfi_csr_elmt_t = `RVFI_CSR_ELMT_T(CVA6Cfg),
  parameter type rvfi_csr_t      = `RVFI_CSR_T(CVA6Cfg, rvfi_csr_elmt_t),

  parameter type rvfi_probes_instr_t = `RVFI_PROBES_INSTR_T(CVA6Cfg),
  parameter type rvfi_probes_csr_t   = `RVFI_PROBES_CSR_T(CVA6Cfg),
  parameter type rvfi_probes_t       = struct packed {
    rvfi_probes_csr_t   csr;
    rvfi_probes_instr_t instr;
  },
  parameter type rvfi_to_iti_t       = `RVFI_TO_ITI_T(CVA6Cfg),

  parameter int unsigned AXI_USER_EN = 0,
  parameter int unsigned NUM_WORDS   = 2**25
)(
  input  logic clk_i,
  input  logic rst_ni,
  input  logic [CVA6Cfg.XLEN-1:0] boot_addr_i,

  output logic [31:0] tb_exit_o,
  // Use the *type parameters* here
  output rvfi_instr_t [CVA6Cfg.NrCommitPorts-1:0] rvfi_o,
  output rvfi_csr_t                               rvfi_csr_o
);

  ariane_axi::req_t    axi_ariane_req;
  ariane_axi::resp_t   axi_ariane_resp;

  rvfi_instr_t [CVA6Cfg.NrCommitPorts-1:0]  rvfi_instr;
  rvfi_probes_t rvfi_probes;
  rvfi_to_iti_t rvfi_to_iti;
  rvfi_csr_t rvfi_csr;
  assign rvfi_o = rvfi_instr;
  assign rvfi_csr_o = rvfi_csr;

  cvxif_req_t  cvxif_req;
  cvxif_resp_t cvxif_resp;

  cva6 #(
     .CVA6Cfg ( CVA6Cfg ),
     .rvfi_probes_instr_t  ( rvfi_probes_instr_t ),
     .rvfi_probes_csr_t    ( rvfi_probes_csr_t   ),
     .rvfi_probes_t        ( rvfi_probes_t       )
   ) i_cva6 (
    .clk_i                ( clk_i                        ),
    .rst_ni               ( rst_ni                       ),
    .boot_addr_i          ( boot_addr_i                  ),//Driving the boot_addr value from the core control agent
    .hart_id_i            ( '0                           ),
    .irq_i                ( '0                           ),
    .ipi_i                ( 1'b0                         ),
    .time_irq_i           ( '0                           ),
    .debug_req_i          ( 1'b0                         ),
    .rvfi_probes_o        ( rvfi_probes                  ),
    .cvxif_req_o          ( cvxif_req                    ),
    .cvxif_resp_i         ( cvxif_resp                   ),
    .noc_req_o            ( axi_ariane_req               ),
    .noc_resp_i           ( axi_ariane_resp              )
  );

  //----------------------------------------------------------------------------
  // RVFI
  //----------------------------------------------------------------------------

  cva6_rvfi #(
      .CVA6Cfg   (CVA6Cfg),
      .rvfi_instr_t(rvfi_instr_t),
      .rvfi_csr_t(rvfi_csr_t),
      .rvfi_probes_instr_t(rvfi_probes_instr_t),
      .rvfi_probes_csr_t(rvfi_probes_csr_t),
      .rvfi_probes_t(rvfi_probes_t),
      .rvfi_to_iti_t(rvfi_to_iti_t)
  ) i_cva6_rvfi (
      .clk_i     (clk_i),
      .rst_ni    (rst_ni),
      .rvfi_probes_i(rvfi_probes),
      .rvfi_instr_o(rvfi_instr), //   Full architectural commit trace
      .rvfi_to_iti_o   (rvfi_to_iti), // Instruction-flow trace (lighter weight)
      .rvfi_csr_o(rvfi_csr)  // CSR/state trace

  );


  rvfi_tracer  #(
    .CVA6Cfg(CVA6Cfg),
    .rvfi_instr_t(rvfi_instr_t),
    .rvfi_csr_t(rvfi_csr_t),
    //
    .HART_ID(8'h0),
    .DEBUG_START(0),
    .DEBUG_STOP(0)
  ) i_rvfi_tracer (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .rvfi_i(rvfi_instr),
    .rvfi_csr_i(rvfi_csr),
    .end_of_test_o(tb_exit_o)
  ) ;

  //----------------------------------------------------------------------------
  // Memory
  //----------------------------------------------------------------------------

  logic                         req;
  logic                         we;
  logic [CVA6Cfg.AxiAddrWidth-1:0] addr;
  logic [CVA6Cfg.AxiDataWidth/8-1:0]  be;
  logic [CVA6Cfg.AxiDataWidth-1:0]    wdata;
  logic [CVA6Cfg.AxiUserWidth-1:0]    wuser;
  logic [CVA6Cfg.AxiDataWidth-1:0]    rdata;
  logic [CVA6Cfg.AxiUserWidth-1:0]    ruser;

  //Response structs
   assign axi_ariane_resp.aw_ready = cva6_axi_bus.aw_ready;
   assign axi_ariane_resp.ar_ready = cva6_axi_bus.ar_ready;
   assign axi_ariane_resp.w_ready  = cva6_axi_bus.w_ready;
   assign axi_ariane_resp.b_valid  = cva6_axi_bus.b_valid;
   assign axi_ariane_resp.r_valid  = cva6_axi_bus.r_valid;
   // B Channel
   assign axi_ariane_resp.b.id   = cva6_axi_bus.b_id;
   assign axi_ariane_resp.b.resp = cva6_axi_bus.b_resp;
   assign axi_ariane_resp.b.user = cva6_axi_bus.b_user;
   // R Channel
   assign axi_ariane_resp.r.id   =  cva6_axi_bus.r_id;
   assign axi_ariane_resp.r.data =  cva6_axi_bus.r_data;
   assign axi_ariane_resp.r.resp =  cva6_axi_bus.r_resp;
   assign axi_ariane_resp.r.last =  cva6_axi_bus.r_last;
   assign axi_ariane_resp.r.user =  cva6_axi_bus.r_user;

  AXI_BUS #(
    .AXI_ADDR_WIDTH ( CVA6Cfg.AxiAddrWidth         ),
    .AXI_DATA_WIDTH ( CVA6Cfg.AxiDataWidth         ),
    .AXI_ID_WIDTH   ( ariane_axi_soc::IdWidthSlave ),
    .AXI_USER_WIDTH ( CVA6Cfg.AxiUserWidth         )
  ) cva6_axi_bus();

  axi_master_connect #(
  ) i_axi_master_connect_cva6_to_mem (
    .axi_req_i  (axi_ariane_req),
    .dis_mem    ('0),
    .master     (cva6_axi_bus)
  );

  axi2mem #(
    .AXI_ID_WIDTH   ( ariane_axi_soc::IdWidthSlave ),
    .AXI_ADDR_WIDTH ( CVA6Cfg.AxiAddrWidth         ),
    .AXI_DATA_WIDTH ( CVA6Cfg.AxiDataWidth         ),
    .AXI_USER_WIDTH ( CVA6Cfg.AxiUserWidth         )
  ) i_cva6_axi2mem (
    .clk_i  ( clk_i       ),
    .rst_ni ( rst_ni      ),
    .slave  ( cva6_axi_bus ),
    .req_o  ( req          ),
    .we_o   ( we           ),
    .addr_o ( addr         ),
    .be_o   ( be           ),
    .user_o ( wuser        ),
    .data_o ( wdata        ),
    .user_i ( ruser        ),
    .data_i ( rdata        )
  );

  sram #(
    .USER_WIDTH ( CVA6Cfg.AxiUserWidth ),
    .DATA_WIDTH ( CVA6Cfg.AxiDataWidth ),
    .USER_EN    ( AXI_USER_EN    ),
    .SIM_INIT   ( "zeros"        ),
    .NUM_WORDS  ( NUM_WORDS      )
  ) i_sram (
    .clk_i      ( clk_i                                                                       ),
    .rst_ni     ( rst_ni                                                                      ),
    .req_i      ( req                                                                         ),
    .we_i       ( we                                                                          ),
    .addr_i     ( addr[$clog2(NUM_WORDS)-1+$clog2(CVA6Cfg.AxiDataWidth/8):$clog2(CVA6Cfg.AxiDataWidth/8)] ),
    .wuser_i    ( wuser                                                                       ),
    .wdata_i    ( wdata                                                                       ),
    .be_i       ( be                                                                          ),
    .ruser_o    ( ruser                                                                       ),
    .rdata_o    ( rdata                                                                       )
  );



  // block for handling cvxif
  always_comb begin
  cvxif_resp = '0;

  // Never stall the core on CVXIF handshakes
  cvxif_resp.compressed_ready      = 1'b1;
  cvxif_resp.compressed_resp.accept= 1'b0;
  cvxif_resp.compressed_resp.instr = 32'b0;

  cvxif_resp.issue_ready           = 1'b1;
  cvxif_resp.issue_resp.accept     = 1'b0;
  cvxif_resp.issue_resp.writeback  = '0;
  cvxif_resp.issue_resp.register_read = '0;

  cvxif_resp.register_ready        = 1'b1;

  // Never return results
  cvxif_resp.result_valid          = 1'b0;
  cvxif_resp.result                = '0;
end






endmodule
