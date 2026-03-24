module atb_funnel_pre_fifo_top #(
  parameter int unsigned ATDATA_W    = 32,
  parameter int unsigned ATBYTES_W   = 2,
  parameter int unsigned ATID_W      = 7,
  parameter int unsigned SYNC_STAGES = 2
) (
  // --------------------------------------------------------------------------
  // Common source-side clock domain
  // --------------------------------------------------------------------------
  input  logic                    src_clk_i,
  input  logic                    src_rst_ni,

  // --------------------------------------------------------------------------
  // Destination / funnel clock domain
  // --------------------------------------------------------------------------
  input  logic                    dst_clk_i,
  input  logic                    dst_rst_ni,

  // --------------------------------------------------------------------------
  // Flush control coming from the later funnel/output stage
  // These are shared across all three source-side flush controllers.
  // --------------------------------------------------------------------------
  input  logic                    dst_afvalid_i,
  input  logic                    dst_flush_ack_i,

  // --------------------------------------------------------------------------
  // ATB bus 0 : Neighbor trace (highest base priority)
  // --------------------------------------------------------------------------
  input  logic [ATDATA_W-1:0]     nbr_atdata_i,
  input  logic [ATBYTES_W-1:0]    nbr_atbytes_i,
  input  logic [ATID_W-1:0]       nbr_atid_i,
  input  logic                    nbr_atvalid_i,
  output logic                    nbr_atready_o,
  output logic                    nbr_src_afvalid_o,
  input  logic                    nbr_src_afready_i,

  // --------------------------------------------------------------------------
  // ATB bus 1 : System trace
  // --------------------------------------------------------------------------
  input  logic [ATDATA_W-1:0]     sys_atdata_i,
  input  logic [ATBYTES_W-1:0]    sys_atbytes_i,
  input  logic [ATID_W-1:0]       sys_atid_i,
  input  logic                    sys_atvalid_i,
  output logic                    sys_atready_o,
  output logic                    sys_src_afvalid_o,
  input  logic                    sys_src_afready_i,

  // --------------------------------------------------------------------------
  // ATB bus 2 : Instruction trace (lowest base priority)
  // --------------------------------------------------------------------------
  input  logic [ATDATA_W-1:0]     ins_atdata_i,
  input  logic [ATBYTES_W-1:0]    ins_atbytes_i,
  input  logic [ATID_W-1:0]       ins_atid_i,
  input  logic                    ins_atvalid_i,
  output logic                    ins_atready_o,
  output logic                    ins_src_afvalid_o,
  input  logic                    ins_src_afready_i,

  // --------------------------------------------------------------------------
  // Selected stream toward the later post-mux FIFO stage
  // --------------------------------------------------------------------------
  output logic [ATDATA_W-1:0]     mux_atdata_o,
  output logic [ATBYTES_W-1:0]    mux_atbytes_o,
  output logic [ATID_W-1:0]       mux_atid_o,
  output logic                    mux_atvalid_o,
  input  logic                    mux_atready_i,

  // --------------------------------------------------------------------------
  // Synchronized per-source flush-complete bits for later funnel logic
  // --------------------------------------------------------------------------
  output logic                    nbr_flush_complete_o,
  output logic                    sys_flush_complete_o,
  output logic                    ins_flush_complete_o,

  // Optional debug
  output logic [1:0]              mux_sel_o
);

  typedef struct packed {
    logic [ATDATA_W-1:0]  atdata;
    logic [ATBYTES_W-1:0] atbytes;
    logic [ATID_W-1:0]    atid;
  } atb_payload_t;

  // --------------------------------------------------------------------------
  // Shared synchronized control into source clock domain
  // --------------------------------------------------------------------------
  logic afvalid_src_sync;
  logic flush_ack_src_sync;

  // --------------------------------------------------------------------------
  // Source-domain flush-controller outputs
  // --------------------------------------------------------------------------
  logic nbr_flush_complete_src;
  logic sys_flush_complete_src;
  logic ins_flush_complete_src;

  // --------------------------------------------------------------------------
  // CDC payload wiring
  // --------------------------------------------------------------------------
  atb_payload_t nbr_src_payload, nbr_dst_payload;
  atb_payload_t sys_src_payload, sys_dst_payload;
  atb_payload_t ins_src_payload, ins_dst_payload;

  logic nbr_dst_atvalid, sys_dst_atvalid, ins_dst_atvalid;
  logic nbr_dst_atready, sys_dst_atready, ins_dst_atready;

  // --------------------------------------------------------------------------
  // Pack source payloads
  // --------------------------------------------------------------------------
  assign nbr_src_payload.atdata  = nbr_atdata_i;
  assign nbr_src_payload.atbytes = nbr_atbytes_i;
  assign nbr_src_payload.atid    = nbr_atid_i;

  assign sys_src_payload.atdata  = sys_atdata_i;
  assign sys_src_payload.atbytes = sys_atbytes_i;
  assign sys_src_payload.atid    = sys_atid_i;

  assign ins_src_payload.atdata  = ins_atdata_i;
  assign ins_src_payload.atbytes = ins_atbytes_i;
  assign ins_src_payload.atid    = ins_atid_i;

  // --------------------------------------------------------------------------
  // Shared control synchronizers: destination -> source
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
  // Flush controllers (one per source)
  // --------------------------------------------------------------------------
  atb_flush_ctrl i_nbr_flush_ctrl (
    .clk_i            ( src_clk_i             ),
    .rst_ni           ( src_rst_ni            ),
    .afvalid_i        ( afvalid_src_sync      ),
    .src_afready_i    ( nbr_src_afready_i     ),
    .flush_ack_i      ( flush_ack_src_sync    ),
    .src_afvalid_o    ( nbr_src_afvalid_o     ),
    .flush_complete_o ( nbr_flush_complete_src ),
    .busy_o           ( /* unused */          ),
    .state_o          ( /* unused */          )
  );

  atb_flush_ctrl i_sys_flush_ctrl (
    .clk_i            ( src_clk_i             ),
    .rst_ni           ( src_rst_ni            ),
    .afvalid_i        ( afvalid_src_sync      ),
    .src_afready_i    ( sys_src_afready_i     ),
    .flush_ack_i      ( flush_ack_src_sync    ),
    .src_afvalid_o    ( sys_src_afvalid_o     ),
    .flush_complete_o ( sys_flush_complete_src ),
    .busy_o           ( /* unused */          ),
    .state_o          ( /* unused */          )
  );

  atb_flush_ctrl i_ins_flush_ctrl (
    .clk_i            ( src_clk_i             ),
    .rst_ni           ( src_rst_ni            ),
    .afvalid_i        ( afvalid_src_sync      ),
    .src_afready_i    ( ins_src_afready_i     ),
    .flush_ack_i      ( flush_ack_src_sync    ),
    .src_afvalid_o    ( ins_src_afvalid_o     ),
    .flush_complete_o ( ins_flush_complete_src ),
    .busy_o           ( /* unused */          ),
    .state_o          ( /* unused */          )
  );

  // --------------------------------------------------------------------------
  // Payload CDCs: source -> destination
  // --------------------------------------------------------------------------
  cdc_2phase #(
    .T ( atb_payload_t )
  ) i_nbr_cdc (
    .src_rst_ni  ( src_rst_ni      ),
    .src_clk_i   ( src_clk_i       ),
    .src_data_i  ( nbr_src_payload ),
    .src_valid_i ( nbr_atvalid_i   ),
    .src_ready_o ( nbr_atready_o   ),

    .dst_rst_ni  ( dst_rst_ni      ),
    .dst_clk_i   ( dst_clk_i       ),
    .dst_data_o  ( nbr_dst_payload ),
    .dst_valid_o ( nbr_dst_atvalid ),
    .dst_ready_i ( nbr_dst_atready )
  );

  cdc_2phase #(
    .T ( atb_payload_t )
  ) i_sys_cdc (
    .src_rst_ni  ( src_rst_ni      ),
    .src_clk_i   ( src_clk_i       ),
    .src_data_i  ( sys_src_payload ),
    .src_valid_i ( sys_atvalid_i   ),
    .src_ready_o ( sys_atready_o   ),

    .dst_rst_ni  ( dst_rst_ni      ),
    .dst_clk_i   ( dst_clk_i       ),
    .dst_data_o  ( sys_dst_payload ),
    .dst_valid_o ( sys_dst_atvalid ),
    .dst_ready_i ( sys_dst_atready )
  );

  cdc_2phase #(
    .T ( atb_payload_t )
  ) i_ins_cdc (
    .src_rst_ni  ( src_rst_ni      ),
    .src_clk_i   ( src_clk_i       ),
    .src_data_i  ( ins_src_payload ),
    .src_valid_i ( ins_atvalid_i   ),
    .src_ready_o ( ins_atready_o   ),

    .dst_rst_ni  ( dst_rst_ni      ),
    .dst_clk_i   ( dst_clk_i       ),
    .dst_data_o  ( ins_dst_payload ),
    .dst_valid_o ( ins_dst_atvalid ),
    .dst_ready_i ( ins_dst_atready )
  );

  // --------------------------------------------------------------------------
  // Per-source flush_complete synchronizers: source -> destination
  // --------------------------------------------------------------------------
  sync #(
    .STAGES     ( SYNC_STAGES ),
    .ResetValue ( 1'b0        )
  ) i_sync_nbr_flush_complete_to_dst (
    .clk_i    ( dst_clk_i             ),
    .rst_ni   ( dst_rst_ni            ),
    .serial_i ( nbr_flush_complete_src ),
    .serial_o ( nbr_flush_complete_o  )
  );

  sync #(
    .STAGES     ( SYNC_STAGES ),
    .ResetValue ( 1'b0        )
  ) i_sync_sys_flush_complete_to_dst (
    .clk_i    ( dst_clk_i             ),
    .rst_ni   ( dst_rst_ni            ),
    .serial_i ( sys_flush_complete_src ),
    .serial_o ( sys_flush_complete_o  )
  );

  sync #(
    .STAGES     ( SYNC_STAGES ),
    .ResetValue ( 1'b0        )
  ) i_sync_ins_flush_complete_to_dst (
    .clk_i    ( dst_clk_i             ),
    .rst_ni   ( dst_rst_ni            ),
    .serial_i ( ins_flush_complete_src ),
    .serial_o ( ins_flush_complete_o  )
  );

  // --------------------------------------------------------------------------
  // Destination-domain priority mux
  //
  // NOTE:
  // This is the current version of your mux that masks out any source whose
  // synchronized flush_complete is high.
  // The post-mux FIFO and final funnel afready logic are intentionally not
  // included yet.
  // --------------------------------------------------------------------------
  atb_priority_mux #(
    .ATDATA_W  ( ATDATA_W  ),
    .ATBYTES_W ( ATBYTES_W ),
    .ATID_W    ( ATID_W    )
  ) i_priority_mux (
    .nbr_flush_complete_i ( nbr_flush_complete_o       ),
    .sys_flush_complete_i ( sys_flush_complete_o       ),
    .ins_flush_complete_i ( ins_flush_complete_o       ),

    .nbr_atdata_i         ( nbr_dst_payload.atdata     ),
    .nbr_atbytes_i        ( nbr_dst_payload.atbytes    ),
    .nbr_atid_i           ( nbr_dst_payload.atid       ),
    .nbr_atvalid_i        ( nbr_dst_atvalid            ),
    .nbr_atready_o        ( nbr_dst_atready            ),

    .sys_atdata_i         ( sys_dst_payload.atdata     ),
    .sys_atbytes_i        ( sys_dst_payload.atbytes    ),
    .sys_atid_i           ( sys_dst_payload.atid       ),
    .sys_atvalid_i        ( sys_dst_atvalid            ),
    .sys_atready_o        ( sys_dst_atready            ),

    .ins_atdata_i         ( ins_dst_payload.atdata     ),
    .ins_atbytes_i        ( ins_dst_payload.atbytes    ),
    .ins_atid_i           ( ins_dst_payload.atid       ),
    .ins_atvalid_i        ( ins_dst_atvalid            ),
    .ins_atready_o        ( ins_dst_atready            ),

    .mux_atdata_o         ( mux_atdata_o               ),
    .mux_atbytes_o        ( mux_atbytes_o              ),
    .mux_atid_o           ( mux_atid_o                 ),
    .mux_atvalid_o        ( mux_atvalid_o              ),
    .mux_atready_i        ( mux_atready_i              ),

    .sel_o                ( mux_sel_o                  )
  );

endmodule