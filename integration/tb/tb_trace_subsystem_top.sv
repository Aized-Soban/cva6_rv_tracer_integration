`timescale 1ns/1ps

module tb_trace_subsystem_top;

  import iti_pkg::*;
  import te_pkg::*;
  import riscv::*;

  localparam int unsigned N                = 1;
  localparam int unsigned ONLY_BRANCHES    = 0;
  localparam int unsigned APB_ADDR_WIDTH   = 32;
  localparam int unsigned DATA_LEN         = 32;
  localparam int unsigned ENCAP_FIFO_DEPTH = 16;
  localparam logic [4:0] HARTID            = 5'd0;
  localparam logic       TRACE_IS_SYSTEM   = 1'b0;
  localparam int unsigned ATID_W           = 7;
  localparam int unsigned SYNC_STAGES      = 2;
  localparam int unsigned ATBYTES_W        = $clog2(DATA_LEN)-3;

  localparam logic [1:0] SEL_NONE = 2'd0;
  localparam logic [1:0] SEL_NBR  = 2'd1;
  localparam logic [1:0] SEL_SYS  = 2'd2;
  localparam logic [1:0] SEL_INS  = 2'd3;

  logic                         trace_clk_i;
  logic                         trace_rst_ni;
  logic                         funnel_clk_i;
  logic                         funnel_rst_ni;

  iti_pkg::rvfi_to_iti_t        rvfi_to_iti_i;
  logic [te_pkg::TIME_LEN-1:0]  time_i;
  logic [te_pkg::XLEN-1:0]      tvec_i;
  logic [te_pkg::XLEN-1:0]      epc_i;

  logic [APB_ADDR_WIDTH-1:0]    paddr_i;
  logic                         pwrite_i;
  logic                         psel_i;
  logic                         penable_i;
  logic [31:0]                  pwdata_i;
  logic                         pready_o;
  logic [31:0]                  prdata_o;

  logic [ATBYTES_W-1:0]         out_atbytes_o;
  logic [DATA_LEN-1:0]          out_atdata_o;
  logic [ATID_W-1:0]            out_atid_o;
  logic                         out_atvalid_o;
  logic                         out_atready_i;
  logic                         out_afvalid_i;
  logic                         out_afready_o;

  logic                         enc_stall_o;
  logic                         nbr_flush_complete_o;
  logic                         sys_flush_complete_o;
  logic                         ins_flush_complete_o;
  logic [1:0]                   funnel_mux_sel_o;

  logic [DATA_LEN-1:0]          captured_data;
  logic [ATBYTES_W-1:0]         captured_bytes;
  logic [ATID_W-1:0]            captured_id;

  integer                       tests_passed;
  integer                       tests_failed;

  trace_subsystem_top #(
    .N                ( N                ),
    .ONLY_BRANCHES    ( ONLY_BRANCHES    ),
    .APB_ADDR_WIDTH   ( APB_ADDR_WIDTH   ),
    .DATA_LEN         ( DATA_LEN         ),
    .ENCAP_FIFO_DEPTH ( ENCAP_FIFO_DEPTH ),
    .HARTID           ( HARTID           ),
    .TRACE_IS_SYSTEM  ( TRACE_IS_SYSTEM  ),
    .ATID_W           ( ATID_W           ),
    .SYNC_STAGES      ( SYNC_STAGES      )
  ) dut (
    .trace_clk_i           ( trace_clk_i           ),
    .trace_rst_ni          ( trace_rst_ni          ),
    .funnel_clk_i          ( funnel_clk_i          ),
    .funnel_rst_ni         ( funnel_rst_ni         ),
    .rvfi_to_iti_i         ( rvfi_to_iti_i         ),
    .time_i                ( time_i                ),
    .tvec_i                ( tvec_i                ),
    .epc_i                 ( epc_i                 ),
    .paddr_i               ( paddr_i               ),
    .pwrite_i              ( pwrite_i              ),
    .psel_i                ( psel_i                ),
    .penable_i             ( penable_i             ),
    .pwdata_i              ( pwdata_i              ),
    .pready_o              ( pready_o              ),
    .prdata_o              ( prdata_o              ),
    .out_atbytes_o         ( out_atbytes_o         ),
    .out_atdata_o          ( out_atdata_o          ),
    .out_atid_o            ( out_atid_o            ),
    .out_atvalid_o         ( out_atvalid_o         ),
    .out_atready_i         ( out_atready_i         ),
    .out_afvalid_i         ( out_afvalid_i         ),
    .out_afready_o         ( out_afready_o         ),
    .enc_stall_o           ( enc_stall_o           ),
    .nbr_flush_complete_o  ( nbr_flush_complete_o  ),
    .sys_flush_complete_o  ( sys_flush_complete_o  ),
    .ins_flush_complete_o  ( ins_flush_complete_o  ),
    .funnel_mux_sel_o      ( funnel_mux_sel_o      )
  );

  initial begin
    $timeformat(-9, 2, " ns", 10);
  end

  initial begin
    trace_clk_i = 1'b0;
    forever #5 trace_clk_i = ~trace_clk_i;
  end

  initial begin
    funnel_clk_i = 1'b0;
    forever #7 funnel_clk_i = ~funnel_clk_i;
  end

  task automatic print_banner(input string name);
    begin
      $display("\n============================================================");
      $display("TESTCASE: %s", name);
      $display("TIME: %0t", $time);
      $display("============================================================");
    end
  endtask

  task automatic clear_inputs;
    begin
      rvfi_to_iti_i  = '0;
      time_i         = '0;
      tvec_i         = '0;
      epc_i          = '0;
      paddr_i        = '0;
      pwrite_i       = 1'b0;
      psel_i         = 1'b0;
      penable_i      = 1'b0;
      pwdata_i       = '0;
      out_atready_i  = 1'b0;
      out_afvalid_i  = 1'b0;
      captured_data  = '0;
      captured_bytes = '0;
      captured_id    = '0;
    end
  endtask

  task automatic apply_reset;
    begin
      trace_rst_ni  = 1'b0;
      funnel_rst_ni = 1'b0;
      clear_inputs();
      repeat (8) @(posedge trace_clk_i);
      repeat (8) @(posedge funnel_clk_i);
      trace_rst_ni  = 1'b1;
      funnel_rst_ni = 1'b1;
      repeat (6) @(posedge trace_clk_i);
      repeat (6) @(posedge funnel_clk_i);
      $display("[%0t] Reset released", $time);
    end
  endtask

  task automatic drive_trace_sample(
    input logic [te_pkg::XLEN-1:0] pc,
    input logic                    branch_taken,
    input logic                    ex_valid,
    input logic [te_pkg::XLEN-1:0] cause,
    input logic [te_pkg::XLEN-1:0] tval,
    input logic [63:0]             cycles
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

      time_i                         <= te_pkg::TIME_LEN'(cycles);
      epc_i                          <= pc;
      tvec_i                         <= pc + 64'h100;

      $display("[DRV ] time=%0t pc=0x%016h branch=%0b ex_valid=%0b cause=0x%016h tval=0x%016h cycles=%0d",
               $time, pc, branch_taken, ex_valid, cause, tval, cycles);

      @(posedge trace_clk_i);
      rvfi_to_iti_i.valid[0]         <= 1'b0;
    end
  endtask

  task automatic wait_encoder_handshake;
    integer timeout;
    begin
      timeout = 0;
      while (!(dut.ins_atvalid && dut.ins_atready) && timeout < 400) begin
        @(posedge trace_clk_i);
        timeout = timeout + 1;
      end

      if (timeout == 400) begin
        $display("[ENC ] FAIL: timeout waiting for encoder handshake");
        tests_failed = tests_failed + 1;
        $fatal;
      end

      captured_id    = dut.ins_atid;
      captured_data  = dut.ins_atdata;
      captured_bytes = dut.ins_atbytes;

      $display("[ENC ] time=%0t id=0x%0h data=0x%08h bytes=%0d valid=%0b ready=%0b",
               $time, captured_id, captured_data, captured_bytes,
               dut.ins_atvalid, dut.ins_atready);
    end
  endtask

  task automatic wait_funnel_valid;
    integer timeout;
    begin
      timeout = 0;
      while (!out_atvalid_o && timeout < 400) begin
        @(posedge funnel_clk_i);
        timeout = timeout + 1;
      end

      if (timeout == 400) begin
        $display("[OUT ] FAIL: timeout waiting for funnel output valid");
        tests_failed = tests_failed + 1;
        $fatal;
      end

      $display("[OUT ] time=%0t sel=%0d id=0x%0h data=0x%08h bytes=%0d valid=%0b ready=%0b",
               $time, funnel_mux_sel_o, out_atid_o, out_atdata_o, out_atbytes_o,
               out_atvalid_o, out_atready_i);
    end
  endtask

  task automatic wait_funnel_handshake;
    integer timeout;
    begin
      timeout = 0;
      while (!(out_atvalid_o && out_atready_i) && timeout < 400) begin
        @(posedge funnel_clk_i);
        timeout = timeout + 1;
      end

      if (timeout == 400) begin
        $display("[OUT ] FAIL: timeout waiting for funnel output handshake");
        tests_failed = tests_failed + 1;
        $fatal;
      end

      $display("[OUT ] HANDSHAKE time=%0t sel=%0d id=0x%0h data=0x%08h bytes=%0d",
               $time, funnel_mux_sel_o, out_atid_o, out_atdata_o, out_atbytes_o);
    end
  endtask

  task automatic check_match(input string tc_name);
    begin
      if ((out_atid_o    === captured_id) &&
          (out_atdata_o  === captured_data) &&
          (out_atbytes_o === captured_bytes)) begin
        $display("[%s] PASS: encoder packet matched funnel output", tc_name);
      end else begin
        $display("[%s] FAIL: encoder/funnel mismatch", tc_name);
        $display("        ENC: id=0x%0h data=0x%08h bytes=%0d", captured_id, captured_data, captured_bytes);
        $display("        OUT: id=0x%0h data=0x%08h bytes=%0d", out_atid_o, out_atdata_o, out_atbytes_o);
        tests_failed = tests_failed + 1;
        $fatal;
      end

      if (funnel_mux_sel_o === SEL_INS) begin
        $display("[%s] PASS: instruction path selected (mux_sel=%0d)", tc_name, funnel_mux_sel_o);
      end else begin
        $display("[%s] FAIL: wrong mux select = %0d", tc_name, funnel_mux_sel_o);
        tests_failed = tests_failed + 1;
        $fatal;
      end

      if ((nbr_flush_complete_o !== 1'b0) || (sys_flush_complete_o !== 1'b0)) begin
        $display("[%s] FAIL: tied-off paths unexpectedly active", tc_name);
        tests_failed = tests_failed + 1;
        $fatal;
      end

      tests_passed = tests_passed + 1;
    end
  endtask

  task automatic wait_output_clear;
    integer timeout;
    begin
      timeout = 0;
      while (out_atvalid_o && timeout < 100) begin
        @(posedge funnel_clk_i);
        timeout = timeout + 1;
      end
      if (timeout == 100) begin
        $display("[WARN] output valid did not clear within timeout");
      end
    end
  endtask

  task automatic tc1_basic;
    begin
      print_banner("TC1_BASIC");
      out_atready_i = 1'b1;

      drive_trace_sample(64'h0000_0000_8000_0014, 1'b0, 1'b0, 64'h0, 64'h0, 64'd5);
      wait_encoder_handshake();
      wait_funnel_handshake();
      check_match("TC1_BASIC");
      wait_output_clear();
    end
  endtask

  task automatic tc2_branch;
    begin
      print_banner("TC2_BRANCH");
      out_atready_i = 1'b1;

      drive_trace_sample(64'h0000_0000_8000_0020, 1'b1, 1'b0, 64'h0, 64'h0, 64'd6);
      wait_encoder_handshake();
      wait_funnel_handshake();
      check_match("TC2_BRANCH");
      wait_output_clear();
    end
  endtask

  task automatic tc3_exception;
    begin
      print_banner("TC3_EXCEPTION");
      out_atready_i = 1'b1;

      drive_trace_sample(64'h0000_0000_8000_0030, 1'b0, 1'b1,
                         64'h0000_0000_0000_0002,
                         64'h0000_0000_DEAD_BEEF,
                         64'd7);
      wait_encoder_handshake();
      wait_funnel_handshake();
      check_match("TC3_EXCEPTION");
      wait_output_clear();
    end
  endtask

  task automatic tc4_idle;
    integer k;
    bit seen_output;
    begin
      print_banner("TC4_IDLE");
      rvfi_to_iti_i = '0;
      out_atready_i = 1'b1;
      seen_output   = 1'b0;

      for (k = 0; k < 40; k++) begin
        @(posedge funnel_clk_i);
        if (out_atvalid_o) seen_output = 1'b1;
      end

      if (!seen_output) begin
        $display("[TC4_IDLE] PASS: no output generated while input valid=0");
        tests_passed = tests_passed + 1;
      end else begin
        $display("[TC4_IDLE] FAIL: unexpected output during idle");
        tests_failed = tests_failed + 1;
        $fatal;
      end
    end
  endtask

  task automatic tc5_backpressure;
    logic [ATID_W-1:0]     hold_id;
    logic [DATA_LEN-1:0]   hold_data;
    logic [ATBYTES_W-1:0]  hold_bytes;
    integer                i;
    bit                    stable_ok;
    begin
      print_banner("TC5_BACKPRESSURE");
      out_atready_i = 1'b0;

      drive_trace_sample(64'h0000_0000_8000_0040, 1'b0, 1'b0, 64'h0, 64'h0, 64'd8);
      wait_encoder_handshake();
      wait_funnel_valid();

      hold_id    = out_atid_o;
      hold_data  = out_atdata_o;
      hold_bytes = out_atbytes_o;
      stable_ok  = 1'b1;

      for (i = 0; i < 5; i++) begin
        @(posedge funnel_clk_i);
        if ((out_atid_o !== hold_id) ||
            (out_atdata_o !== hold_data) ||
            (out_atbytes_o !== hold_bytes) ||
            (out_atvalid_o !== 1'b1)) begin
          stable_ok = 1'b0;
        end
      end

      if (stable_ok) begin
        $display("[TC5_BACKPRESSURE] PASS: output held stable while ready=0");
      end else begin
        $display("[TC5_BACKPRESSURE] FAIL: output changed while ready=0");
        tests_failed = tests_failed + 1;
        $fatal;
      end

      out_atready_i = 1'b1;
      wait_funnel_handshake();
      check_match("TC5_BACKPRESSURE");
      wait_output_clear();
    end
  endtask

  initial begin
    tests_passed = 0;
    tests_failed = 0;

    apply_reset();

    tc1_basic();
    tc2_branch();
    tc3_exception();
    tc4_idle();
    tc5_backpressure();

    $display("\n============================================================");
    $display("TRACE SUBSYSTEM DISPLAY TB SUMMARY");
    $display("PASSED = %0d", tests_passed);
    $display("FAILED = %0d", tests_failed);
    $display("============================================================\n");

    #50;
    $finish;
  end

  initial begin
    #500000;
    $display("TB timeout");
    $fatal;
  end

endmodule
