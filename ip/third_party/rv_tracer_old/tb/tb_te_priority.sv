`timescale 1ns/1ps
import te_pkg::*;


// ------------------------------------------------------------
// Testbench
// ------------------------------------------------------------
module tb_te_priority;
  import te_pkg::*;

  // Clock/reset
  logic clk_i;
  logic rst_ni;

  // DUT inputs
  logic valid_i;

  // lc
  logic lc_exception_i;
  logic lc_updiscon_i;

  // tc
  logic tc_qualified_i;
  logic tc_exception_i;
  logic [te_pkg::IRETIRE_LEN-1:0] tc_retired_i;
  logic tc_first_qualified_i;
  logic tc_privchange_i;
  logic tc_gt_max_resync_i;
  logic tc_et_max_resync_i;
  logic tc_branch_map_empty_i;
  logic tc_branch_map_full_i;

  // support triggers
  logic tc_enc_enabled_i;
  logic tc_enc_disabled_i;
  logic tc_opmode_change_i;
  logic tc_final_qualified_i;
  logic tc_packets_lost_i;

  // nc
  logic nc_exception_i;
  logic nc_privchange_i;
  logic nc_branch_map_empty_i;
  logic nc_qualified_i;
  logic [te_pkg::IRETIRE_LEN-1:0] nc_retired_i;

  // compress
  logic [te_pkg::XLEN:0] addr_to_compress_i;

  // DUT outputs
  logic                      valid_o;
  te_pkg::format_e           packet_format_o;
  te_pkg::f_sync_subformat_e packet_f_sync_subformat_o;
  logic                      thaddr_o;
  logic                      lc_tc_mux_o;
  logic                      resync_timer_rst_o;
  te_pkg::qual_status_e      qual_status_o;
  logic                      tc_resync_o;
  logic [$clog2(te_pkg::XLEN):0] keep_bits_o;

  // ----------------------------------------------------------
  // Instantiate DUT (your uploaded module)
  // ----------------------------------------------------------
  te_priority dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .valid_i(valid_i),

    .lc_exception_i(lc_exception_i),
    .lc_updiscon_i(lc_updiscon_i),

    .tc_qualified_i(tc_qualified_i),
    .tc_exception_i(tc_exception_i),
    .tc_retired_i(tc_retired_i),
    .tc_first_qualified_i(tc_first_qualified_i),
    .tc_privchange_i(tc_privchange_i),
    .tc_gt_max_resync_i(tc_gt_max_resync_i),
    .tc_et_max_resync_i(tc_et_max_resync_i),
    .tc_branch_map_empty_i(tc_branch_map_empty_i),
    .tc_branch_map_full_i(tc_branch_map_full_i),

    .tc_enc_enabled_i(tc_enc_enabled_i),
    .tc_enc_disabled_i(tc_enc_disabled_i),
    .tc_opmode_change_i(tc_opmode_change_i),
    .tc_final_qualified_i(tc_final_qualified_i),
    .tc_packets_lost_i(tc_packets_lost_i),

    .nc_exception_i(nc_exception_i),
    .nc_privchange_i(nc_privchange_i),
    .nc_branch_map_empty_i(nc_branch_map_empty_i),
    .nc_qualified_i(nc_qualified_i),
    .nc_retired_i(nc_retired_i),

    .addr_to_compress_i(addr_to_compress_i),

    .valid_o(valid_o),
    .packet_format_o(packet_format_o),
    .packet_f_sync_subformat_o(packet_f_sync_subformat_o),
    .thaddr_o(thaddr_o),
    .lc_tc_mux_o(lc_tc_mux_o),
    .resync_timer_rst_o(resync_timer_rst_o),
    .qual_status_o(qual_status_o),
    .tc_resync_o(tc_resync_o),
    .keep_bits_o(keep_bits_o)
  );

  // ----------------------------------------------------------
  // Clock
  // ----------------------------------------------------------
  initial clk_i = 0;
  always #5 clk_i = ~clk_i;  // 100 MHz

  // ----------------------------------------------------------
  // Utility: pretty-print packet decision
  // ----------------------------------------------------------
  function string fmt_to_str(te_pkg::format_e f);
    case (f)
      F_OPT_EXT:    return "F0 (OPT_EXT)";
      F_DIFF_DELTA: return "F1 (DIFF_DELTA)";
      F_ADDR_ONLY:  return "F2 (ADDR_ONLY)";
      F_SYNC:       return "F3 (SYNC)";
      default:      return "UNKNOWN";
    endcase
  endfunction

  function string sf_to_str(te_pkg::f_sync_subformat_e sf);
    case (sf)
      SF_START:   return "SF_START";
      SF_TRAP:    return "SF_TRAP";
      SF_CONTEXT: return "SF_CONTEXT";
      SF_SUPPORT: return "SF_SUPPORT";
      default:    return "SF_?";
    endcase
  endfunction

  task automatic show;
    if (valid_o) begin
      if (packet_format_o == F_SYNC)
        $display("[%0t] EMIT: %s / %s  thaddr=%0b  lc_tc_mux=%0b  resync_rst=%0b  qual_status=%0d  keep_bits=%0d",
                  $time, fmt_to_str(packet_format_o), sf_to_str(packet_f_sync_subformat_o),
                  thaddr_o, lc_tc_mux_o, resync_timer_rst_o, qual_status_o, keep_bits_o);
      else
        $display("[%0t] EMIT: %s            lc_tc_mux=%0b  resync_rst=%0b  keep_bits=%0d",
                  $time, fmt_to_str(packet_format_o), lc_tc_mux_o, resync_timer_rst_o, keep_bits_o);
    end else begin
      $display("[%0t] EMIT: (none)", $time);
    end
  endtask

  // Drive defaults each cycle (so test stays readable)
  task automatic drive_defaults;
    valid_i = 1;

    lc_exception_i = 0;
    lc_updiscon_i  = 0;

    tc_qualified_i        = 1;
    tc_exception_i        = 0;
    tc_retired_i          = 0;
    tc_first_qualified_i  = 0;
    tc_privchange_i       = 0;
    tc_gt_max_resync_i    = 0;
    tc_et_max_resync_i    = 0;
    tc_branch_map_empty_i = 0;
    tc_branch_map_full_i  = 0;

    tc_enc_enabled_i     = 0;
    tc_enc_disabled_i    = 0;
    tc_opmode_change_i   = 0;
    tc_final_qualified_i = 0;
    tc_packets_lost_i    = 0;

    nc_exception_i        = 0;
    nc_privchange_i       = 0;
    nc_branch_map_empty_i = 0;
    nc_qualified_i        = 1;
    nc_retired_i          = 0;

    addr_to_compress_i = 33'h0000_1234; // just demo
  endtask

  // Advance one cycle and print output
  task automatic step(string label);
    @(negedge clk_i);
    $display("\n--- %s ---", label);
    @(posedge clk_i);
    #1; // allow combinational settle
    show();
  endtask

  // ----------------------------------------------------------
  // Main test sequence
  // ----------------------------------------------------------
  initial begin
    // Reset
    drive_defaults();
    rst_ni = 0;
    @(posedge clk_i);
    @(posedge clk_i);
    rst_ni = 1;

    // 1) SUPPORT packet: encoder enabled => F3/SF_SUPPORT
    drive_defaults();
    tc_enc_enabled_i = 1;
    step("Support packet (encoder enabled) => F3/SF_SUPPORT");

    // 2) START packet: first qualified => F3/SF_START
    drive_defaults();
    tc_first_qualified_i = 1;
    step("Start packet (first qualified) => F3/SF_START");

    // 3) TRAP packet, exception-only with lc_exception=1
    //    Here: lc_exception_i=1 AND tc_exc_only=1 -> F3/SF_TRAP, thaddr=0, lc_tc_mux=0
    drive_defaults();
    lc_exception_i  = 1;
    tc_exception_i  = 1;
    tc_retired_i    = 0; // exc_only
    step("Trap packet (lc_exception + tc_exc_only) => F3/SF_TRAP thaddr=0");

    // 4) TRAP packet "not reported yet" path -> thaddr=1
    //    Make lc_exception=1 but tc_exc_only=0 and tc_reported_q is still 0 after reset.
    //    This should hit the 'else // not reported' and set thaddr=1.
    drive_defaults();
    lc_exception_i  = 1;
    tc_exception_i  = 1;
    tc_retired_i    = 1; // NOT exc_only
    step("Trap packet (lc_exception, not reported yet) => F3/SF_TRAP thaddr=1");

    // 5) Normal delta packet: no special events, branch map NOT empty => F1
    drive_defaults();
    tc_branch_map_empty_i = 0; // has branches
    step("Normal packet with branch-map => F1 (DIFF_DELTA)");

    // 6) Address-only: branch map empty in a condition that forces packet selection
    //    Use lc_updiscon_i=1 to force packet emission; then empty branch map => F2
    drive_defaults();
    lc_updiscon_i          = 1;
    tc_branch_map_empty_i  = 1;
    step("PC discontinuity + empty branch-map => F2 (ADDR_ONLY)");

    // 7) Flush before becoming unqualified next cycle:
    //    nc_qualified_i=0 causes emission; pick F1 if current has branches
    drive_defaults();
    nc_qualified_i = 0;
    tc_branch_map_empty_i = 0;
    step("Next cycle unqualified => emit now (F1 if branches exist)");

    // Done
    $display("\nAll tests done.");
    $finish;
  end

endmodule
