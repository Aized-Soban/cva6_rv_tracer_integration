module atb_flush_ctrl (
    input  logic       clk_i,
    input  logic       rst_ni,

    // Flush request seen in source clock domain
    input  logic       afvalid_i,

    // Local source flush completion
    input  logic       src_afready_i,

    // Destination-side acknowledge back to this controller
    input  logic       flush_ack_i,

    // Flush request to local source
    output logic       src_afvalid_o,

    // Source-complete indication toward destination
    output logic       flush_complete_o,

    // Optional debug
    output logic       busy_o,
    output logic [1:0] state_o
);

  typedef enum logic [1:0] {
    IDLE_S     = 2'b00,
    FLUSH_S    = 2'b01,
    WAIT_ACK_S = 2'b10
  } state_t;

  state_t state_q, state_d;

  // Prevent re-accepting the same level-high afvalid_i after WAIT_ACK -> IDLE.
  // Re-arm only when afvalid_i goes low.
  logic req_seen_q, req_seen_d;

  logic start_flush;

  assign start_flush = afvalid_i & ~req_seen_q;

  // Next-state / sideband control
  always_comb begin
    state_d    = state_q;
    req_seen_d = req_seen_q;

    // Re-arm when the incoming request level goes low again
    if (!afvalid_i) begin
      req_seen_d = 1'b0;
    end

    unique case (state_q)
      IDLE_S: begin
        if (start_flush) begin
          state_d    = FLUSH_S;
          req_seen_d = 1'b1;
        end
      end

      FLUSH_S: begin
        if (src_afready_i) begin
          state_d = WAIT_ACK_S;
        end
      end

      WAIT_ACK_S: begin
        if (flush_ack_i) begin
          state_d = IDLE_S;
        end
      end

      default: begin
        state_d    = IDLE_S;
        req_seen_d = 1'b0;
      end
    endcase
  end

  // Registers
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q    <= IDLE_S;
      req_seen_q <= 1'b0;
    end else begin
      state_q    <= state_d;
      req_seen_q <= req_seen_d;
    end
  end

  // --------------------------------------------------------------------------
  // Outputs
  //
  // IMPORTANT:
  // 1) src_afvalid_o goes high immediately when a new flush request is seen,
  //    even before the FSM has fully moved out of IDLE.
  //
  // 2) flush_complete_o goes high immediately when src_afready_i is seen in
  //    FLUSH, and stays high throughout WAIT_ACK.
  // --------------------------------------------------------------------------
  always_comb begin
    // Immediate assertion on new request, plus steady assertion in FLUSH
    src_afvalid_o = ((state_q == IDLE_S)  && start_flush) ||
                    ((state_q == FLUSH_S));

    // Immediate assertion on source completion, plus steady assertion in WAIT_ACK
    flush_complete_o = ((state_q == FLUSH_S)    && src_afready_i) ||
                       ((state_q == WAIT_ACK_S));

    busy_o  = (state_q != IDLE_S) || start_flush;
    state_o = state_q;
  end

endmodule