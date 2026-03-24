`timescale 1ns/1ps

module tb_trace_subsystem_backpressure_debug;

  localparam int DATA_LEN       = 32;
  localparam int APB_ADDR_WIDTH = 32;
  localparam int ENCAP_FIFO_DEPTH = 16;
  localparam int SYNC_STAGES    = 2;
  localparam int ATID_W         = 7;
  localparam int ATBYTES_W      = 2;

  logic trace_clk_i;
  logic funnel_clk_i;
  logic trace_rst_ni;
  logic funnel_rst_ni;

  logic [63:0] time_i;
  logic [63:0] tvec_i;
  logic [63:0] epc_i;

  logic [APB_ADDR_WIDTH-1:0] paddr_i;
  logic pwrite_i;
  logic psel_i;
  logic penable_i;
  logic [31:0] pwdata_i;
  logic pready_o;
  logic [31:0] prdata_o;

  logic [ATID_W-1:0] out_atid_o;
  logic [DATA_LEN-1:0] out_atdata_o;
  logic [ATBYTES_W-1:0] out_atbytes_o;
  logic out_atvalid_o;
  logic out_atready_i;
  logic out_afvalid_i;
  logic out_afready_o;

  logic enc_stall_o;
  logic nbr_flush_complete_o;
  logic sys_flush_complete_o;
  logic ins_flush_complete_o;

  // These package/type names follow the earlier integration work.
  // If your repo uses a different package path, adjust just these imports/types.
  import riscv::*;
  import iti_pkg::*;

  rvfi_to_iti_t rvfi_to_iti_i;

  trace_subsystem_top dut (
    .trace_clk_i          (trace_clk_i),
    .trace_rst_ni         (trace_rst_ni),
    .funnel_clk_i         (funnel_clk_i),
    .funnel_rst_ni        (funnel_rst_ni),
    .rvfi_to_iti_i        (rvfi_to_iti_i),
    .time_i               (time_i),
    .tvec_i               (tvec_i),
    .epc_i                (epc_i),
    .paddr_i              (paddr_i),
    .pwrite_i             (pwrite_i),
    .psel_i               (psel_i),
    .penable_i            (penable_i),
    .pwdata_i             (pwdata_i),
    .pready_o             (pready_o),
    .prdata_o             (prdata_o),
    .out_atid_o           (out_atid_o),
    .out_atdata_o         (out_atdata_o),
    .out_atbytes_o        (out_atbytes_o),
    .out_atvalid_o        (out_atvalid_o),
    .out_atready_i        (out_atready_i),
    .out_afvalid_i        (out_afvalid_i),
    .out_afready_o        (out_afready_o),
    .enc_stall_o          (enc_stall_o),
    .nbr_flush_complete_o (nbr_flush_complete_o),
    .sys_flush_complete_o (sys_flush_complete_o),
    .ins_flush_complete_o (ins_flush_complete_o)
  );

  typedef struct packed {
    logic [ATID_W-1:0]    id;
    logic [DATA_LEN-1:0]  data;
    logic [ATBYTES_W-1:0] bytes;
  } atb_pkt_t;

  atb_pkt_t exp_q[$];
  atb_pkt_t out_q[$];

  int enc_hs_count;
  int out_hs_count;
  int cmp_errors;
  int dup_errors;
  int hold_errors;
  bit monitors_enable;

  logic [ATID_W-1:0]    hold_id;
  logic [DATA_LEN-1:0]  hold_data;
  logic [ATBYTES_W-1:0] hold_bytes;
  bit                   hold_active;

  logic [ATID_W-1:0]    prev_out_id;
  logic [DATA_LEN-1:0]  prev_out_data;
  logic [ATBYTES_W-1:0] prev_out_bytes;
  bit                   prev_out_valid;

  initial begin
    $timeformat(-9, 2, " ns", 10);
  end

  initial begin
    trace_clk_i = 1'b0;
    forever #5 trace_clk_i = ~trace_clk_i;
  end

  initial begin
    funnel_clk_i = 1'b0;
    forever #5 funnel_clk_i = ~funnel_clk_i;
    // For CDC stress later, use instead:
    // forever #7 funnel_clk_i = ~funnel_clk_i;
  end

  task automatic reset_dut;
  begin
    trace_rst_ni    = 1'b0;
    funnel_rst_ni   = 1'b0;
    out_atready_i   = 1'b0;
    out_afvalid_i   = 1'b0;
    rvfi_to_iti_i   = '0;
    time_i          = '0;
    tvec_i          = 64'h0000_0000_8000_0114;
    epc_i           = 64'h0000_0000_8000_0014;
    paddr_i         = '0;
    pwrite_i        = 1'b0;
    psel_i          = 1'b0;
    penable_i       = 1'b0;
    pwdata_i        = '0;
    monitors_enable = 1'b0;
    hold_active     = 1'b0;
    prev_out_valid  = 1'b0;

    repeat (5) @(posedge trace_clk_i);
    trace_rst_ni = 1'b1;
    repeat (5) @(posedge funnel_clk_i);
    funnel_rst_ni = 1'b1;
    repeat (8) @(posedge funnel_clk_i);
    monitors_enable = 1'b1;
    $display("[%0t] Reset released, monitors enabled", $time);
  end
  endtask

  task automatic clear_scoreboard;
  begin
    exp_q.delete();
    out_q.delete();
    enc_hs_count   = 0;
    out_hs_count   = 0;
    cmp_errors     = 0;
    dup_errors     = 0;
    hold_errors    = 0;
    hold_active    = 1'b0;
    prev_out_valid = 1'b0;
  end
  endtask

  task automatic drive_trace_sample(
    input logic [63:0] pc,
    input logic        branch_taken,
    input logic        ex_valid,
    input logic [63:0] cause,
    input logic [63:0] tval,
    input logic [63:0] cycles
  );
  begin
    @(posedge trace_clk_i);
    rvfi_to_iti_i                  <= '0;
    rvfi_to_iti_i.valid[0]         <= 1'b1;
    rvfi_to_iti_i.pc[0]            <= pc;
    rvfi_to_iti_i.is_taken[0]      <= branch_taken;
    rvfi_to_iti_i.is_compressed[0] <= 1'b0;
    rvfi_to_iti_i.priv_lvl         <= riscv::PRIV_LVL_M;
    rvfi_to_iti_i.cycles           <= cycles;
    rvfi_to_iti_i.ex_valid         <= ex_valid;
    rvfi_to_iti_i.cause            <= cause;
    rvfi_to_iti_i.tval             <= tval;

    $display("[DRV ] t=%0t pc=0x%016h branch=%0b ex=%0b cause=0x%016h tval=0x%016h cycles=%0d",
             $time, pc, branch_taken, ex_valid, cause, tval, cycles);

    @(posedge trace_clk_i);
    rvfi_to_iti_i.valid[0] <= 1'b0;
  end
  endtask

  task automatic drive_burst8;
    int i;
  begin
    $display("\n---------------- BURST START (8 samples) ----------------");
    for (i = 0; i < 8; i++) begin
      drive_trace_sample(64'h0000_0000_8000_1000 + (i*4),
                         (i == 1) || (i == 4) || (i == 7),
                         (i == 4),
                         (i == 4) ? 64'h2 : 64'h0,
                         (i == 4) ? 64'h0000_0000_dead_0004 : 64'h0,
                         64'd100 + i);
    end
    $display("---------------- BURST END ----------------\n");
  end
  endtask

  // Expected stream source: encoder-side ATB handshakes.
  always @(posedge funnel_clk_i) begin
    if (!funnel_rst_ni) begin
      // nothing
    end else if (monitors_enable) begin
      if (dut.ins_atvalid && dut.ins_atready) begin
        atb_pkt_t pkt;
        pkt.id    = dut.ins_atid;
        pkt.data  = dut.ins_atdata;
        pkt.bytes = dut.ins_atbytes;
        exp_q.push_back(pkt);
        enc_hs_count <= enc_hs_count + 1;
        $display("[ENC ] t=%0t idx=%0d id=0x%0h data=0x%08h bytes=%0d",
                 $time, exp_q.size(), pkt.id, pkt.data, pkt.bytes);
      end
    end
  end

  // Hold-stability monitor.
  always @(posedge funnel_clk_i) begin
    if (!funnel_rst_ni || !monitors_enable) begin
      hold_active <= 1'b0;
    end else begin
      if (out_atvalid_o && !out_atready_i) begin
        if (!hold_active) begin
          hold_active <= 1'b1;
          hold_id     <= out_atid_o;
          hold_data   <= out_atdata_o;
          hold_bytes  <= out_atbytes_o;
        end else begin
          if ((out_atid_o !== hold_id) ||
              (out_atdata_o !== hold_data) ||
              (out_atbytes_o !== hold_bytes)) begin
            hold_errors <= hold_errors + 1;
            $display("[HOLD] FAIL t=%0t output changed while valid=1 and ready=0", $time);
            $display("       expected hold: id=0x%0h data=0x%08h bytes=%0d", hold_id, hold_data, hold_bytes);
            $display("       got          : id=0x%0h data=0x%08h bytes=%0d", out_atid_o, out_atdata_o, out_atbytes_o);
          end
        end
      end else begin
        hold_active <= 1'b0;
      end
    end
  end

  // Output monitor + scoreboard + duplicate detection.
  always @(posedge funnel_clk_i) begin
    if (!funnel_rst_ni || !monitors_enable) begin
      prev_out_valid <= 1'b0;
    end else if (out_atvalid_o && out_atready_i) begin
      atb_pkt_t got;
      atb_pkt_t exp;
      got.id    = out_atid_o;
      got.data  = out_atdata_o;
      got.bytes = out_atbytes_o;
      out_q.push_back(got);
      out_hs_count <= out_hs_count + 1;

      $display("[OUT ] t=%0t idx=%0d mux_sel=%0d id=0x%0h data=0x%08h bytes=%0d",
               $time, out_q.size()-1, dut.funnel_mux_sel_o, got.id, got.data, got.bytes);

      if (prev_out_valid &&
          (got.id    === prev_out_id) &&
          (got.data  === prev_out_data) &&
          (got.bytes === prev_out_bytes)) begin
        dup_errors <= dup_errors + 1;
        $display("[DUP ] FAIL t=%0t repeated consecutive output handshake", $time);
      end

      prev_out_valid <= 1'b1;
      prev_out_id    <= got.id;
      prev_out_data  <= got.data;
      prev_out_bytes <= got.bytes;

      if (exp_q.size() == 0) begin
        cmp_errors <= cmp_errors + 1;
        $display("[CMP ] FAIL: output packet arrived before expected queue entry existed");
      end else begin
        exp = exp_q.pop_front();
        if ((got.id === exp.id) && (got.data === exp.data) && (got.bytes === exp.bytes)) begin
          $display("[CMP ] PASS: matched");
        end else begin
          cmp_errors <= cmp_errors + 1;
          $display("[CMP ] FAIL: packet mismatch");
          $display("       EXP: id=0x%0h data=0x%08h bytes=%0d", exp.id, exp.data, exp.bytes);
          $display("       GOT: id=0x%0h data=0x%08h bytes=%0d", got.id, got.data, got.bytes);
        end
      end
    end
  end

  task automatic wait_encoder_quiet(input int quiet_cycles, input int timeout_cycles);
    int quiet;
    int total;
    int last_cnt;
  begin
    quiet    = 0;
    total    = 0;
    last_cnt = enc_hs_count;
    while ((quiet < quiet_cycles) && (total < timeout_cycles)) begin
      @(posedge funnel_clk_i);
      total = total + 1;
      if (enc_hs_count == last_cnt) quiet = quiet + 1;
      else begin
        quiet = 0;
        last_cnt = enc_hs_count;
      end
    end
    if (quiet >= quiet_cycles)
      $display("[WAIT] PASS: encoder stream quiet after %0d accepted beats", enc_hs_count);
    else
      $display("[WAIT] FAIL: encoder stream did not go quiet in time");
  end
  endtask

  task automatic wait_output_drain(input int timeout_cycles);
    int total;
  begin
    total = 0;
    while ((exp_q.size() != 0) && (total < timeout_cycles)) begin
      @(posedge funnel_clk_i);
      total = total + 1;
    end
    if (exp_q.size() == 0)
      $display("[WAIT] PASS: output drained. queued+consumed OK, out_hs=%0d", out_hs_count);
    else
      $display("[WAIT] FAIL: output did not drain. remaining=%0d", exp_q.size());
  end
  endtask

  task automatic summary_and_check(input string name);
  begin
    $display("\n============================================================");
    $display("SUMMARY: %s", name);
    $display(" encoder handshakes = %0d", enc_hs_count);
    $display(" output  handshakes = %0d", out_hs_count);
    $display(" remaining expected = %0d", exp_q.size());
    $display(" compare errors     = %0d", cmp_errors);
    $display(" duplicate errors   = %0d", dup_errors);
    $display(" hold errors        = %0d", hold_errors);
    $display("============================================================\n");
  end
  endtask

  task automatic tc_hold_stability;
  begin
    clear_scoreboard();
    $display("\n============================================================");
    $display("TEST A: HOLD-STABILITY UNDER STALL");
    $display("============================================================");

    out_atready_i = 1'b1;
    drive_burst8();

    // Wait until one packet reaches output, then stall while valid remains asserted.
    wait (out_atvalid_o === 1'b1);
    @(posedge funnel_clk_i);
    out_atready_i = 1'b0;
    repeat (8) @(posedge funnel_clk_i);
    out_atready_i = 1'b1;

    wait_encoder_quiet(6, 400);
    wait_output_drain(600);
    summary_and_check("TEST A");
  end
  endtask

  task automatic tc_single_pulse_release;
    int k;
  begin
    clear_scoreboard();
    $display("\n============================================================");
    $display("TEST B: SINGLE-CYCLE READY PULSE RELEASE");
    $display("============================================================");

    out_atready_i = 1'b0;
    drive_burst8();
    wait_encoder_quiet(6, 400);

    // Drain using one-cycle ready pulses; catches replay/double-pop bugs.
    for (k = 0; k < 24; k++) begin
      @(posedge funnel_clk_i);
      out_atready_i = 1'b1;
      @(posedge funnel_clk_i);
      out_atready_i = 1'b0;
      repeat (2) @(posedge funnel_clk_i);
    end

    out_atready_i = 1'b1;
    wait_output_drain(800);
    summary_and_check("TEST B");
  end
  endtask

  task automatic tc_toggle_backpressure;
    int k;
  begin
    clear_scoreboard();
    $display("\n============================================================");
    $display("TEST C: PERIODIC BACKPRESSURE TOGGLE");
    $display("============================================================");

    fork
      begin
        out_atready_i = 1'b1;
        forever begin
          repeat (3) @(posedge funnel_clk_i);
          out_atready_i = 1'b0;
          repeat (2) @(posedge funnel_clk_i);
          out_atready_i = 1'b1;
        end
      end
      begin
        drive_burst8();
        wait_encoder_quiet(6, 400);
        wait_output_drain(800);
      end
    join_any
    disable fork;

    out_atready_i = 1'b1;
    summary_and_check("TEST C");
  end
  endtask

  task automatic tc_long_stall_midstream;
  begin
    clear_scoreboard();
    $display("\n============================================================");
    $display("TEST D: LONG MID-STREAM STALL THEN RELEASE");
    $display("============================================================");

    out_atready_i = 1'b1;
    fork
      begin
        drive_burst8();
      end
      begin
        wait (out_hs_count >= 2);
        @(posedge funnel_clk_i);
        out_atready_i = 1'b0;
        repeat (12) @(posedge funnel_clk_i);
        out_atready_i = 1'b1;
      end
    join

    wait_encoder_quiet(6, 400);
    wait_output_drain(800);
    summary_and_check("TEST D");
  end
  endtask

  initial begin
    reset_dut();

    tc_hold_stability();
    tc_single_pulse_release();
    tc_toggle_backpressure();
    tc_long_stall_midstream();

    $display("All focused backpressure tests completed.");
    #100;
    $finish;
  end

endmodule
