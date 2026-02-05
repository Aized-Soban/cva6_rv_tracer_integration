// ============================================================
// tracer_top.sv
// Top-level integration wrapper:
//
//   CVA6 signals -> cva6_te_connector -> rv_tracer -> rv_encapsulator -> ATB
//
// This module is meant to be instantiated by your CVA6 top (later),
// or used standalone in your TB.
// ============================================================

module tracer_top #(
  // Connector parameters
  parameter int unsigned NRET            = 2,   // CVA6 retire width
  parameter int unsigned N               = 1,   // MUST be 1 for this wrapper (encapsulator is single-lane)
  parameter int unsigned FIFO_DEPTH      = 16,  // connector internal fifos

  // rv_tracer parameters
  parameter int unsigned ONLY_BRANCHES   = 0,
  parameter int unsigned APB_ADDR_WIDTH  = 32,

  // Encapsulator parameters
  parameter int unsigned DATA_LEN        = 32,
  parameter int unsigned ENCAP_FIFO_DEPTH= 16
)(
  // ----------------------------
  // Clock / Reset
  // ----------------------------
  input  logic                                    clk_i,
  input  logic                                    rst_ni,

  // ============================================================
  // 1) Inputs from CPU (CVA6) into cva6_te_connector
  // ============================================================
  input  logic [NRET-1:0]                         cpu_valid_i,
  input  logic [NRET-1:0][connector_pkg::XLEN-1:0] cpu_pc_i,
  input  connector_pkg::fu_op [NRET-1:0]          cpu_op_i,
  input  logic [NRET-1:0]                         cpu_is_compressed_i,

  input  logic                                    cpu_branch_valid_i,
  input  logic                                    cpu_is_taken_i,
  input  connector_pkg::cf_t                      cpu_cf_type_i,
  input  logic [connector_pkg::XLEN-1:0]          cpu_disc_pc_i,

  input  logic                                    cpu_ex_valid_i,
  input  logic [connector_pkg::XLEN-1:0]          cpu_tval_i,
  input  logic [connector_pkg::XLEN-1:0]          cpu_cause_i,
  input  logic [connector_pkg::PRIV_LEN-1:0]      cpu_priv_lvl_i,

  // ============================================================
  // 2) Extra rv_tracer context inputs (typically from CPU/CSR side)
  // ============================================================
  input  logic [te_pkg::TIME_LEN-1:0]             time_i,
  input  logic [te_pkg::XLEN-1:0]                 tvec_i,
  input  logic [te_pkg::XLEN-1:0]                 epc_i,

  // ============================================================
  // 3) APB programming interface into rv_tracer
  // ============================================================
  input  logic [APB_ADDR_WIDTH-1:0]               paddr_i,
  input  logic                                    pwrite_i,
  input  logic                                    psel_i,
  input  logic                                    penable_i,
  input  logic [31:0]                             pwdata_i,
  output logic                                    pready_o,
  output logic [31:0]                             prdata_o,

  // ============================================================
  // 4) ATB-like output interface from rv_encapsulator
  // ============================================================
  input  logic                                    atready_i,
  input  logic                                    afvalid_i,

  output logic [$clog2(DATA_LEN)-4:0]             atbytes_o,
  output logic [DATA_LEN-1:0]                     atdata_o,
  output logic [6:0]                              atid_o,
  output logic                                    atvalid_o,
  output logic                                    afready_o,

  // ============================================================
  // Misc
  // ============================================================
  output logic                                    stall_o
);

  // ------------------------------------------------------------
  // Internal wires: connector -> tracer
  // ------------------------------------------------------------
  logic [N-1:0]                                   te_valid;
  logic [N-1:0][connector_pkg::ITYPE_LEN-1:0]      te_itype;
  logic [connector_pkg::XLEN-1:0]                  te_cause;
  logic [connector_pkg::XLEN-1:0]                  te_tval;
  logic [connector_pkg::PRIV_LEN-1:0]              te_priv;
  logic [N-1:0][connector_pkg::XLEN-1:0]           te_iaddr;
  logic [N-1:0][connector_pkg::IRETIRE_LEN-1:0]    te_iretire;
  logic [N-1:0]                                   te_ilastsize;

  // ------------------------------------------------------------
  // Internal wires: tracer -> encapsulator
  // ------------------------------------------------------------
  logic [N-1:0]                                   pkt_valid;
  te_pkg::it_packet_type_e [N-1:0]                pkt_type;
  logic [N-1:0][te_pkg::P_LEN-1:0]                pkt_length;
  logic [N-1:0][te_pkg::PAYLOAD_LEN-1:0]          pkt_payload;

  logic                                           encap_ready;  // from encapsulator to tracer

  // ------------------------------------------------------------
  // 1) cva6_te_connector
  // ------------------------------------------------------------
  cva6_te_connector #(
    .NRET       ( NRET       ),
    .N          ( N          ),
    .FIFO_DEPTH ( FIFO_DEPTH )
  ) i_cva6_te_connector (
    .clk_i            ( clk_i              ),
    .rst_ni           ( rst_ni             ),

    .valid_i          ( cpu_valid_i        ),
    .pc_i             ( cpu_pc_i           ),
    .op_i             ( cpu_op_i           ),
    .is_compressed_i  ( cpu_is_compressed_i),

    .branch_valid_i   ( cpu_branch_valid_i ),
    .is_taken_i       ( cpu_is_taken_i     ),
    .cf_type_i        ( cpu_cf_type_i      ),
    .disc_pc_i        ( cpu_disc_pc_i      ),

    .ex_valid_i       ( cpu_ex_valid_i     ),
    .tval_i           ( cpu_tval_i         ),
    .cause_i          ( cpu_cause_i        ),
    .priv_lvl_i       ( cpu_priv_lvl_i     ),

    .valid_o          ( te_valid           ),
    .iretire_o        ( te_iretire         ),
    .ilastsize_o      ( te_ilastsize       ),
    .itype_o          ( te_itype           ),
    .cause_o          ( te_cause           ),
    .tval_o           ( te_tval            ),
    .priv_o           ( te_priv            ),
    .iaddr_o          ( te_iaddr           )
  );

  // ------------------------------------------------------------
  // 2) rv_tracer
  // ------------------------------------------------------------
  rv_tracer #(
    .N              ( N              ),
    .ONLY_BRANCHES  ( ONLY_BRANCHES  ),
    .APB_ADDR_WIDTH ( APB_ADDR_WIDTH )
  ) i_rv_tracer (
    .clk_i                ( clk_i         ),
    .rst_ni               ( rst_ni        ),

    .valid_i              ( te_valid      ),
    .itype_i              ( te_itype      ),
    .cause_i              ( te_cause      ),
    .tval_i               ( te_tval       ),
    .priv_i               ( te_priv       ),
    .iaddr_i              ( te_iaddr      ),
    .iretire_i            ( te_iretire    ),
    .ilastsize_i          ( te_ilastsize  ),

    .time_i               ( time_i        ),
    .tvec_i               ( tvec_i        ),
    .epc_i                ( epc_i         ),

    .encapsulator_ready_i ( encap_ready   ),

    .paddr_i              ( paddr_i       ),
    .pwrite_i             ( pwrite_i      ),
    .psel_i               ( psel_i        ),
    .penable_i            ( penable_i     ),
    .pwdata_i             ( pwdata_i      ),
    .pready_o             ( pready_o      ),
    .prdata_o             ( prdata_o      ),

    .packet_valid_o       ( pkt_valid     ),
    .packet_type_o        ( pkt_type      ),
    .packet_length_o      ( pkt_length    ),
    .packet_payload_o     ( pkt_payload   ),

    .stall_o              ( stall_o       )
  );

  // ------------------------------------------------------------
  // 3) rv_encapsulator
  //
  // NOTE:
  // - Encapsulator is single-lane, so we use lane [0]
  // - It expects: valid, packet_length, payload, timestamp, notime
  // - rv_tracer provides packet_type too, but encapsulator does not use it.
  // - For now: notime_i = 1'b0 (timestamp always provided)
  // - timestamp_i = time_i (cast to encap_pkg::T_LEN)
  // ------------------------------------------------------------
  rv_encapsulator #(
    .DATA_LEN    ( DATA_LEN        ),
    .FIFO_DEPTH  ( ENCAP_FIFO_DEPTH )
  ) i_rv_encapsulator (
    .clk_i              ( clk_i ),
    .rst_ni             ( rst_ni ),

    .valid_i            ( pkt_valid[0] ),
    .packet_length_i    ( pkt_length[0] ),
    .notime_i           ( 1'b0 ),
    .timestamp_i        ( encap_pkg::T_LEN'(time_i) ),
    .trace_payload_i    ( pkt_payload[0] ),

    .atready_i          ( atready_i ),
    .afvalid_i          ( afvalid_i ),

    .atbytes_o          ( atbytes_o ),
    .atdata_o           ( atdata_o  ),
    .atid_o             ( atid_o    ),
    .atvalid_o          ( atvalid_o ),
    .afready_o          ( afready_o ),

    .encapsulator_ready_o ( encap_ready )
  );

  // Safety: this wrapper is intended for N=1
  // (You can remove this if you later generalize it.)
  initial begin
    if (N != 1) begin
      $error("tracer_top: This wrapper assumes N==1 (single lane). Got N=%0d", N);
    end
  end

endmodule
