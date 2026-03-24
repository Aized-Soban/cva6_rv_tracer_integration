`timescale 1ns/1ps
// ============================================================================
// tracer_top.sv
//
// Reduced-memory wrapper for packet-based connector flow:
//
//   rvfi_to_iti_t packet --> connector --> iti_to_encoder_t packet
//                        --> flatten --> rv_tracer --> rv_encapsulator
//
// Key points:
// - Uses iti_pkg concrete packet types directly
// - No CVA6Cfg parameter
// - No generic type parameters
// - Wrapper stays single-lane toward rv_tracer / rv_encapsulator
// ============================================================================

module Enc_trace_top #(
  parameter int unsigned N                = 1,   // wrapper stays single-lane
  parameter int unsigned ONLY_BRANCHES    = 0,
  parameter int unsigned APB_ADDR_WIDTH   = 32,
  parameter int unsigned DATA_LEN         = 32,
  parameter int unsigned ENCAP_FIFO_DEPTH = 16,
  parameter logic [4:0] HARTID            = 5'd0,
  parameter logic       TRACE_IS_SYSTEM   = 1'b0
)(
  input  logic                         clk_i,
  input  logic                         rst_ni,

  // --------------------------------------------------------------------------
  // New connector packet input
  // --------------------------------------------------------------------------
  input  iti_pkg::rvfi_to_iti_t        rvfi_to_iti_i,

  // --------------------------------------------------------------------------
  // Extra rv_tracer context inputs
  // --------------------------------------------------------------------------
  input  logic [te_pkg::TIME_LEN-1:0]  time_i,
  input  logic [te_pkg::XLEN-1:0]      tvec_i,
  input  logic [te_pkg::XLEN-1:0]      epc_i,

  // --------------------------------------------------------------------------
  // APB programming interface into rv_tracer
  // --------------------------------------------------------------------------
  input  logic [APB_ADDR_WIDTH-1:0]    paddr_i,
  input  logic                         pwrite_i,
  input  logic                         psel_i,
  input  logic                         penable_i,
  input  logic [31:0]                  pwdata_i,
  output logic                         pready_o,
  output logic [31:0]                  prdata_o,

  // --------------------------------------------------------------------------
  // ATB output interface from rv_encapsulator
  // --------------------------------------------------------------------------
  input  logic                         atready_i,
  input  logic                         afvalid_i,

  output logic [$clog2(DATA_LEN)-4:0]  atbytes_o,
  output logic [DATA_LEN-1:0]          atdata_o,
  output logic [6:0]                   atid_o,
  output logic                         atvalid_o,
  output logic                         afready_o,

  // Misc
  output logic                         stall_o
);

  // --------------------------------------------------------------------------
  // Connector -> tracer bridge signals
  // --------------------------------------------------------------------------
  logic [N-1:0]                              te_valid;
  logic [N-1:0][te_pkg::ITYPE_LEN-1:0]       te_itype;
  logic [te_pkg::XLEN-1:0]                   te_cause;
  logic [te_pkg::XLEN-1:0]                   te_tval;
  logic [te_pkg::PRIV_LEN-1:0]               te_priv;
  logic [N-1:0][te_pkg::XLEN-1:0]            te_iaddr;
  logic [N-1:0][te_pkg::IRETIRE_LEN-1:0]     te_iretire;
  logic [N-1:0]                              te_ilastsize;

  // --------------------------------------------------------------------------
  // Tracer -> encapsulator signals
  // --------------------------------------------------------------------------
  logic [N-1:0]                              pkt_valid;
  te_pkg::it_packet_type_e [N-1:0]           pkt_type;
  logic [N-1:0][te_pkg::P_LEN-1:0]           pkt_length;
  logic [N-1:0][te_pkg::PAYLOAD_LEN-1:0]     pkt_payload;

  logic                                      encap_ready;

  // --------------------------------------------------------------------------
  // Connector packet output
  // --------------------------------------------------------------------------
  iti_pkg::iti_to_encoder_t                  iti_pkt;
  logic [iti_pkg::NR_COMMIT_PORTS-1:0]       connector_valid;

  // --------------------------------------------------------------------------
  // Packet-based connector
  //
  // If your concrete connector module is still named cva6_te_connector,
  // change only the module name below.
  // --------------------------------------------------------------------------
  cva6_te_connector u_connector (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .valid_i          (rvfi_to_iti_i.valid),
    .rvfi_to_iti_i    (rvfi_to_iti_i),
    .valid_o          (connector_valid),
    .iti_to_encoder_o (iti_pkt)
  );

  // --------------------------------------------------------------------------
  // Flatten connector packet output into legacy rv_tracer flat inputs.
  //
  // The wrapper remains single-lane (N=1), so only lane [0] is forwarded to
  // rv_tracer / rv_encapsulator. This preserves the previous wrapper behavior.
  // --------------------------------------------------------------------------
  always_comb begin
    te_valid     = '0;
    te_iretire   = '0;
    te_ilastsize = '0;
    te_itype     = '0;
    te_iaddr     = '0;

    te_cause = te_pkg::XLEN'(iti_pkt.cause);
    te_tval  = iti_pkt.tval;
    te_priv  = te_pkg::PRIV_LEN'(iti_pkt.priv);

    te_valid[0]     = iti_pkt.valid[0];
    te_iretire[0]   = te_pkg::IRETIRE_LEN'(iti_pkt.iretire[0]);
    te_ilastsize[0] = iti_pkt.ilastsize[0];
    te_itype[0]     = te_pkg::ITYPE_LEN'(iti_pkt.itype[0]);
    te_iaddr[0]     = iti_pkt.iaddr[0];
  end

  // --------------------------------------------------------------------------
  // rv_tracer
  // --------------------------------------------------------------------------
  rv_tracer #(
    .N              (N),
    .ONLY_BRANCHES  (ONLY_BRANCHES),
    .APB_ADDR_WIDTH (APB_ADDR_WIDTH)
  ) i_rv_tracer (
    .clk_i                (clk_i),
    .rst_ni               (rst_ni),

    .valid_i              (te_valid),
    .itype_i              (te_itype),
    .cause_i              (te_cause),
    .tval_i               (te_tval),
    .priv_i               (te_priv),
    .iaddr_i              (te_iaddr),
    .iretire_i            (te_iretire),
    .ilastsize_i          (te_ilastsize),

    .time_i               (time_i),
    .tvec_i               (tvec_i),
    .epc_i                (epc_i),
    .encapsulator_ready_i (encap_ready),

    .paddr_i              (paddr_i),
    .pwrite_i             (pwrite_i),
    .psel_i               (psel_i),
    .penable_i            (penable_i),
    .pwdata_i             (pwdata_i),
    .pready_o             (pready_o),
    .prdata_o             (prdata_o),

    .packet_valid_o       (pkt_valid),
    .packet_type_o        (pkt_type),
    .packet_length_o      (pkt_length),
    .packet_payload_o     (pkt_payload),

    .stall_o              (stall_o)
  );

  // --------------------------------------------------------------------------
  // rv_encapsulator
  //
  // Encapsulator remains single-lane in this wrapper, so lane [0] is used.
  // --------------------------------------------------------------------------
  logic [6:0] srcid;
  assign srcid = {TRACE_IS_SYSTEM, HARTID, 1'b1};

  rv_encapsulator #(
    .DATA_LEN   (DATA_LEN),
    .FIFO_DEPTH (ENCAP_FIFO_DEPTH)
  ) i_rv_encapsulator (
    .clk_i                (clk_i),
    .rst_ni               (rst_ni),

    .valid_i              (pkt_valid[0]),
    .packet_length_i      (pkt_length[0]),
    .notime_i             (1'b0),
    .srcid_i              (srcid),
    .timestamp_i          (encap_pkg::T_LEN'(time_i)),
    .trace_payload_i      (pkt_payload[0]),

    .atready_i            (atready_i),
    .afvalid_i            (afvalid_i),

    .atbytes_o            (atbytes_o),
    .atdata_o             (atdata_o),
    .atid_o               (atid_o),
    .atvalid_o            (atvalid_o),
    .afready_o            (afready_o),

    .encapsulator_ready_o (encap_ready)
  );

endmodule