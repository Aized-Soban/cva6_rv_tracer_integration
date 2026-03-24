`timescale 1ns/1ps

module tb_trace_subsystem_debug;

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
  localparam int unsigned MAX_PKTS         = 128;

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

  int                           exp_wr_idx;
  int                           exp_rd_idx;
  int                           enc_hs_count;
  int                           out_hs_count;
  int                           err_count;

  logic [ATID_W-1:0]            exp_id    [0:MAX_PKTS-1];
  logic [DATA_LEN-1:0]          exp_data  [0:MAX_PKTS-1];
  logic [ATBYTES_W-1:0]         exp_bytes [0:MAX_PKTS-1];

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

  // --------------------------------------------------------------------------
  // Clocking
  // NOTE:
  //   For clean datapath debug, keep both clocks identical first.
  //   After this passes, change funnel clock to #7 for CDC stress.
  // --------------------------------------------------------------------------
  initial begin
    trace_clk_i = 1'b0;
    forever #5 trace_clk_i = ~trace_clk_i;
  end

  initial begin
    funnel_clk_i = 1'b0;
    forever #5 funnel_clk_i = ~funnel_clk_i;
    // For CDC stress later, use this instead:
     //forever #7 funnel_clk_i = ~funnel_clk_i;
  end

  task automatic clear_inputs;
    begin
      rvfi_to_iti_i = '0;
      time_i        = '0;
      tvec_i        = '0;
      epc_i         = '0;
      paddr_i       = '0;
      pwrite_i      = 1'b0;
      psel_i        = 1'b0;
      penable_i     = 1'b0;
      pwdata_i      = '0;
      out_atready_i = 1'b1;
      out_afvalid_i = 1'b0;
    end
  endtask

  task automatic reset_dut;
    begin
      trace_rst_ni  = 1'b0;
      funnel_rst_ni = 1'b0;
      clear_inputs();
      exp_wr_idx    = 0;
      exp_rd_idx    = 0;
      enc_hs_count  = 0;
      out_hs_count  = 0;
      err_count     = 0;

      repeat (8) @(posedge trace_clk_i);
      trace_rst_ni  = 1'b1;
      funnel_rst_ni = 1'b1;
      repeat (6) @(posedge trace_clk_i);
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

      time_i <= te_pkg::TIME_LEN'(cycles);
      epc_i  <= pc;
      tvec_i <= pc + 64'h100;

      $display("[DRV ] t=%0t pc=0x%016h branch=%0b ex=%0b cause=0x%016h tval=0x%016h cycles=%0d",
               $time, pc, branch_taken, ex_valid, cause, tval, cycles);

      @(posedge trace_clk_i);
      rvfi_to_iti_i.valid[0] <= 1'b0;
    end
  endtask

  task automatic drive_burst(input int num_pkts);
    int i;
    logic branch_taken;
    logic ex_valid;
    logic [63:0] pc;
    begin
      $display("\n---------------- BURST START (%0d packets) ----------------", num_pkts);
      for (i = 0; i < num_pkts; i++) begin
        pc           = 64'h0000_0000_8000_1000 + (i * 64'h4);
        branch_taken = (i % 3 == 1);
        ex_valid     = (i == (num_pkts/2));
        drive_trace_sample(pc,
                           branch_taken,
                           ex_valid,
                           ex_valid ? 64'h2 : 64'h0,
                           ex_valid ? (64'hDEAD_0000 + i) : 64'h0,
                           64'd100 + i);
      end
      $display("---------------- BURST END ----------------\n");
    end
  endtask

  task automatic wait_until_drained(input int expected_count, input int timeout_cycles);
    int timeout;
    begin
      timeout = 0;
      while ((out_hs_count < expected_count) && (timeout < timeout_cycles)) begin
        @(posedge funnel_clk_i);
        timeout = timeout + 1;
      end

      if (out_hs_count < expected_count) begin
        $display("[WAIT] FAIL: output did not drain. expected=%0d observed=%0d timeout_cycles=%0d",
                 expected_count, out_hs_count, timeout_cycles);
        err_count = err_count + 1;
      end else begin
        $display("[WAIT] PASS: output drained. expected=%0d observed=%0d", expected_count, out_hs_count);
      end
    end
  endtask

  task automatic print_summary(input string name);
    begin
      $display("\n============================================================");
      $display("SUMMARY: %s", name);
      $display(" encoder handshakes = %0d", enc_hs_count);
      $display(" output  handshakes = %0d", out_hs_count);
      $display(" expected queued    = %0d", exp_wr_idx);
      $display(" expected consumed  = %0d", exp_rd_idx);
      $display(" errors             = %0d", err_count);
      $display("============================================================\n");
    end
  endtask

  task automatic run_always_ready_test;
    begin
      $display("\n============================================================");
      $display("TEST 1: SAME-CLOCK, ALWAYS-READY, BURST COMPARISON");
      $display("============================================================");

      out_atready_i = 1'b1;
      drive_burst(10);
      wait_until_drained(10, 400);
      print_summary("TEST 1");

      if ((enc_hs_count !== 10) || (out_hs_count !== 10) || (err_count !== 0)) begin
        $display("[TEST 1] FAIL");
        $fatal;
      end else begin
        $display("[TEST 1] PASS\n");
      end
    end
  endtask

  task automatic run_backpressure_test;
    begin
      $display("\n============================================================");
      $display("TEST 2: SAME-CLOCK, BACKPRESSURE, BURST COMPARISON");
      $display("============================================================");

      // reset counters only, keep DUT alive
      exp_wr_idx   = 0;
      exp_rd_idx   = 0;
      enc_hs_count = 0;
      out_hs_count = 0;
      err_count    = 0;

      fork
        begin : ready_pattern
          out_atready_i = 1'b1;
          repeat (3) @(posedge funnel_clk_i);
          out_atready_i = 1'b0;
          repeat (8) @(posedge funnel_clk_i);
          out_atready_i = 1'b1;
          repeat (4) @(posedge funnel_clk_i);
          out_atready_i = 1'b0;
          repeat (6) @(posedge funnel_clk_i);
          out_atready_i = 1'b1;
        end
        begin : traffic
          drive_burst(8);
        end
      join

      wait_until_drained(8, 500);
      print_summary("TEST 2");

      if ((enc_hs_count !== 8) || (out_hs_count !== 8) || (err_count !== 0)) begin
        $display("[TEST 2] FAIL");
        $fatal;
      end else begin
        $display("[TEST 2] PASS\n");
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // Monitors
  // --------------------------------------------------------------------------
  // Capture what encoder really hands to the funnel.
  always @(posedge trace_clk_i) begin
    if (!trace_rst_ni) begin
      exp_wr_idx   <= 0;
      enc_hs_count <= 0;
    end else if (dut.ins_atvalid && dut.ins_atready) begin
      if (exp_wr_idx < MAX_PKTS) begin
        exp_id[exp_wr_idx]    <= dut.ins_atid;
        exp_data[exp_wr_idx]  <= dut.ins_atdata;
        exp_bytes[exp_wr_idx] <= dut.ins_atbytes;
        $display("[ENC ] t=%0t idx=%0d id=0x%0h data=0x%08h bytes=%0d",
                 $time, exp_wr_idx, dut.ins_atid, dut.ins_atdata, dut.ins_atbytes);
        exp_wr_idx   <= exp_wr_idx + 1;
        enc_hs_count <= enc_hs_count + 1;
      end else begin
        $display("[ENC ] FAIL: expected packet queue overflow");
        err_count <= err_count + 1;
      end
    end
  end

  // Compare final funnel output against captured encoder packets in order.
  always @(posedge funnel_clk_i) begin
    if (!funnel_rst_ni) begin
      exp_rd_idx   <= 0;
      out_hs_count <= 0;
    end else if (out_atvalid_o && out_atready_i) begin
      $display("[OUT ] t=%0t idx=%0d mux_sel=%0d id=0x%0h data=0x%08h bytes=%0d",
               $time, exp_rd_idx, funnel_mux_sel_o, out_atid_o, out_atdata_o, out_atbytes_o);

      if (exp_rd_idx >= exp_wr_idx) begin
        $display("[CMP ] FAIL: output packet arrived before expected queue was populated");
        err_count <= err_count + 1;
      end else if ((out_atid_o    !== exp_id[exp_rd_idx]) ||
                   (out_atdata_o  !== exp_data[exp_rd_idx]) ||
                   (out_atbytes_o !== exp_bytes[exp_rd_idx])) begin
        $display("[CMP ] FAIL: packet mismatch at idx=%0d", exp_rd_idx);
        $display("       EXP: id=0x%0h data=0x%08h bytes=%0d",
                 exp_id[exp_rd_idx], exp_data[exp_rd_idx], exp_bytes[exp_rd_idx]);
        $display("       GOT: id=0x%0h data=0x%08h bytes=%0d",
                 out_atid_o, out_atdata_o, out_atbytes_o);
        err_count <= err_count + 1;
      end else begin
        $display("[CMP ] PASS: packet idx=%0d matched", exp_rd_idx);
      end

      exp_rd_idx   <= exp_rd_idx + 1;
      out_hs_count <= out_hs_count + 1;
    end
  end

  initial begin
    reset_dut();
    run_always_ready_test();
    run_backpressure_test();

    $display("All trace_subsystem debug tests completed.");
    #50;
    $finish;
  end

  initial begin
    #500000;
    $display("TB timeout");
    $fatal;
  end
  logic monitors_enable;

initial begin
  monitors_enable = 1'b0;
  trace_rst_ni    = 1'b0;
  funnel_rst_ni   = 1'b0;

  repeat (5) @(posedge trace_clk_i);
  trace_rst_ni = 1'b1;

  repeat (5) @(posedge funnel_clk_i);
  funnel_rst_ni = 1'b1;

  repeat (4) @(posedge funnel_clk_i);
  monitors_enable = 1'b1;

  $display("[%0t] Reset released, monitors enabled", $time);
end

always @(posedge funnel_clk_i) begin
  if (!funnel_rst_ni) begin
    // reset state
  end else if (monitors_enable) begin
    if (dut.ins_atvalid && dut.ins_atready) begin
      // count encoder-side accepted packet
    end

    if (out_atvalid_o && out_atready_i) begin
      // count final output packet
    end
  end
end
endmodule
