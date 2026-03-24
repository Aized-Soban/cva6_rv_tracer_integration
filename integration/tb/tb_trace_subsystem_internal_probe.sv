`timescale 1ns/1ps

module tb_trace_subsystem_internal_probe;

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
  localparam int unsigned MAX_PKTS         = 256;

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

  logic                         monitors_enable;
  integer                       cycle_no;
  integer                       enc_hs_count;
  integer                       out_hs_count;
  integer                       cmp_errors;
  integer                       duplicate_errors;
  integer                       hold_errors;
  integer                       exp_wr_idx;
  integer                       exp_rd_idx;

  logic [ATID_W-1:0]            exp_id    [0:MAX_PKTS-1];
  logic [DATA_LEN-1:0]          exp_data  [0:MAX_PKTS-1];
  logic [ATBYTES_W-1:0]         exp_bytes [0:MAX_PKTS-1];

  logic                         prev_out_valid;
  logic [ATID_W-1:0]            prev_out_id;
  logic [DATA_LEN-1:0]          prev_out_data;
  logic [ATBYTES_W-1:0]         prev_out_bytes;
  logic                         stall_active;
  logic [ATID_W-1:0]            stall_id;
  logic [DATA_LEN-1:0]          stall_data;
  logic [ATBYTES_W-1:0]         stall_bytes;

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
    forever #5 funnel_clk_i = ~funnel_clk_i;
    // For CDC stress later:
    // forever #7 funnel_clk_i = ~funnel_clk_i;
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

  task automatic clear_stats;
    integer i;
    begin
      enc_hs_count      = 0;
      out_hs_count      = 0;
      cmp_errors        = 0;
      duplicate_errors  = 0;
      hold_errors       = 0;
      exp_wr_idx        = 0;
      exp_rd_idx        = 0;
      cycle_no          = 0;
      prev_out_valid    = 1'b0;
      stall_active      = 1'b0;
      prev_out_id       = '0;
      prev_out_data     = '0;
      prev_out_bytes    = '0;
      stall_id          = '0;
      stall_data        = '0;
      stall_bytes       = '0;
      for (i = 0; i < MAX_PKTS; i++) begin
        exp_id[i]    = '0;
        exp_data[i]  = '0;
        exp_bytes[i] = '0;
      end
    end
  endtask

  task automatic do_reset;
    begin
      clear_inputs();
      clear_stats();
      monitors_enable = 1'b0;
      trace_rst_ni    = 1'b0;
      funnel_rst_ni   = 1'b0;

      repeat (6) @(posedge trace_clk_i);
      trace_rst_ni = 1'b1;
      repeat (6) @(posedge funnel_clk_i);
      funnel_rst_ni = 1'b1;
      repeat (6) @(posedge funnel_clk_i);
      monitors_enable = 1'b1;
      $display("[%0t] Reset released, monitors enabled", $time);
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

  task automatic drive_burst_8;
    begin
      $display("\n---------------- BURST START (8 samples) ----------------");
      drive_trace_sample(64'h0000_0000_8000_1000, 1'b0, 1'b0, 64'h0, 64'h0,             64'd100);
      drive_trace_sample(64'h0000_0000_8000_1004, 1'b1, 1'b0, 64'h0, 64'h0,             64'd101);
      drive_trace_sample(64'h0000_0000_8000_1008, 1'b0, 1'b0, 64'h0, 64'h0,             64'd102);
      drive_trace_sample(64'h0000_0000_8000_100c, 1'b0, 1'b0, 64'h0, 64'h0,             64'd103);
      drive_trace_sample(64'h0000_0000_8000_1010, 1'b1, 1'b1, 64'h2, 64'h0000_0000_dead_0004, 64'd104);
      drive_trace_sample(64'h0000_0000_8000_1014, 1'b0, 1'b0, 64'h0, 64'h0,             64'd105);
      drive_trace_sample(64'h0000_0000_8000_1018, 1'b0, 1'b0, 64'h0, 64'h0,             64'd106);
      drive_trace_sample(64'h0000_0000_8000_101c, 1'b1, 1'b0, 64'h0, 64'h0,             64'd107);
      $display("---------------- BURST END ----------------\n");
    end
  endtask

  task automatic wait_encoder_quiet(input int quiet_cycles);
    int quiet;
    begin
      quiet = 0;
      while (quiet < quiet_cycles) begin
        @(posedge funnel_clk_i);
        if (dut.ins_atvalid && dut.ins_atready)
          quiet = 0;
        else
          quiet = quiet + 1;
      end
      $display("[WAIT] encoder stream quiet after %0d accepted beats", enc_hs_count);
    end
  endtask

  task automatic wait_output_drain(input int timeout_cycles);
    int t;
    begin
      t = 0;
      while ((exp_rd_idx != exp_wr_idx) && (t < timeout_cycles)) begin
        @(posedge funnel_clk_i);
        t = t + 1;
      end
      if (exp_rd_idx == exp_wr_idx)
        $display("[WAIT] output drained. consumed=%0d queued=%0d out_hs=%0d", exp_rd_idx, exp_wr_idx, out_hs_count);
      else
        $display("[WAIT] FAIL: timeout drain. consumed=%0d queued=%0d out_hs=%0d", exp_rd_idx, exp_wr_idx, out_hs_count);
    end
  endtask

  // Encoder-side accepted packet monitor = golden stream
  always @(posedge funnel_clk_i) begin
    if (!funnel_rst_ni) begin
      enc_hs_count <= 0;
      exp_wr_idx   <= 0;
    end else if (monitors_enable) begin
      if (dut.ins_atvalid && dut.ins_atready) begin
        if (exp_wr_idx < MAX_PKTS) begin
          exp_id[exp_wr_idx]    <= dut.ins_atid;
          exp_data[exp_wr_idx]  <= dut.ins_atdata;
          exp_bytes[exp_wr_idx] <= dut.ins_atbytes;
        end
        $display("[ENC ] t=%0t idx=%0d id=0x%0h data=0x%08h bytes=%0d",
                 $time, exp_wr_idx, dut.ins_atid, dut.ins_atdata, dut.ins_atbytes);
        enc_hs_count <= enc_hs_count + 1;
        exp_wr_idx   <= exp_wr_idx + 1;
      end
    end
  end

  // Probe internal funnel state every destination clock when something interesting is happening.
  always @(posedge funnel_clk_i) begin
    if (!funnel_rst_ni) begin
      cycle_no <= 0;
    end else if (monitors_enable) begin
      cycle_no <= cycle_no + 1;
      if (dut.i_atb_funnel_top.mux_atvalid || out_atvalid_o || dut.i_atb_funnel_top.fifo_push || dut.i_atb_funnel_top.fifo_pop || !out_atready_i) begin
        $display("[PROBE] cyc=%0d t=%0t | ins_dst v/r=%0b/%0b data=0x%08h bytes=%0d | mux v/r=%0b/%0b sel=%0d data=0x%08h bytes=%0d | fifo push/pop=%0b/%0b full/empty=%0b/%0b usage=%0d | out v/r=%0b/%0b data=0x%08h bytes=%0d",
                 cycle_no, $time,
                 dut.i_atb_funnel_top.ins_dst_atvalid,
                 dut.i_atb_funnel_top.ins_dst_atready,
                 dut.i_atb_funnel_top.ins_dst_payload.atdata,
                 dut.i_atb_funnel_top.ins_dst_payload.atbytes,
                 dut.i_atb_funnel_top.mux_atvalid,
                 dut.i_atb_funnel_top.mux_atready,
                 dut.i_atb_funnel_top.mux_sel_o,
                 dut.i_atb_funnel_top.mux_atdata,
                 dut.i_atb_funnel_top.mux_atbytes,
                 dut.i_atb_funnel_top.fifo_push,
                 dut.i_atb_funnel_top.fifo_pop,
                 dut.i_atb_funnel_top.fifo_full,
                 dut.i_atb_funnel_top.fifo_empty,
                 dut.i_atb_funnel_top.fifo_usage,
                 out_atvalid_o,
                 out_atready_i,
                 out_atdata_o,
                 out_atbytes_o);
      end
    end
  end

  // Output checker + duplicate/hold detection
  always @(posedge funnel_clk_i) begin
    if (!funnel_rst_ni) begin
      out_hs_count      <= 0;
      exp_rd_idx        <= 0;
      cmp_errors        <= 0;
      duplicate_errors  <= 0;
      hold_errors       <= 0;
      prev_out_valid    <= 1'b0;
      stall_active      <= 1'b0;
    end else if (monitors_enable) begin
      // hold-stability under stall
      if (out_atvalid_o && !out_atready_i) begin
        if (!stall_active) begin
          stall_active <= 1'b1;
          stall_id     <= out_atid_o;
          stall_data   <= out_atdata_o;
          stall_bytes  <= out_atbytes_o;
        end else if ((out_atid_o !== stall_id) || (out_atdata_o !== stall_data) || (out_atbytes_o !== stall_bytes)) begin
          hold_errors <= hold_errors + 1;
          $display("[HOLD] FAIL t=%0t output changed while stalled", $time);
        end
      end else begin
        stall_active <= 1'b0;
      end

      if (out_atvalid_o && out_atready_i) begin
        $display("[OUT ] t=%0t idx=%0d mux_sel=%0d id=0x%0h data=0x%08h bytes=%0d | fifo push/pop=%0b/%0b usage=%0d",
                 $time, exp_rd_idx, funnel_mux_sel_o, out_atid_o, out_atdata_o, out_atbytes_o,
                 dut.i_atb_funnel_top.fifo_push, dut.i_atb_funnel_top.fifo_pop, dut.i_atb_funnel_top.fifo_usage);

        if (prev_out_valid && (prev_out_id === out_atid_o) && (prev_out_data === out_atdata_o) && (prev_out_bytes === out_atbytes_o)) begin
          duplicate_errors <= duplicate_errors + 1;
          $display("[DUP ] FAIL t=%0t repeated consecutive output handshake", $time);
        end

        if (exp_rd_idx >= exp_wr_idx) begin
          cmp_errors <= cmp_errors + 1;
          $display("[CMP ] FAIL: output packet arrived before expected queue entry existed");
        end else if ((out_atid_o !== exp_id[exp_rd_idx]) || (out_atdata_o !== exp_data[exp_rd_idx]) || (out_atbytes_o !== exp_bytes[exp_rd_idx])) begin
          cmp_errors <= cmp_errors + 1;
          $display("[CMP ] FAIL: packet mismatch at idx=%0d", exp_rd_idx);
          $display("       EXP: id=0x%0h data=0x%08h bytes=%0d", exp_id[exp_rd_idx], exp_data[exp_rd_idx], exp_bytes[exp_rd_idx]);
          $display("       GOT: id=0x%0h data=0x%08h bytes=%0d", out_atid_o, out_atdata_o, out_atbytes_o);
        end else begin
          $display("[CMP ] PASS: matched");
        end

        prev_out_valid <= 1'b1;
        prev_out_id    <= out_atid_o;
        prev_out_data  <= out_atdata_o;
        prev_out_bytes <= out_atbytes_o;

        out_hs_count <= out_hs_count + 1;
        exp_rd_idx   <= exp_rd_idx + 1;
      end
    end
  end

  task automatic run_test_always_ready;
    begin
      $display("\n============================================================");
      $display("TEST 1: INTERNAL PROBE, ALWAYS READY");
      $display("============================================================");
      clear_stats();
      clear_inputs();
      out_atready_i = 1'b1;
      repeat (3) @(posedge funnel_clk_i);
      drive_burst_8();
      wait_encoder_quiet(8);
      wait_output_drain(300);
      $display("\nSUMMARY TEST 1: enc_hs=%0d out_hs=%0d remaining=%0d cmp=%0d dup=%0d hold=%0d\n",
               enc_hs_count, out_hs_count, (exp_wr_idx-exp_rd_idx), cmp_errors, duplicate_errors, hold_errors);
    end
  endtask

  task automatic run_test_targeted_backpressure;
    begin
      $display("\n============================================================");
      $display("TEST 2: INTERNAL PROBE, TARGETED BACKPRESSURE");
      $display("============================================================");
      clear_stats();
      clear_inputs();
      out_atready_i = 1'b1;
      repeat (3) @(posedge funnel_clk_i);
      fork
        begin
          drive_burst_8();
        end
        begin : ready_pattern
          // Let a few beats enter, then stall and release in a deterministic way.
          repeat (18) @(posedge funnel_clk_i);
          out_atready_i <= 1'b0;
          repeat (5)  @(posedge funnel_clk_i);
          out_atready_i <= 1'b1;
          repeat (1)  @(posedge funnel_clk_i);
          out_atready_i <= 1'b0;
          repeat (3)  @(posedge funnel_clk_i);
          out_atready_i <= 1'b1;
          repeat (2)  @(posedge funnel_clk_i);
          out_atready_i <= 1'b0;
          repeat (4)  @(posedge funnel_clk_i);
          out_atready_i <= 1'b1;
        end
      join
      wait_encoder_quiet(8);
      wait_output_drain(400);
      $display("\nSUMMARY TEST 2: enc_hs=%0d out_hs=%0d remaining=%0d cmp=%0d dup=%0d hold=%0d\n",
               enc_hs_count, out_hs_count, (exp_wr_idx-exp_rd_idx), cmp_errors, duplicate_errors, hold_errors);
    end
  endtask

  initial begin
    do_reset();
    run_test_always_ready();
    repeat (20) @(posedge funnel_clk_i);
    run_test_targeted_backpressure();
    repeat (40) @(posedge funnel_clk_i);
    $display("All internal-probe tests completed.");
    $finish;
  end

endmodule
