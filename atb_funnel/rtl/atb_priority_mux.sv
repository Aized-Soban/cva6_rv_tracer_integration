module atb_priority_mux #(
  parameter int unsigned ATDATA_W  = 32,
  parameter int unsigned ATBYTES_W = 2,
  parameter int unsigned ATID_W    = 7
) (
  // Per-source flush complete
  // 1 = remove this source from priority list
  // 0 = keep this source eligible
  input  logic                    nbr_flush_complete_i,
  input  logic                    sys_flush_complete_i,
  input  logic                    ins_flush_complete_i,

  // Neighbor input
  input  logic [ATDATA_W-1:0]     nbr_atdata_i,
  input  logic [ATBYTES_W-1:0]    nbr_atbytes_i,
  input  logic [ATID_W-1:0]       nbr_atid_i,
  input  logic                    nbr_atvalid_i,
  output logic                    nbr_atready_o,

  // System input
  input  logic [ATDATA_W-1:0]     sys_atdata_i,
  input  logic [ATBYTES_W-1:0]    sys_atbytes_i,
  input  logic [ATID_W-1:0]       sys_atid_i,
  input  logic                    sys_atvalid_i,
  output logic                    sys_atready_o,

  // Instruction input
  input  logic [ATDATA_W-1:0]     ins_atdata_i,
  input  logic [ATBYTES_W-1:0]    ins_atbytes_i,
  input  logic [ATID_W-1:0]       ins_atid_i,
  input  logic                    ins_atvalid_i,
  output logic                    ins_atready_o,

  // Selected output toward post-mux FIFO
  output logic [ATDATA_W-1:0]     mux_atdata_o,
  output logic [ATBYTES_W-1:0]    mux_atbytes_o,
  output logic [ATID_W-1:0]       mux_atid_o,
  output logic                    mux_atvalid_o,
  input  logic                    mux_atready_i,

  // Optional debug
  output logic [1:0]              sel_o
);

  typedef enum logic [1:0] {
    SEL_NONE = 2'd0,
    SEL_NBR  = 2'd1,
    SEL_SYS  = 2'd2,
    SEL_INS  = 2'd3
  } sel_t;

  sel_t sel_d;

  logic nbr_eligible;
  logic sys_eligible;
  logic ins_eligible;

  // Exclude any source whose flush_complete is high
  assign nbr_eligible = nbr_atvalid_i & ~nbr_flush_complete_i;
  assign sys_eligible = sys_atvalid_i & ~sys_flush_complete_i;
  assign ins_eligible = ins_atvalid_i & ~ins_flush_complete_i;

  // Priority after masking completed sources:
  // neighbor > system > instruction
  always_comb begin
    sel_d = SEL_NONE;

    if (nbr_eligible) begin
      sel_d = SEL_NBR;
    end else if (sys_eligible) begin
      sel_d = SEL_SYS;
    end else if (ins_eligible) begin
      sel_d = SEL_INS;
    end
  end

  always_comb begin
    mux_atdata_o  = '0;
    mux_atbytes_o = '0;
    mux_atid_o    = '0;
    mux_atvalid_o = 1'b0;

    nbr_atready_o = 1'b0;
    sys_atready_o = 1'b0;
    ins_atready_o = 1'b0;

    sel_o = sel_d;

    unique case (sel_d)
      SEL_NBR: begin
        mux_atdata_o  = nbr_atdata_i;
        mux_atbytes_o = nbr_atbytes_i;
        mux_atid_o    = nbr_atid_i;
        mux_atvalid_o = nbr_atvalid_i;
        nbr_atready_o = mux_atready_i;
      end

      SEL_SYS: begin
        mux_atdata_o  = sys_atdata_i;
        mux_atbytes_o = sys_atbytes_i;
        mux_atid_o    = sys_atid_i;
        mux_atvalid_o = sys_atvalid_i;
        sys_atready_o = mux_atready_i;
      end

      SEL_INS: begin
        mux_atdata_o  = ins_atdata_i;
        mux_atbytes_o = ins_atbytes_i;
        mux_atid_o    = ins_atid_i;
        mux_atvalid_o = ins_atvalid_i;
        ins_atready_o = mux_atready_i;
      end

      default: begin
        // none selected
      end
    endcase
  end

endmodule