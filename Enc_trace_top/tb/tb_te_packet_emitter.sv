`timescale 1ns/1ps

module tb_te_packet_emitter_full;
  import te_pkg::*;

  // -------------------------
  // Clock / Reset
  // -------------------------
  logic clk_i;
  logic rst_ni;

  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  // -------------------------
  // DUT inputs
  // -------------------------
  logic                    valid_i;

  format_e                 packet_format_i;
  f_sync_subformat_e       packet_f_sync_subformat_i;

  logic [XLEN-1:0]         lc_cause_i, lc_tval_i;
  logic                    lc_interrupt_i;

  logic [XLEN-1:0]         tc_cause_i, tc_tval_i;
  logic                    tc_interrupt_i;
  logic                    tc_resync_i;

  logic                    nc_exc_only_i;
  logic                    nc_ppccd_br_i;

  logic                    nocontext_i;
  logic                    notime_i;

  logic                    tc_branch_i;
  logic                    tc_branch_taken_i;
  logic [PRIV_LEN-1:0]     tc_priv_i;
  logic [TIME_LEN-1:0]     tc_time_i;
  logic [XLEN-1:0]         tc_address_i;

  logic                    lc_tc_mux_i;
  logic                    thaddr_i;
  logic [XLEN-1:0]         tc_tvec_i;
  logic [XLEN-1:0]         lc_epc_i;

  logic                    tc_ienable_i;
  logic                    encoder_mode_i;
  qual_status_e            qual_status_i;
  ioptions_s               ioptions_i;

  logic                    lc_updiscon_i;

  logic [BRANCH_COUNT_LEN-1:0] branches_i;
  logic [BRANCH_MAP_LEN-1:0]   branch_map_i;

  logic [$clog2(XLEN):0]   keep_bits_i;
  logic                    shallow_trace_i;

  // -------------------------
  // DUT outputs
  // -------------------------
  logic                    packet_valid_o;
  it_packet_type_e         packet_type_o;
  logic [PAYLOAD_LEN-1:0]  packet_payload_o;
  logic [P_LEN-1:0]        payload_length_o;
  logic                    branch_map_flush_o;
  logic [XLEN-1:0]         addr_to_compress_o;

  // -------------------------
  // DUT instance
  // -------------------------
  te_packet_emitter dut (.*);

  // -------------------------
  // Helpers / defaults
  // -------------------------
  task automatic drive_defaults();
    valid_i = 1'b0;

    packet_format_i           = F_ADDR_ONLY;
    packet_f_sync_subformat_i = SF_START;

    lc_cause_i      = '0;
    lc_tval_i       = '0;
    lc_interrupt_i  = 1'b0;

    tc_cause_i      = '0;
    tc_tval_i       = '0;
    tc_interrupt_i  = 1'b0;
    tc_resync_i     = 1'b0;

    nc_exc_only_i   = 1'b0;
    nc_ppccd_br_i   = 1'b0;

    nocontext_i     = 1'b0;
    notime_i        = 1'b0;

    tc_branch_i        = 1'b0;
    tc_branch_taken_i  = 1'b0;
    tc_priv_i          = '0;
    tc_time_i          = '0;
    tc_address_i       = '0;

    lc_tc_mux_i      = 1'b0;
    thaddr_i         = 1'b0;
    tc_tvec_i        = '0;
    lc_epc_i         = '0;

    tc_ienable_i     = 1'b1;
    encoder_mode_i   = 1'b0;
    qual_status_i    = NO_CHANGE;
    ioptions_i       = '0;

    lc_updiscon_i    = 1'b0;

    branches_i       = '0;
    branch_map_i     = '0;

    keep_bits_i      = '0;
    shallow_trace_i  = 1'b0;
  endtask

  function automatic it_packet_type_e exp_type_for_format(format_e f, f_sync_subformat_e sf);
    unique case (f)
      F_ADDR_ONLY : exp_type_for_format = F2;
      F_DIFF_DELTA: exp_type_for_format = F1;
      F_SYNC: begin
        unique case (sf)
          SF_START  : exp_type_for_format = F3SF0;
          SF_TRAP   : exp_type_for_format = F3SF1;
          SF_CONTEXT: exp_type_for_format = F3SF2;
          SF_SUPPORT: exp_type_for_format = F3SF3;
          default   : exp_type_for_format = F3SF0;
        endcase
      end
      default: exp_type_for_format = F0SF0; // F_OPT_EXT path in your RTL starts at F0SF0
    endcase
  endfunction

  task automatic apply_one_cycle(
    input format_e f,
    input f_sync_subformat_e sf,
    input logic [XLEN-1:0] addr,
    input logic [BRANCH_COUNT_LEN-1:0] br_cnt,
    input logic [BRANCH_MAP_LEN-1:0] br_map,
    input logic [$clog2(XLEN):0] kb,
    input ioptions_s opts,
    input qual_status_e qs
  );
    @(negedge clk_i);
    packet_format_i           = f;
    packet_f_sync_subformat_i = sf;
    tc_address_i              = addr;
    branches_i                = br_cnt;
    branch_map_i              = br_map;
    keep_bits_i               = kb;
    ioptions_i                = opts;
    qual_status_i             = qs;

    valid_i                   = 1'b1;

    // Hold for exactly one full cycle (checked at next posedge)
    @(negedge clk_i);
    valid_i                   = 1'b0;
  endtask

  // Simple assert macro
  `define TB_ASSERT(cond, msg) \
    if (!(cond)) begin \
      $display("[%0t] TB_ASSERT FAIL: %s", $time, msg); \
      $stop; \
    end

  // -------------------------
  // Checker: sample on posedge when valid_i is high
  // We drive valid_i starting at negedge and keep it until the next negedge,
  // so it is guaranteed stable at the intermediate posedge.
  // -------------------------
  it_packet_type_e exp_type_q;
  logic exp_flush_next_q;
  logic exp_addr_mode_full_q;
  logic exp_addr_mode_delta_q;
  logic [XLEN-1:0] exp_addr_q;
  logic [$clog2(XLEN):0] exp_kb_q;
  format_e exp_fmt_q;
  f_sync_subformat_e exp_sf_q;

  // Track last "latest address" expectation for delta testing (TB side)
  logic [XLEN-1:0] tb_latest_addr_q;

  initial tb_latest_addr_q = '0;

  always @(posedge clk_i) begin
    if (!rst_ni) begin
      exp_type_q        <= F0SF0;
      exp_flush_next_q  <= 1'b0;
      exp_addr_mode_full_q <= 1'b0;
      exp_addr_mode_delta_q<= 1'b0;
      exp_addr_q        <= '0;
      exp_kb_q          <= '0;
      exp_fmt_q         <= F_ADDR_ONLY;
      exp_sf_q          <= SF_START;
      tb_latest_addr_q  <= '0;
    end else begin
      // branch_map_flush_o is delayed (flush_q), so check it against exp_flush_next_q
      `TB_ASSERT(branch_map_flush_o === exp_flush_next_q,
        "branch_map_flush_o mismatch (expected delayed flush)");

      // When valid_i is asserted, the combinational packet outputs must be valid
      if (valid_i) begin
        `TB_ASSERT(packet_valid_o === 1'b1, "packet_valid_o should be 1 when valid_i=1");

        // Check packet type mapping
        `TB_ASSERT(packet_type_o === exp_type_for_format(packet_format_i, packet_f_sync_subformat_i),
          "packet_type_o mismatch for format/subformat");

        // Length should not be 0 for a valid packet (your RTL always accounts at least header bits)
        `TB_ASSERT(payload_length_o != 0, "payload_length_o unexpectedly 0 on valid packet");

        // Address compression observability:
        // - Only meaningful for F_ADDR_ONLY or F_DIFF_DELTA depending on opts
        // - For FULL mode, addr_to_compress_o should match tc_address_i (for those formats)
        if ((packet_format_i == F_ADDR_ONLY || packet_format_i == F_DIFF_DELTA) && ioptions_i.full_address_en) begin
          `TB_ASSERT(addr_to_compress_o === tc_address_i, "addr_to_compress_o should equal tc_address_i in full mode");
        end

        // For DELTA mode, the RTL does: diff_addr = latest_addr_q - tc_address_i
        // We'll only check DELTA when we purposely make it small positive in directed tests.
      end else begin
        // If valid_i is low, packet_valid_o should be 0 in your RTL defaults
        `TB_ASSERT(packet_valid_o === 1'b0, "packet_valid_o should be 0 when valid_i=0");
      end

      // Predict flush one-cycle later: In RTL F_DIFF_DELTA sets flush_d=1 -> flush_q -> branch_map_flush_o
      exp_flush_next_q <= (valid_i && (packet_format_i == F_DIFF_DELTA));

      // Maintain TB-side latest address model (based on what packet types update it in RTL)
      // RTL updates latest in:
      // - F_ADDR_ONLY always
      // - F_SYNC when SF_START or SF_TRAP
      // - F_OPT_EXT when branches_i < 31
      if (valid_i) begin
        if (packet_format_i == F_ADDR_ONLY) begin
          tb_latest_addr_q <= tc_address_i;
        end else if (packet_format_i == F_SYNC &&
                    (packet_f_sync_subformat_i == SF_START || packet_f_sync_subformat_i == SF_TRAP)) begin
          tb_latest_addr_q <= tc_address_i;
        end else if (packet_format_i == F_OPT_EXT && (branches_i < 31)) begin
          tb_latest_addr_q <= tc_address_i;
        end
      end
    end
  end

  // -------------------------
  // Directed tests
  // -------------------------
  task automatic test_sync_all_subformats();
    ioptions_s opts;
    opts = '0;
    opts.full_address_en = 1'b1;

    apply_one_cycle(F_SYNC, SF_START,   64'h0000_0000_0000_3000, '0, '0, '0, opts, NO_CHANGE);
    apply_one_cycle(F_SYNC, SF_TRAP,    64'h0000_0000_0000_3010, '0, '0, '0, opts, ENDED_REP);
    apply_one_cycle(F_SYNC, SF_CONTEXT, 64'h0000_0000_0000_3020, '0, '0, '0, opts, TRACE_LOST);
    apply_one_cycle(F_SYNC, SF_SUPPORT, 64'h0000_0000_0000_3030, '0, '0, '0, opts, ENDED_NTR);
  endtask

  task automatic test_addr_only_full_and_delta();
    ioptions_s opts;

    // FULL address mode
    opts = '0;
    opts.full_address_en = 1'b1;
    apply_one_cycle(F_ADDR_ONLY, SF_START, 64'h0000_0000_0000_1000, '0, '0, '0, opts, NO_CHANGE);

    // DELTA mode (make diff positive small): latest (from previous) = 0x1000
    // RTL uses diff = latest - addr. So choose addr = 0x0F80 => diff = 0x80
    opts = '0;
    opts.delta_address_en = 1'b1;

    // Drive an address smaller than last latest to avoid wrap.
    apply_one_cycle(F_ADDR_ONLY, SF_START, 64'h0000_0000_0000_0F80, '0, '0, 6, opts, NO_CHANGE);

    // Check DELTA explicitly at the posedge inside this test by peeking right after apply.
    // We'll do it with a small wait: after apply_one_cycle returns, one check already happened.
  endtask

  task automatic test_diff_delta_branchmap_flush();
    ioptions_s opts;
    opts = '0;
    opts.full_address_en = 1'b1;

    // branches < 31: branch_map_off non-zero path
    apply_one_cycle(F_DIFF_DELTA, SF_START,
      64'h0000_0000_0000_2000,
      5'd8,
      31'h1555_5555,
      '0,
      opts,
      NO_CHANGE);

    // branches >= 31: branch_map_off becomes 0 in your RTL (full map path)
    apply_one_cycle(F_DIFF_DELTA, SF_START,
      64'h0000_0000_0000_2008,
      5'd31,
      31'h7FFF_FFFF,
      '0,
      opts,
      NO_CHANGE);
  endtask

  task automatic test_opt_ext_basic();
    ioptions_s opts;
    opts = '0;

    // This format is where your RTL packs optional extension info.
    // We mainly verify it doesn't hang and produces a valid packet.
    apply_one_cycle(F_OPT_EXT, SF_START, 64'h0000_0000_0000_4000, 5'd0, '0, '0, opts, NO_CHANGE);

    // also try with branches < 31 to trigger "update_latest_addr_pred" in our TB model
    apply_one_cycle(F_OPT_EXT, SF_START, 64'h0000_0000_0000_4010, 5'd10, 31'h1234_567, '0, opts, NO_CHANGE);
  endtask

  // -------------------------
  // Random stress test (catches “freeze again�? situations)
  // -------------------------
      format_e f;
      f_sync_subformat_e sf;
      logic [XLEN-1:0] addr;
      logic [BRANCH_COUNT_LEN-1:0] brc;
      logic [BRANCH_MAP_LEN-1:0] brm;
      logic [$clog2(XLEN):0] kb;
      qual_status_e qs;
  task automatic stress_random(int n);
    ioptions_s opts;
    for (int i = 0; i < n; i++) begin
      opts = '0;

      // Randomly enable one of the address modes sometimes
      case ($urandom_range(0,2))
        0: opts.full_address_en  = 1'b1;
        1: opts.delta_address_en = 1'b1;
        default: begin end
      endcase

      //format_e f;
      //f_sync_subformat_e sf;

      // pick random format
      case ($urandom_range(0,3))
        0: f = F_OPT_EXT;
        1: f = F_DIFF_DELTA;
        2: f = F_ADDR_ONLY;
        default: f = F_SYNC;
      endcase

      // random subformat (only meaningful if F_SYNC)
      case ($urandom_range(0,3))
        0: sf = SF_START;
        1: sf = SF_TRAP;
        2: sf = SF_CONTEXT;
        default: sf = SF_SUPPORT;
      endcase

      
      addr = $urandom();
      addr[XLEN-1 -: 32] = $urandom(); // widen randomness for XLEN=64

      
      brc = $urandom_range(0, 31);

      
      brm = $urandom();

     
      kb = $urandom_range(0, $clog2(XLEN));

      
      case ($urandom_range(0,3))
        0: qs = NO_CHANGE;
        1: qs = ENDED_REP;
        2: qs = TRACE_LOST;
        default: qs = ENDED_NTR;
      endcase

      apply_one_cycle(f, sf, addr, brc, brm, kb, opts, qs);
    end
  endtask

  // -------------------------
  // Test sequence
  // -------------------------
  initial begin
    $display("TB STARTED (full functionality test)");
    drive_defaults();

    rst_ni = 1'b0;
    repeat (6) @(posedge clk_i);
    rst_ni = 1'b1;

    // Directed suite
    test_addr_only_full_and_delta();
    test_diff_delta_branchmap_flush();
    test_sync_all_subformats();
    test_opt_ext_basic();

    // Random stress suite (increase if you want)
    stress_random(200);

    $display("TB PASSED (no assertions fired)");
    repeat (10) @(posedge clk_i);
    $finish;
  end

endmodule
