module atb_funnel_top #(
  parameter int unsigned ATDATA_W    = 32,
  parameter int unsigned ATBYTES_W   = 2,
  parameter int unsigned ATID_W      = 7,
  parameter int unsigned SYNC_STAGES = 2
) (

  // Common source-side clock domain

  input  logic                    src_clk_i,
  input  logic                    src_rst_ni,


  // Funnel / destination-side clock domain

  input  logic                    dst_clk_i,
  input  logic                    dst_rst_ni,


  // ATB bus 0 : Neighbor trace

  input  logic [ATDATA_W-1:0]     nbr_atdata_i,
  input  logic [ATBYTES_W-1:0]    nbr_atbytes_i,
  input  logic [ATID_W-1:0]       nbr_atid_i,
  input  logic                    nbr_atvalid_i,
  output logic                    nbr_atready_o,
  output logic                    nbr_afvalid_o,
  input  logic                    nbr_afready_i,

  // ATB bus 1 : System trace

  input  logic [ATDATA_W-1:0]     sys_atdata_i,
  input  logic [ATBYTES_W-1:0]    sys_atbytes_i,
  input  logic [ATID_W-1:0]       sys_atid_i,
  input  logic                    sys_atvalid_i,
  output logic                    sys_atready_o,
  output logic                    sys_afvalid_o,
  input  logic                    sys_afready_i,


  // ATB bus 2 : Instruction trace

  input  logic [ATDATA_W-1:0]     ins_atdata_i,
  input  logic [ATBYTES_W-1:0]    ins_atbytes_i,
  input  logic [ATID_W-1:0]       ins_atid_i,
  input  logic                    ins_atvalid_i,
  output logic                    ins_atready_o,
  output logic                    ins_afvalid_o,
  input  logic                    ins_afready_i,


  // Output ATB bus

  output logic [ATDATA_W-1:0]     out_atdata_o,
  output logic [ATBYTES_W-1:0]    out_atbytes_o,
  output logic [ATID_W-1:0]       out_atid_o,
  output logic                    out_atvalid_o,
  input  logic                    out_atready_i,

  input  logic                    out_afvalid_i,
  output logic                    out_afready_o,

  // Optional debug
  output logic                    nbr_flush_complete_o,
  output logic                    sys_flush_complete_o,
  output logic                    ins_flush_complete_o,
  output logic [1:0]              mux_sel_o
);

  typedef struct packed {
    logic [ATDATA_W-1:0]  atdata;
    logic [ATBYTES_W-1:0] atbytes;
    logic [ATID_W-1:0]    atid;
  } atb_payload_t;


  // Shared destination->source synced control

  logic afvalid_src_sync;
  logic flush_ack_src_sync;


  // Source-side flush-controller outputs

  logic nbr_flush_complete_src;
  logic sys_flush_complete_src;
  logic ins_flush_complete_src;


  // Source->destination payload CDC

  atb_payload_t nbr_src_payload, nbr_dst_payload;
  atb_payload_t sys_src_payload, sys_dst_payload;
  atb_payload_t ins_src_payload, ins_dst_payload;

  logic nbr_dst_atvalid, nbr_dst_atready;
  logic sys_dst_atvalid, sys_dst_atready;
  logic ins_dst_atvalid, ins_dst_atready;


  // Priority mux outputs

  logic [ATDATA_W-1:0]  mux_atdata;
  logic [ATBYTES_W-1:0] mux_atbytes;
  logic [ATID_W-1:0]    mux_atid;
  logic                 mux_atvalid;
  logic                 mux_atready;


  // Post-mux FIFO

  atb_payload_t fifo_data_in, fifo_data_out;
  logic         fifo_push, fifo_pop;
  logic         fifo_full, fifo_empty;
  //logic [0:0]   fifo_usage;


  // Flush bookkeeping

  logic all_src_done;
  logic all_src_done_re;
  logic all_src_done_fe_unused;

  logic out_afvalid_q;
  logic flush_start_re;

  logic all_done_seen_q;
  logic fifo_old_q;

  // Pack source payloads

  assign nbr_src_payload.atdata  = nbr_atdata_i;
  assign nbr_src_payload.atbytes = nbr_atbytes_i;
  assign nbr_src_payload.atid    = nbr_atid_i;

  assign sys_src_payload.atdata  = sys_atdata_i;
  assign sys_src_payload.atbytes = sys_atbytes_i;
  assign sys_src_payload.atid    = sys_atid_i;

  assign ins_src_payload.atdata  = ins_atdata_i;
  assign ins_src_payload.atbytes = ins_atbytes_i;
  assign ins_src_payload.atid    = ins_atid_i;


  // Sync output-side flush request and flush ack into source clock domain

  sync #(
    .STAGES     ( SYNC_STAGES ),
    .ResetValue ( 1'b0        )
  ) i_sync_afvalid_to_src (
    .clk_i    ( src_clk_i        ),
    .rst_ni   ( src_rst_ni       ),
    .serial_i ( out_afvalid_i    ),
    .serial_o ( afvalid_src_sync )
  );

  sync #(
    .STAGES     ( SYNC_STAGES ),
    .ResetValue ( 1'b0        )
  ) i_sync_flush_ack_to_src (
    .clk_i    ( src_clk_i          ),
    .rst_ni   ( src_rst_ni         ),
    .serial_i ( out_afready_o      ),
    .serial_o ( flush_ack_src_sync )
  );

  // Flush controllers

  atb_flush_ctrl i_nbr_flush_ctrl (
    .clk_i            ( src_clk_i              ),
    .rst_ni           ( src_rst_ni             ),
    .afvalid_i        ( afvalid_src_sync       ),
    .src_afready_i    ( nbr_afready_i          ),
    .flush_ack_i      ( flush_ack_src_sync     ),
    .src_afvalid_o    ( nbr_afvalid_o          ),
    .flush_complete_o ( nbr_flush_complete_src ),
    .busy_o           (                        ),
    .state_o          (                        )
  );

  atb_flush_ctrl i_sys_flush_ctrl (
    .clk_i            ( src_clk_i              ),
    .rst_ni           ( src_rst_ni             ),
    .afvalid_i        ( afvalid_src_sync       ),
    .src_afready_i    ( sys_afready_i          ),
    .flush_ack_i      ( flush_ack_src_sync     ),
    .src_afvalid_o    ( sys_afvalid_o          ),
    .flush_complete_o ( sys_flush_complete_src ),
    .busy_o           (                        ),
    .state_o          (                        )
  );

  atb_flush_ctrl i_ins_flush_ctrl (
    .clk_i            ( src_clk_i              ),
    .rst_ni           ( src_rst_ni             ),
    .afvalid_i        ( afvalid_src_sync       ),
    .src_afready_i    ( ins_afready_i          ),
    .flush_ack_i      ( flush_ack_src_sync     ),
    .src_afvalid_o    ( ins_afvalid_o          ),
    .flush_complete_o ( ins_flush_complete_src ),
    .busy_o           (                        ),
    .state_o          (                        )
  );


  // Payload CDCs: source -> destination

  cdc_fifo_2phase #(
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

  cdc_fifo_2phase #(
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

  cdc_fifo_2phase #(
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

  // Sync source-side flush_complete into destination clock domain


  sync #(
    .STAGES     ( SYNC_STAGES ),
    .ResetValue ( 1'b0        )
  ) i_sync_nbr_flush_complete (
    .clk_i    ( dst_clk_i              ),
    .rst_ni   ( dst_rst_ni             ),
    .serial_i ( nbr_flush_complete_src ),
    .serial_o ( nbr_flush_complete_o   )
  );

  sync #(
    .STAGES     ( SYNC_STAGES ),
    .ResetValue ( 1'b0        )
  ) i_sync_sys_flush_complete (
    .clk_i    ( dst_clk_i              ),
    .rst_ni   ( dst_rst_ni             ),
    .serial_i ( sys_flush_complete_src ),
    .serial_o ( sys_flush_complete_o   )
  );

  sync #(
    .STAGES     ( SYNC_STAGES ),
    .ResetValue ( 1'b0        )
  ) i_sync_ins_flush_complete (
    .clk_i    ( dst_clk_i              ),
    .rst_ni   ( dst_rst_ni             ),
    .serial_i ( ins_flush_complete_src ),
    .serial_o ( ins_flush_complete_o   )
  );

  // Priority mux

  atb_priority_mux #(
    .ATDATA_W  ( ATDATA_W  ),
    .ATBYTES_W ( ATBYTES_W ),
    .ATID_W    ( ATID_W    )
  ) i_priority_mux (
    .nbr_flush_complete_i ( nbr_flush_complete_o    ),
    .sys_flush_complete_i ( sys_flush_complete_o    ),
    .ins_flush_complete_i ( ins_flush_complete_o    ),

    .nbr_atdata_i         ( nbr_dst_payload.atdata  ),
    .nbr_atbytes_i        ( nbr_dst_payload.atbytes ),
    .nbr_atid_i           ( nbr_dst_payload.atid    ),
    .nbr_atvalid_i        ( nbr_dst_atvalid         ),
    .nbr_atready_o        ( nbr_dst_atready         ),

    .sys_atdata_i         ( sys_dst_payload.atdata  ),
    .sys_atbytes_i        ( sys_dst_payload.atbytes ),
    .sys_atid_i           ( sys_dst_payload.atid    ),
    .sys_atvalid_i        ( sys_dst_atvalid         ),
    .sys_atready_o        ( sys_dst_atready         ),

    .ins_atdata_i         ( ins_dst_payload.atdata  ),
    .ins_atbytes_i        ( ins_dst_payload.atbytes ),
    .ins_atid_i           ( ins_dst_payload.atid    ),
    .ins_atvalid_i        ( ins_dst_atvalid         ),
    .ins_atready_o        ( ins_dst_atready         ),

    .mux_atdata_o         ( mux_atdata              ),
    .mux_atbytes_o        ( mux_atbytes             ),
    .mux_atid_o           ( mux_atid                ),
    .mux_atvalid_o        ( mux_atvalid             ),
    .mux_atready_i        ( mux_atready             ),
    .sel_o                ( mux_sel_o               )
  );

  // Post-mux single-depth FIFO
  
  assign fifo_data_in.atdata  = mux_atdata;
  assign fifo_data_in.atbytes = mux_atbytes;
  assign fifo_data_in.atid    = mux_atid;

  assign mux_atready = ~fifo_full;
  assign fifo_push   = mux_atvalid & mux_atready;

  assign fifo_pop    = out_atvalid_o & out_atready_i;
  
  fifo_v3 #(
    .FALL_THROUGH ( 1'b0          ),
    .DEPTH        ( 1             ),
    .dtype        ( atb_payload_t )
  ) i_post_mux_fifo (
    .clk_i      ( dst_clk_i     ),
    .rst_ni     ( dst_rst_ni    ),
    .flush_i    ( 1'b0          ),
    .testmode_i ( 1'b0          ),
    .full_o     ( fifo_full     ),
    .empty_o    ( fifo_empty    ),
//    .usage_o    ( fifo_usage    ),
    .data_i     ( fifo_data_in  ),
    .push_i     ( fifo_push     ),
    .data_o     ( fifo_data_out ),
    .pop_i      ( fifo_pop      )
  );

  assign out_atdata_o  = fifo_data_out.atdata;
  assign out_atbytes_o = fifo_data_out.atbytes;
  assign out_atid_o    = fifo_data_out.atid;
  assign out_atvalid_o = ~fifo_empty;

  // Flush-complete combine

  assign all_src_done = nbr_flush_complete_o &
                        sys_flush_complete_o &
                        ins_flush_complete_o;

  edge_detect i_all_done_edge_detect (
    .clk_i  ( dst_clk_i            ),
    .rst_ni ( dst_rst_ni           ),
    .d_i    ( all_src_done         ),
    .re_o   ( all_src_done_re      ), // rising edge
    .fe_o   ( all_src_done_fe_unused )
  );

  // Detect start of an output flush request
  
  always_ff @(posedge dst_clk_i or negedge dst_rst_ni) begin
    if (!dst_rst_ni) begin
      out_afvalid_q <= 1'b0;
    end else begin
      out_afvalid_q <= out_afvalid_i;
    end
  end

  assign flush_start_re = out_afvalid_i & ~out_afvalid_q;

  // Sticky "all done seen" latch

  always_ff @(posedge dst_clk_i or negedge dst_rst_ni) begin
    if (!dst_rst_ni) begin
      all_done_seen_q <= 1'b0;
    end else if (!out_afvalid_i) begin
      all_done_seen_q <= 1'b0;
    end else if (all_src_done_re) begin
      all_done_seen_q <= 1'b1;
    end
  end

  // Track whether funnel still has one old pre-flush beat buffered locally

  always_ff @(posedge dst_clk_i or negedge dst_rst_ni) begin
    if (!dst_rst_ni) begin
      fifo_old_q <= 1'b0;
    end else if (!out_afvalid_i) begin
      fifo_old_q <= 1'b0;
    end else begin
      if (flush_start_re) begin
        fifo_old_q <= (~fifo_empty) | mux_atvalid;
      end else if (fifo_old_q && fifo_pop) begin
        fifo_old_q <= 1'b0;
      end
    end
  end

  // Final flush acknowledge to output receiver

  assign out_afready_o = out_afvalid_i & all_done_seen_q & ~fifo_old_q;

endmodule