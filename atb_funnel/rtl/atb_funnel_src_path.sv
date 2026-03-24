module atb_funnel_src_path #(
  parameter int unsigned ATDATA_W    = 32,
  parameter int unsigned ATBYTES_W   = 2,
  parameter int unsigned ATID_W      = 7,
  parameter int unsigned SYNC_STAGES = 2
) (
  // --------------------------------------------------------------------------
  // Source clock domain
  // --------------------------------------------------------------------------
  input  logic                    src_clk_i,
  input  logic                    src_rst_ni,

  input  logic [ATDATA_W-1:0]     src_atdata_i,
  input  logic [ATBYTES_W-1:0]    src_atbytes_i,
  input  logic [ATID_W-1:0]       src_atid_i,
  input  logic                    src_atvalid_i,
  output logic                    src_atready_o,

  // Flush interface toward the local ATB source
  output logic                    src_afvalid_o,
  input  logic                    src_afready_i,

  // --------------------------------------------------------------------------
  // Destination / funnel clock domain
  // --------------------------------------------------------------------------
  input  logic                    dst_clk_i,
  input  logic                    dst_rst_ni,

  // Flush request coming from downstream receiver side
  input  logic                    dst_afvalid_i,

  // Flush acknowledge coming back from destination-side funnel/output logic
  input  logic                    dst_flush_ack_i,

  // Stream presented in destination clock domain
  output logic [ATDATA_W-1:0]     dst_atdata_o,
  output logic [ATBYTES_W-1:0]    dst_atbytes_o,
  output logic [ATID_W-1:0]       dst_atid_o,
  output logic                    dst_atvalid_o,
  input  logic                    dst_atready_i,

  // Source-complete indication seen in destination domain
  output logic                    dst_flush_complete_o
);

  typedef struct packed {
    logic [ATDATA_W-1:0]  atdata;
    logic [ATBYTES_W-1:0] atbytes;
    logic [ATID_W-1:0]    atid;
  } atb_payload_t;

  atb_payload_t src_payload, dst_payload;

  logic afvalid_src_sync;
  logic flush_ack_src_sync;
  logic flush_complete_src;

  assign src_payload.atdata  = src_atdata_i;
  assign src_payload.atbytes = src_atbytes_i;
  assign src_payload.atid    = src_atid_i;

  // --------------------------------------------------------------------------
  // Flush request: destination domain -> source domain
  // --------------------------------------------------------------------------
  sync #(
    .STAGES     ( SYNC_STAGES ),
    .ResetValue ( 1'b0        )
  ) i_sync_afvalid_to_src (
    .clk_i    ( src_clk_i       ),
    .rst_ni   ( src_rst_ni      ),
    .serial_i ( dst_afvalid_i   ),
    .serial_o ( afvalid_src_sync )
  );

  // --------------------------------------------------------------------------
  // Flush acknowledge: destination domain -> source domain
  // --------------------------------------------------------------------------
  sync #(
    .STAGES     ( SYNC_STAGES ),
    .ResetValue ( 1'b0        )
  ) i_sync_flush_ack_to_src (
    .clk_i    ( src_clk_i         ),
    .rst_ni   ( src_rst_ni        ),
    .serial_i ( dst_flush_ack_i   ),
    .serial_o ( flush_ack_src_sync )
  );

  // --------------------------------------------------------------------------
  // Source-side flush controller
  // --------------------------------------------------------------------------
  atb_flush_ctrl i_atb_flush_ctrl (
    .clk_i            ( src_clk_i          ),
    .rst_ni           ( src_rst_ni         ),
    .afvalid_i        ( afvalid_src_sync   ),
    .src_afready_i    ( src_afready_i      ),
    .flush_ack_i      ( flush_ack_src_sync ),
    .src_afvalid_o    ( src_afvalid_o      ),
    .flush_complete_o ( flush_complete_src ),
    .busy_o           ( /* unused */       ),
    .state_o          ( /* unused */       )
  );

  // --------------------------------------------------------------------------
  // Source-complete: source domain -> destination domain
  // --------------------------------------------------------------------------
  sync #(
    .STAGES     ( SYNC_STAGES ),
    .ResetValue ( 1'b0        )
  ) i_sync_flush_complete_to_dst (
    .clk_i    ( dst_clk_i             ),
    .rst_ni   ( dst_rst_ni            ),
    .serial_i ( flush_complete_src    ),
    .serial_o ( dst_flush_complete_o  )
  );

  // --------------------------------------------------------------------------
  // ATB payload CDC: source domain -> destination domain
  // --------------------------------------------------------------------------
  cdc_2phase #(
    .T ( atb_payload_t )
  ) i_cdc_2phase (
    .src_rst_ni  ( src_rst_ni     ),
    .src_clk_i   ( src_clk_i      ),
    .src_data_i  ( src_payload    ),
    .src_valid_i ( src_atvalid_i  ),
    .src_ready_o ( src_atready_o  ),

    .dst_rst_ni  ( dst_rst_ni     ),
    .dst_clk_i   ( dst_clk_i      ),
    .dst_data_o  ( dst_payload    ),
    .dst_valid_o ( dst_atvalid_o  ),
    .dst_ready_i ( dst_atready_i  )
  );

  assign dst_atdata_o  = dst_payload.atdata;
  assign dst_atbytes_o = dst_payload.atbytes;
  assign dst_atid_o    = dst_payload.atid;

endmodule