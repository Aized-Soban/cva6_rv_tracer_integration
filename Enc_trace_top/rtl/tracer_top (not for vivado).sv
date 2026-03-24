// tracer_top.sv
//
// Wrapper flow:
//
//   rvfi_to_iti_t packet -> cva6_te_connector -> iti_to_encoder_t packet
//   -> flatten into rv_tracer flat inputs
//
`timescale 1ns/1ps

`include "rvfi_types.svh"
`include "iti_types.svh"

module tracer_top #(
  parameter config_pkg::cva6_cfg_t CVA6Cfg =
    build_config_pkg::build_config(cva6_config_pkg::cva6_cfg),

  // Wrapper / downstream tracer params
  parameter int unsigned N                = 1,   // wrapper stays single-lane
  parameter int unsigned ONLY_BRANCHES    = 0,
  parameter int unsigned APB_ADDR_WIDTH   = 32,

  // Encapsulator params
  parameter int unsigned DATA_LEN         = 32,
  parameter int unsigned ENCAP_FIFO_DEPTH = 16,
  parameter logic [4:0] HARTID            = 5'd0,
  parameter logic       TRACE_IS_SYSTEM   = 1'b0,

  // Struct types passed into / out of connector
  parameter type rvfi_to_iti_t    = logic,
  parameter type iti_to_encoder_t = logic
)(
  input  logic                                    clk_i,
  input  logic                                    rst_ni,

  // connector input: one packed RVFI->ITI packet
  input  rvfi_to_iti_t                            rvfi_to_iti_i,

  // Extra rv_tracer context inputs
  input  logic [te_pkg::TIME_LEN-1:0]             time_i,
  input  logic [te_pkg::XLEN-1:0]                 tvec_i,
  input  logic [te_pkg::XLEN-1:0]                 epc_i,

  // APB programming interface into rv_tracer
  input  logic [APB_ADDR_WIDTH-1:0]               paddr_i,
  input  logic                                    pwrite_i,
  input  logic                                    psel_i,
  input  logic                                    penable_i,
  input  logic [31:0]                             pwdata_i,
  output logic                                    pready_o,
  output logic [31:0]                             prdata_o,

  // ATB output interface from rv_encapsulator
  input  logic                                    atready_i,
  input  logic                                    afvalid_i,

  output logic [$clog2(DATA_LEN)-4:0]             atbytes_o,
  output logic [DATA_LEN-1:0]                     atdata_o,
  output logic [6:0]                              atid_o,
  output logic                                    atvalid_o,
  output logic                                    afready_o,

  // Misc
  output logic                                    stall_o
);

  // Internal wires: connector -> tracer
  logic [N-1:0]                                    te_valid;
  logic [N-1:0][te_pkg::ITYPE_LEN-1:0]      te_itype;
  logic [te_pkg::XLEN-1:0]                  te_cause;
  logic [te_pkg::XLEN-1:0]                  te_tval;
  logic [te_pkg::PRIV_LEN-1:0]              te_priv;
  logic [N-1:0][te_pkg::XLEN-1:0]           te_iaddr;
  logic [N-1:0][te_pkg::IRETIRE_LEN-1:0]    te_iretire;
  logic [N-1:0]                                    te_ilastsize;

  // Internal wires: tracer -> encapsulator
  logic [N-1:0]                                    pkt_valid;
  te_pkg::it_packet_type_e [N-1:0]                 pkt_type;
  logic [N-1:0][te_pkg::P_LEN-1:0]                 pkt_length;
  logic [N-1:0][te_pkg::PAYLOAD_LEN-1:0]           pkt_payload;

  logic                                            encap_ready;

  // New connector output packet
  iti_to_encoder_t iti_pkt;

  logic [CVA6Cfg.NrCommitPorts-1:0] connector_valid;

  // 1)  connector: packet in / packet out
  cva6_te_connector #(
    .CVA6Cfg          (CVA6Cfg),
    .block_mode       (1),
    .rvfi_to_iti_t    (rvfi_to_iti_t),
    .iti_to_encoder_t (iti_to_encoder_t)
  ) u_connector (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .valid_i          (rvfi_to_iti_i.valid),
    .rvfi_to_iti_i    (rvfi_to_iti_i),
    .valid_o          (connector_valid),
    .iti_to_encoder_o (iti_pkt)
  );

  // Flatten connector output packet into old rv_tracer flat signals
  // Wrapper stays single-lane (N=1), so consume lane [0] only.
  always_comb begin
    te_valid     = '0;
    te_iretire   = '0;
    te_ilastsize = '0;
    te_itype     = '0;
    te_iaddr     = '0;

    te_cause = iti_pkt.cause;
    te_tval  = iti_pkt.tval;
    te_priv  = iti_pkt.priv;

    te_valid[0]     = iti_pkt.valid[0];
    te_iretire[0]   = iti_pkt.iretire[0];
    te_ilastsize[0] = iti_pkt.ilastsize[0];
    te_itype[0]     = te_pkg::ITYPE_LEN'(iti_pkt.itype[0]);
    te_iaddr[0]     = iti_pkt.iaddr[0];
  end
  
  // 2) rv_tracer
  
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

  // 3) rv_encapsulator
  // Encapsulator is single-lane, so use lane [0]
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