`timescale 1ns/1ps
// ============================================================================
// trace_subsystem_top.sv
//
// Top-level trace integration wrapper.
//
// Current integration:
//   - Instruction / Encoder trace (Enc_trace_top)
//   - 3-input ATB funnel (atb_funnel_top)
//
// Reserved for later integration:
//   - System trace (STM)
//   - Neighbor tile trace
//
// For now, only instruction trace is connected into the funnel.
// System-trace and neighbor-trace funnel inputs are tied off.
// ============================================================================

module trace_subsystem_top #(
  parameter int unsigned N                = 1,
  parameter int unsigned ONLY_BRANCHES    = 0,
  parameter int unsigned APB_ADDR_WIDTH   = 32,
  parameter int unsigned DATA_LEN         = 32,
  parameter int unsigned ENCAP_FIFO_DEPTH = 16,
  parameter logic [4:0] HARTID            = 5'd0,
  parameter logic       TRACE_IS_SYSTEM   = 1'b0,
  parameter int unsigned ATID_W           = 7,
  parameter int unsigned SYNC_STAGES      = 2
)(
  // --------------------------------------------------------------------------
  // Clocks / resets
  // --------------------------------------------------------------------------
  input  logic                         trace_clk_i,
  input  logic                         trace_rst_ni,

  input  logic                         funnel_clk_i,
  input  logic                         funnel_rst_ni,

  // --------------------------------------------------------------------------
  // Encoder / instruction trace inputs
  // --------------------------------------------------------------------------
  input  iti_pkg::rvfi_to_iti_t        rvfi_to_iti_i,
  input  logic [te_pkg::TIME_LEN-1:0]  time_i,
  input  logic [te_pkg::XLEN-1:0]      tvec_i,
  input  logic [te_pkg::XLEN-1:0]      epc_i,

  // --------------------------------------------------------------------------
  // APB programming interface to instruction trace
  // --------------------------------------------------------------------------
  input  logic [APB_ADDR_WIDTH-1:0]    paddr_i,
  input  logic                         pwrite_i,
  input  logic                         psel_i,
  input  logic                         penable_i,
  input  logic [31:0]                  pwdata_i,
  output logic                         pready_o,
  output logic [31:0]                  prdata_o,

  // --------------------------------------------------------------------------
  // Final ATB output of the integrated trace subsystem
  // --------------------------------------------------------------------------
  output logic [$clog2(DATA_LEN)-4:0]  out_atbytes_o,
  output logic [DATA_LEN-1:0]          out_atdata_o,
  output logic [ATID_W-1:0]            out_atid_o,
  output logic                         out_atvalid_o,
  input  logic                         out_atready_i,

  input  logic                         out_afvalid_i,
  output logic                         out_afready_o,

  // --------------------------------------------------------------------------
  // Misc / status
  // --------------------------------------------------------------------------
  output logic                         enc_stall_o,
  output logic                         nbr_flush_complete_o,
  output logic                         sys_flush_complete_o,
  output logic                         ins_flush_complete_o,
  output logic [1:0]                   funnel_mux_sel_o
);

  // --------------------------------------------------------------------------
  // Local instruction-trace ATB wires
  // --------------------------------------------------------------------------
  logic [$clog2(DATA_LEN)-4:0] ins_atbytes;
  logic [DATA_LEN-1:0]         ins_atdata;
  logic [ATID_W-1:0]           ins_atid;
  logic                        ins_atvalid;
  logic                        ins_atready;
  logic                        ins_afvalid;
  logic                        ins_afready;

  // --------------------------------------------------------------------------
  // Reserved wires for future System Trace (STM)
  // --------------------------------------------------------------------------
  logic [$clog2(DATA_LEN)-4:0] sys_atbytes;
  logic [DATA_LEN-1:0]         sys_atdata;
  logic [ATID_W-1:0]           sys_atid;
  logic                        sys_atvalid;
  logic                        sys_atready;
  logic                        sys_afvalid;
  logic                        sys_afready;

  // --------------------------------------------------------------------------
  // Reserved wires for future Neighbor Tile trace
  // --------------------------------------------------------------------------
  logic [$clog2(DATA_LEN)-4:0] nbr_atbytes;
  logic [DATA_LEN-1:0]         nbr_atdata;
  logic [ATID_W-1:0]           nbr_atid;
  logic                        nbr_atvalid;
  logic                        nbr_atready;
  logic                        nbr_afvalid;
  logic                        nbr_afready;

  // --------------------------------------------------------------------------
  // Tie off currently-unused sources
  // Later, these ties will be replaced by real STM / neighbor-tile instances.
  // --------------------------------------------------------------------------
  assign sys_atbytes = '0;
  assign sys_atdata  = '0;
  assign sys_atid    = '0;
  assign sys_atvalid = 1'b0;
  assign sys_afready = 1'b0;

  assign nbr_atbytes = '0;
  assign nbr_atdata  = '0;
  assign nbr_atid    = '0;
  assign nbr_atvalid = 1'b0;
  assign nbr_afready = 1'b0;

  // --------------------------------------------------------------------------
  // Instruction / Encoder trace block
  // --------------------------------------------------------------------------
  Enc_trace_top #(
    .N                ( N                ),
    .ONLY_BRANCHES    ( ONLY_BRANCHES    ),
    .APB_ADDR_WIDTH   ( APB_ADDR_WIDTH   ),
    .DATA_LEN         ( DATA_LEN         ),
    .ENCAP_FIFO_DEPTH ( ENCAP_FIFO_DEPTH ),
    .HARTID           ( HARTID           ),
    .TRACE_IS_SYSTEM  ( TRACE_IS_SYSTEM  )
  ) i_enc_trace_top (
    .clk_i       ( trace_clk_i  ),
    .rst_ni      ( trace_rst_ni ),

    .rvfi_to_iti_i ( rvfi_to_iti_i ),
    .time_i       ( time_i       ),
    .tvec_i       ( tvec_i       ),
    .epc_i        ( epc_i        ),

    .paddr_i      ( paddr_i      ),
    .pwrite_i     ( pwrite_i     ),
    .psel_i       ( psel_i       ),
    .penable_i    ( penable_i    ),
    .pwdata_i     ( pwdata_i     ),
    .pready_o     ( pready_o     ),
    .prdata_o     ( prdata_o     ),

    .atready_i    ( ins_atready  ),
    .afvalid_i    ( ins_afvalid  ),
    .atbytes_o    ( ins_atbytes  ),
    .atdata_o     ( ins_atdata   ),
    .atid_o       ( ins_atid     ),
    .atvalid_o    ( ins_atvalid  ),
    .afready_o    ( ins_afready  ),

    .stall_o      ( enc_stall_o  )
  );

  // --------------------------------------------------------------------------
  // Reserved area for future STM instance
  // --------------------------------------------------------------------------
  // stm_top i_stm_top (
  //   ...
  // );

  // --------------------------------------------------------------------------
  // Reserved area for future Neighbor Tile trace instance
  // --------------------------------------------------------------------------
  // nbr_tile_trace_top i_nbr_tile_trace_top (
  //   ...
  // );

  // --------------------------------------------------------------------------
  // 3-source ATB funnel
  // Current population:
  //   bus 0 = Neighbor trace   (tied off for now)
  //   bus 1 = System trace     (tied off for now)
  //   bus 2 = Instruction trace(active)
  // --------------------------------------------------------------------------
  atb_funnel_top #(
    .ATDATA_W    ( DATA_LEN     ),
    .ATBYTES_W   ( $clog2(DATA_LEN)-3 ),
    .ATID_W      ( ATID_W       ),
    .SYNC_STAGES ( SYNC_STAGES  )
  ) i_atb_funnel_top (
    .src_clk_i   ( trace_clk_i   ),
    .src_rst_ni  ( trace_rst_ni  ),
    .dst_clk_i   ( funnel_clk_i  ),
    .dst_rst_ni  ( funnel_rst_ni ),

    .nbr_atdata_i   ( nbr_atdata    ),
    .nbr_atbytes_i  ( nbr_atbytes   ),
    .nbr_atid_i     ( nbr_atid      ),
    .nbr_atvalid_i  ( nbr_atvalid   ),
    .nbr_atready_o  ( nbr_atready   ),
    .nbr_afvalid_o  ( nbr_afvalid   ),
    .nbr_afready_i  ( nbr_afready   ),

    .sys_atdata_i   ( sys_atdata    ),
    .sys_atbytes_i  ( sys_atbytes   ),
    .sys_atid_i     ( sys_atid      ),
    .sys_atvalid_i  ( sys_atvalid   ),
    .sys_atready_o  ( sys_atready   ),
    .sys_afvalid_o  ( sys_afvalid   ),
    .sys_afready_i  ( sys_afready   ),

    .ins_atdata_i   ( ins_atdata    ),
    .ins_atbytes_i  ( ins_atbytes   ),
    .ins_atid_i     ( ins_atid      ),
    .ins_atvalid_i  ( ins_atvalid   ),
    .ins_atready_o  ( ins_atready   ),
    .ins_afvalid_o  ( ins_afvalid   ),
    .ins_afready_i  ( ins_afready   ),

    .out_atdata_o   ( out_atdata_o  ),
    .out_atbytes_o  ( out_atbytes_o ),
    .out_atid_o     ( out_atid_o    ),
    .out_atvalid_o  ( out_atvalid_o ),
    .out_atready_i  ( out_atready_i ),

    .out_afvalid_i  ( out_afvalid_i ),
    .out_afready_o  ( out_afready_o ),

    .nbr_flush_complete_o ( nbr_flush_complete_o ),
    .sys_flush_complete_o ( sys_flush_complete_o ),
    .ins_flush_complete_o ( ins_flush_complete_o ),
    .mux_sel_o            ( funnel_mux_sel_o     )
  );

endmodule
