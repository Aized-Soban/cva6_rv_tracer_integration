`timescale 1ns/1ps

module tb_atb_funnel_top;

  localparam int ATDATA_W    = 32;
  localparam int ATBYTES_W   = 2;
  localparam int ATID_W      = 7;
  localparam int SYNC_STAGES = 2;

  localparam logic [1:0] SEL_NONE = 2'd0;
  localparam logic [1:0] SEL_NBR  = 2'd1;
  localparam logic [1:0] SEL_SYS  = 2'd2;
  localparam logic [1:0] SEL_INS  = 2'd3;


  // --------------------------------------------------------------------------
  // DUT signals
  // --------------------------------------------------------------------------
  logic                    src_clk_i;
  logic                    src_rst_ni;

  logic                    dst_clk_i;
  logic                    dst_rst_ni;

  logic [ATDATA_W-1:0]     nbr_atdata_i;
  logic [ATBYTES_W-1:0]    nbr_atbytes_i;
  logic [ATID_W-1:0]       nbr_atid_i;
  logic                    nbr_atvalid_i;
  logic                    nbr_atready_o;
  logic                    nbr_afvalid_o;
  logic                    nbr_afready_i;

  logic [ATDATA_W-1:0]     sys_atdata_i;
  logic [ATBYTES_W-1:0]    sys_atbytes_i;
  logic [ATID_W-1:0]       sys_atid_i;
  logic                    sys_atvalid_i;
  logic                    sys_atready_o;
  logic                    sys_afvalid_o;
  logic                    sys_afready_i;

  logic [ATDATA_W-1:0]     ins_atdata_i;
  logic [ATBYTES_W-1:0]    ins_atbytes_i;
  logic [ATID_W-1:0]       ins_atid_i;
  logic                    ins_atvalid_i;
  logic                    ins_atready_o;
  logic                    ins_afvalid_o;
  logic                    ins_afready_i;

  logic [ATDATA_W-1:0]     out_atdata_o;
  logic [ATBYTES_W-1:0]    out_atbytes_o;
  logic [ATID_W-1:0]       out_atid_o;
  logic                    out_atvalid_o;
  logic                    out_atready_i;

  logic                    out_afvalid_i;
  logic                    out_afready_o;

  logic                    nbr_flush_complete_o;
  logic                    sys_flush_complete_o;
  logic                    ins_flush_complete_o;
  logic [1:0]              mux_sel_o;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  atb_funnel_top #(
    .ATDATA_W    ( ATDATA_W    ),
    .ATBYTES_W   ( ATBYTES_W   ),
    .ATID_W      ( ATID_W      ),
    .SYNC_STAGES ( SYNC_STAGES )
  ) dut (
    .src_clk_i            ( src_clk_i            ),
    .src_rst_ni           ( src_rst_ni           ),
    .dst_clk_i            ( dst_clk_i            ),
    .dst_rst_ni           ( dst_rst_ni           ),

    .nbr_atdata_i         ( nbr_atdata_i         ),
    .nbr_atbytes_i        ( nbr_atbytes_i        ),
    .nbr_atid_i           ( nbr_atid_i           ),
    .nbr_atvalid_i        ( nbr_atvalid_i        ),
    .nbr_atready_o        ( nbr_atready_o        ),
    .nbr_afvalid_o        ( nbr_afvalid_o        ),
    .nbr_afready_i        ( nbr_afready_i        ),

    .sys_atdata_i         ( sys_atdata_i         ),
    .sys_atbytes_i        ( sys_atbytes_i        ),
    .sys_atid_i           ( sys_atid_i           ),
    .sys_atvalid_i        ( sys_atvalid_i        ),
    .sys_atready_o        ( sys_atready_o        ),
    .sys_afvalid_o        ( sys_afvalid_o        ),
    .sys_afready_i        ( sys_afready_i        ),

    .ins_atdata_i         ( ins_atdata_i         ),
    .ins_atbytes_i        ( ins_atbytes_i        ),
    .ins_atid_i           ( ins_atid_i           ),
    .ins_atvalid_i        ( ins_atvalid_i        ),
    .ins_atready_o        ( ins_atready_o        ),
    .ins_afvalid_o        ( ins_afvalid_o        ),
    .ins_afready_i        ( ins_afready_i        ),

    .out_atdata_o         ( out_atdata_o         ),
    .out_atbytes_o        ( out_atbytes_o        ),
    .out_atid_o           ( out_atid_o           ),
    .out_atvalid_o        ( out_atvalid_o        ),
    .out_atready_i        ( out_atready_i        ),

    .out_afvalid_i        ( out_afvalid_i        ),
    .out_afready_o        ( out_afready_o        ),

    .nbr_flush_complete_o ( nbr_flush_complete_o ),
    .sys_flush_complete_o ( sys_flush_complete_o ),
    .ins_flush_complete_o ( ins_flush_complete_o ),
    .mux_sel_o            ( mux_sel_o            )
  );

  // --------------------------------------------------------------------------
  // Clocks
  // --------------------------------------------------------------------------
  initial begin
    src_clk_i = 1'b0;
    forever #5 src_clk_i = ~src_clk_i;   // 100 MHz
  end

  initial begin
    dst_clk_i = 1'b0;
    forever #7 dst_clk_i = ~dst_clk_i;   // async to src clock
  end

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------
  task automatic clear_inputs;
    begin
      nbr_atdata_i      = 32'hA0A0_0001;
      nbr_atbytes_i     = 2'b01;
      nbr_atid_i        = 7'h11;
      nbr_atvalid_i     = 1'b0;
      nbr_afready_i     = 1'b0;

      sys_atdata_i      = 32'hB1B1_0002;
      sys_atbytes_i     = 2'b10;
      sys_atid_i        = 7'h22;
      sys_atvalid_i     = 1'b0;
      sys_afready_i     = 1'b0;

      ins_atdata_i      = 32'hC2C2_0003;
      ins_atbytes_i     = 2'b11;
      ins_atid_i        = 7'h33;
      ins_atvalid_i     = 1'b0;
      ins_afready_i     = 1'b0;

      out_atready_i     = 1'b1;
      out_afvalid_i     = 1'b0;
    end
  endtask
  
  
    task automatic apply_reset;
    begin
    clear_inputs();

    // Assert both resets together
    src_rst_ni = 1'b0;
    dst_rst_ni = 1'b0;

    // Hold reset long enough.
    // With src period = 10ns and dst period = 14ns, common posedges occur at:
    // 35ns, 105ns, 175ns, ...
    // Releasing at 175ns is safe for this TB.
    #175;
    src_rst_ni = 1'b1;
    dst_rst_ni = 1'b1;

    // Let the design settle a bit after POR release
    repeat (4) @(posedge src_clk_i);
    repeat (4) @(posedge dst_clk_i);
    end
    endtask

  task automatic send_nbr_beat(
    input logic [ATDATA_W-1:0]  data,
    input logic [ATBYTES_W-1:0] bytes,
    input logic [ATID_W-1:0]    id
  );
    begin
      nbr_atdata_i  = data;
      nbr_atbytes_i = bytes;
      nbr_atid_i    = id;
      nbr_atvalid_i = 1'b1;

      while (nbr_atready_o !== 1'b1) @(posedge src_clk_i);
      @(posedge src_clk_i);
      #1 nbr_atvalid_i = 1'b0;
    end
  endtask

  task automatic send_sys_beat(
    input logic [ATDATA_W-1:0]  data,
    input logic [ATBYTES_W-1:0] bytes,
    input logic [ATID_W-1:0]    id
  );
    begin
      sys_atdata_i  = data;
      sys_atbytes_i = bytes;
      sys_atid_i    = id;
      sys_atvalid_i = 1'b1;

      while (sys_atready_o !== 1'b1) @(posedge src_clk_i);
      @(posedge src_clk_i);
      #1 sys_atvalid_i = 1'b0;
    end
  endtask

  task automatic send_ins_beat(
    input logic [ATDATA_W-1:0]  data,
    input logic [ATBYTES_W-1:0] bytes,
    input logic [ATID_W-1:0]    id
  );
    begin
      ins_atdata_i  = data;
      ins_atbytes_i = bytes;
      ins_atid_i    = id;
      ins_atvalid_i = 1'b1;

      while (ins_atready_o !== 1'b1) @(posedge src_clk_i);
      @(posedge src_clk_i);
      #1 ins_atvalid_i = 1'b0;
    end
  endtask

  task automatic wait_out_beat(
    input logic [ATDATA_W-1:0]  exp_data,
    input logic [ATBYTES_W-1:0] exp_bytes,
    input logic [ATID_W-1:0]    exp_id,
    input string                msg
  );
    int i;
    bit found;
    begin
      found = 0;
      for (i = 0; i < 120; i++) begin
        @(posedge dst_clk_i);
        #1;
        if (out_atvalid_o &&
            out_atdata_o  == exp_data &&
            out_atbytes_o == exp_bytes &&
            out_atid_o    == exp_id) begin
          found = 1;
          break;
        end
      end

      if (!found) begin
        $error("[%0t] %s : expected output beat not observed", $time, msg);
        $fatal;
      end
      $display("[%0t] PASS: %s", $time, msg);
    end
  endtask

task automatic consume_one_out_beat(input string msg);
  int i;
  bit seen;
  begin
    out_atready_i = 1'b1;
    seen = 0;

    // Case 1: beat is already present right now
    if (out_atvalid_o) begin
      @(posedge dst_clk_i);
      #1;
      seen = 1;
    end
    // Case 2: beat appears later
    else begin
      for (i = 0; i < 80; i++) begin
        @(posedge dst_clk_i);
        #1;
        if (out_atvalid_o) begin
          @(posedge dst_clk_i);
          #1;
          seen = 1;
          break;
        end
      end
    end

    if (!seen) begin
      $error("[%0t] %s : no output beat to consume", $time, msg);
      $fatal;
    end

    $display("[%0t] PASS: %s", $time, msg);
  end
endtask

  task automatic wait_out_idle(input string msg);
    int i;
    bit ok;
    begin
      ok = 0;
      for (i = 0; i < 80; i++) begin
        @(posedge dst_clk_i);
        #1;
        if (!out_atvalid_o) begin
          ok = 1;
          break;
        end
      end
      if (!ok) begin
        $error("[%0t] %s : output did not go idle", $time, msg);
        $fatal;
      end
      $display("[%0t] PASS: %s", $time, msg);
    end
  endtask

  task automatic wait_mux_sel(
    input logic [1:0] exp_sel,
    input string      msg
  );
    int i;
    bit ok;
    begin
      ok = 0;
      for (i = 0; i < 120; i++) begin
        @(posedge dst_clk_i);
        #1;
        if (mux_sel_o == exp_sel) begin
          ok = 1;
          break;
        end
      end
      if (!ok) begin
        $error("[%0t] %s : expected mux_sel_o=%0d not observed", $time, msg, exp_sel);
        $fatal;
      end
      $display("[%0t] PASS: %s", $time, msg);
    end
  endtask

  task automatic check_idle(input string msg);
    begin
      #1;
      if (out_atvalid_o          !== 1'b0 ||
          out_afready_o          !== 1'b0 ||
          nbr_afvalid_o          !== 1'b0 ||
          sys_afvalid_o          !== 1'b0 ||
          ins_afvalid_o          !== 1'b0 ||
          nbr_flush_complete_o   !== 1'b0 ||
          sys_flush_complete_o   !== 1'b0 ||
          ins_flush_complete_o   !== 1'b0) begin
        $error("[%0t] %s : DUT not idle as expected", $time, msg);
        $fatal;
      end
      $display("[%0t] PASS: %s", $time, msg);
    end
  endtask

  task automatic wait_all_src_afvalid_high(input string msg);
    int i;
    bit ok;
    begin
      ok = 0;
      for (i = 0; i < 60; i++) begin
        @(posedge src_clk_i);
        #1;
        if (nbr_afvalid_o && sys_afvalid_o && ins_afvalid_o) begin
          ok = 1;
          break;
        end
      end
      if (!ok) begin
        $error("[%0t] %s : not all source afvalids went high", $time, msg);
        $fatal;
      end
      $display("[%0t] PASS: %s", $time, msg);
    end
  endtask

  task automatic wait_all_src_afvalid_low(input string msg);
    int i;
    bit ok;
    begin
      ok = 0;
      for (i = 0; i < 120; i++) begin
        @(posedge src_clk_i);
        #1;
        if (!nbr_afvalid_o && !sys_afvalid_o && !ins_afvalid_o) begin
          ok = 1;
          break;
        end
      end
      if (!ok) begin
        $error("[%0t] %s : source afvalids did not all clear", $time, msg);
        $fatal;
      end
      $display("[%0t] PASS: %s", $time, msg);
    end
  endtask

  task automatic pulse_nbr_afready_done;
    begin
      nbr_afready_i = 1'b1;
      repeat (2) @(posedge src_clk_i);
      #1 nbr_afready_i = 1'b0;
    end
  endtask

  task automatic pulse_sys_afready_done;
    begin
      sys_afready_i = 1'b1;
      repeat (2) @(posedge src_clk_i);
      #1 sys_afready_i = 1'b0;
    end
  endtask

  task automatic pulse_ins_afready_done;
    begin
      ins_afready_i = 1'b1;
      repeat (2) @(posedge src_clk_i);
      #1 ins_afready_i = 1'b0;
    end
  endtask

  task automatic wait_nbr_flush_complete_high(input string msg);
    int i;
    bit ok;
    begin
      ok = 0;
      for (i = 0; i < 80; i++) begin
        @(posedge dst_clk_i);
        #1;
        if (nbr_flush_complete_o) begin
          ok = 1;
          break;
        end
      end
      if (!ok) begin
        $error("[%0t] %s : nbr_flush_complete_o did not go high", $time, msg);
        $fatal;
      end
      $display("[%0t] PASS: %s", $time, msg);
    end
  endtask

  task automatic wait_sys_flush_complete_high(input string msg);
    int i;
    bit ok;
    begin
      ok = 0;
      for (i = 0; i < 80; i++) begin
        @(posedge dst_clk_i);
        #1;
        if (sys_flush_complete_o) begin
          ok = 1;
          break;
        end
      end
      if (!ok) begin
        $error("[%0t] %s : sys_flush_complete_o did not go high", $time, msg);
        $fatal;
      end
      $display("[%0t] PASS: %s", $time, msg);
    end
  endtask

  task automatic wait_ins_flush_complete_high(input string msg);
    int i;
    bit ok;
    begin
      ok = 0;
      for (i = 0; i < 80; i++) begin
        @(posedge dst_clk_i);
        #1;
        if (ins_flush_complete_o) begin
          ok = 1;
          break;
        end
      end
      if (!ok) begin
        $error("[%0t] %s : ins_flush_complete_o did not go high", $time, msg);
        $fatal;
      end
      $display("[%0t] PASS: %s", $time, msg);
    end
  endtask

  task automatic wait_all_flush_complete_low(input string msg);
    int i;
    bit ok;
    begin
      ok = 0;
      for (i = 0; i < 120; i++) begin
        @(posedge dst_clk_i);
        #1;
        if (!nbr_flush_complete_o &&
            !sys_flush_complete_o &&
            !ins_flush_complete_o) begin
          ok = 1;
          break;
        end
      end
      if (!ok) begin
        $error("[%0t] %s : flush_complete outputs did not all clear", $time, msg);
        $fatal;
      end
      $display("[%0t] PASS: %s", $time, msg);
    end
  endtask

  task automatic wait_out_afready_high(input string msg);
    int i;
    bit ok;
    begin
      ok = 0;
      for (i = 0; i < 120; i++) begin
        @(posedge dst_clk_i);
        #1;
        if (out_afready_o) begin
          ok = 1;
          break;
        end
      end
      if (!ok) begin
        $error("[%0t] %s : out_afready_o did not go high", $time, msg);
        $fatal;
      end
      $display("[%0t] PASS: %s", $time, msg);
    end
  endtask

  task automatic ensure_out_afready_low_for_cycles(
    input int    cycles,
    input string msg
  );
    int i;
    begin
      for (i = 0; i < cycles; i++) begin
        @(posedge dst_clk_i);
        #1;
        if (out_afready_o !== 1'b0) begin
          $error("[%0t] %s : out_afready_o unexpectedly high", $time, msg);
          $fatal;
        end
      end
      $display("[%0t] PASS: %s", $time, msg);
    end
  endtask

  // --------------------------------------------------------------------------
  // Waves
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_atb_funnel_top.vcd");
    $dumpvars(0, tb_atb_funnel_top);
  end

  // --------------------------------------------------------------------------
  // Global timeout
  // --------------------------------------------------------------------------
  initial begin
    #100us;
    $fatal(1, "Global TB timeout");
  end
    // --------------------------------------------------------------------------
  // Testcase selector
  // --------------------------------------------------------------------------
  // You can either:
  // 1) change the default here manually, or
  // 2) override with simulator plusarg: +TC=single_nbr
  //string tc_name = "idle";
  //string tc_name = "single_nbr";
  //string tc_name = "single_sys";
  //string tc_name = "single_ins";
  string tc_name = "prio_integrated"; /////
  //string tc_name = "flush_broadcast";
  //string tc_name = "flush_nbr_done";
  //string tc_name = "flush_sys_done";
  //string tc_name = "flush_ins_done";
  //string tc_name = "flush_all_done_no_old";
  //string tc_name = "flush_old_fifo_delay_ack";
  //string tc_name = "flush_mask_nbr";
  //string tc_name = "flush_mask_sys";
  //string tc_name = "flush_clear_after_ack";

   // --------------------------------------------------------------------------
  // Main testcase selector
  // --------------------------------------------------------------------------
  initial begin
    //void'($value$plusargs("TC=%s", tc_name));

    $display("====================================================");
    $display("Starting tb_atb_funnel_top");
    $display("====================================================");

    apply_reset();

    case (tc_name)

      "idle": begin // after reset, verify DUT has no stale activity
        $display("Running TC=idle");
        check_idle("reset -> idle");
      end

      "single_nbr": begin // verify one neighbor transaction passes through CDC, mux, FIFO, output
        $display("Running TC=single_nbr");
        out_atready_i = 1'b0;
        send_nbr_beat(32'h1111_0001, 2'b01, 7'h11);
        wait_out_beat(32'h1111_0001, 2'b01, 7'h11,
                      "single neighbor beat reaches output FIFO");
        out_atready_i = 1'b1;
        consume_one_out_beat("neighbor beat consumed");
        wait_out_idle("output idle after consuming neighbor beat");
      end

      "single_sys": begin  // verify one system transaction passes through CDC, mux, FIFO, output
        $display("Running TC=single_sys");
        out_atready_i = 1'b0;
        send_sys_beat(32'h2222_0002, 2'b10, 7'h22);
        wait_out_beat(32'h2222_0002, 2'b10, 7'h22,
                      "single system beat reaches output FIFO");
        out_atready_i = 1'b1;
        consume_one_out_beat("system beat consumed");
        wait_out_idle("output idle after consuming system beat");
      end

      "single_ins": begin // // verify one inst transaction passes through CDC, mux, FIFO, output
        $display("Running TC=single_ins");
        out_atready_i = 1'b0;
        send_ins_beat(32'h3333_0003, 2'b11, 7'h33);
        wait_out_beat(32'h3333_0003, 2'b11, 7'h33,
                      "single instruction beat reaches output FIFO");
        out_atready_i = 1'b1;
        consume_one_out_beat("instruction beat consumed");
        wait_out_idle("output idle after consuming instruction beat");
      end

      "prio_integrated": begin 
      // send inst beat , let it fill FIFO, then send two beats neighbour and system , and check output == ins->neigh->system
        $display("Running TC=prio_integrated");

        // Fill output FIFO first with instruction beat.
        out_atready_i = 1'b0;
        send_ins_beat(32'hCAFE_0003, 2'b11, 7'h33);
        wait_out_beat(32'hCAFE_0003, 2'b11, 7'h33,
                      "instruction beat loaded into output FIFO");

        // While FIFO is full, queue higher-priority sources behind it.
        send_sys_beat(32'hBEEF_0002, 2'b10, 7'h22);
        send_nbr_beat(32'hDEAD_0001, 2'b01, 7'h11);

        // Mux should pick neighbor among pending beats.
        wait_mux_sel(SEL_NBR, "neighbor selected over system while FIFO is blocking");

        // Drain output and confirm order: ins first (already in FIFO), then nbr.
        out_atready_i = 1'b1;
        consume_one_out_beat("consume first buffered instruction beat");
        wait_out_beat(32'hDEAD_0001, 2'b01, 7'h11,
                      "neighbor becomes next output beat after instruction drains");
      end

      "flush_broadcast": begin
      // verify a flush request from output side gets broadcast to all 3 source flush controllers
        $display("Running TC=flush_broadcast");
        out_afvalid_i = 1'b1;
        wait_all_src_afvalid_high("flush request broadcast to all three source controllers");
      end

      "flush_nbr_done": begin
      // verify single-source flush completion works for neighbor
        $display("Running TC=flush_nbr_done");
        out_afvalid_i = 1'b1;
        wait_all_src_afvalid_high("flush request active");
        @(posedge src_clk_i);
        pulse_nbr_afready_done();
        wait_nbr_flush_complete_high("neighbor flush_complete synchronized to destination");
      end

      "flush_sys_done": begin
      // verify single-source flush completion works for system
        $display("Running TC=flush_sys_done");
        out_afvalid_i = 1'b1;
        wait_all_src_afvalid_high("flush request active");
        @(posedge src_clk_i);
        pulse_sys_afready_done();
        wait_sys_flush_complete_high("system flush_complete synchronized to destination");
      end

      "flush_ins_done": begin
      // verify single-source flush completion works for inst
        $display("Running TC=flush_ins_done");
        out_afvalid_i = 1'b1;
        wait_all_src_afvalid_high("flush request active");
        @(posedge src_clk_i);
        pulse_ins_afready_done();
        wait_ins_flush_complete_high("instruction flush_complete synchronized to destination");
      end

      "flush_all_done_no_old": begin
      // verify complete flush when there is no old buffered beat inside the funnel
        $display("Running TC=flush_all_done_no_old");
        out_afvalid_i = 1'b1;
        wait_all_src_afvalid_high("flush request active");
        @(posedge src_clk_i);
        pulse_nbr_afready_done();
        pulse_sys_afready_done();
        pulse_ins_afready_done();

        wait_nbr_flush_complete_high("neighbor done");
        wait_sys_flush_complete_high("system done");
        wait_ins_flush_complete_high("instruction done");

        wait_out_afready_high("all sources done with no old FIFO beat -> out_afready_o asserted");
      end

      "flush_old_fifo_delay_ack": begin
      // prove DUT does not acknowledge flush early if pre-flush data is still buffered
        $display("Running TC=flush_old_fifo_delay_ack");

        // Put one old beat in funnel FIFO before flush starts.
        out_atready_i = 1'b0;
        send_nbr_beat(32'h0BAD_0001, 2'b01, 7'h11);
        wait_out_beat(32'h0BAD_0001, 2'b01, 7'h11,
                      "old beat buffered before flush starts");

        // Start flush while old beat is still in FIFO.
        out_afvalid_i = 1'b1;
        wait_all_src_afvalid_high("flush request active with old FIFO beat present");

        @(posedge src_clk_i);
        pulse_nbr_afready_done();
        pulse_sys_afready_done();
        pulse_ins_afready_done();

        wait_nbr_flush_complete_high("neighbor done");
        wait_sys_flush_complete_high("system done");
        wait_ins_flush_complete_high("instruction done");

        ensure_out_afready_low_for_cycles(6,
          "out_afready_o must stay low while old FIFO beat still exists");

        // Drain the old beat, then out_afready_o should rise.
        out_atready_i = 1'b1;
        consume_one_out_beat("old FIFO beat consumed");
        wait_out_afready_high("out_afready_o asserted after old beat drains");
      end

      "flush_mask_nbr": begin
      // verify flush-complete status removes that source from mux arbitration
        $display("Running TC=flush_mask_nbr");

        // Fill FIFO so that later pending beats stay behind mux.
        out_atready_i = 1'b0;
        send_ins_beat(32'hAAAA_0003, 2'b11, 7'h33);
        wait_out_beat(32'hAAAA_0003, 2'b11, 7'h33,
                      "instruction beat occupying output FIFO");

        // Start flush and complete neighbor first.
        out_afvalid_i = 1'b1;
        wait_all_src_afvalid_high("flush request active");
        @(posedge src_clk_i);
        pulse_nbr_afready_done();
        wait_nbr_flush_complete_high("neighbor marked complete");

        // Queue sys and nbr behind the full FIFO.
        send_sys_beat(32'hBBBB_0002, 2'b10, 7'h22);
        send_nbr_beat(32'hCCCC_0001, 2'b01, 7'h11);

        // Since neighbor is completed, system should be selected.
        wait_mux_sel(SEL_SYS, "neighbor masked by flush_complete, system selected");
      end

      "flush_mask_sys": begin
      // verify flush-complete status removes that source from mux arbitration
        $display("Running TC=flush_mask_sys");

        out_atready_i = 1'b0;
        send_ins_beat(32'h1111_0003, 2'b11, 7'h33);
        wait_out_beat(32'h1111_0003, 2'b11, 7'h33,
                      "instruction beat occupying output FIFO");

        out_afvalid_i = 1'b1;
        wait_all_src_afvalid_high("flush request active");
        @(posedge src_clk_i);
        pulse_sys_afready_done();
        wait_sys_flush_complete_high("system marked complete");

        send_nbr_beat(32'h2222_0001, 2'b01, 7'h11);
        send_sys_beat(32'h3333_0002, 2'b10, 7'h22);

        wait_mux_sel(SEL_NBR, "system masked by flush_complete, neighbor selected");
      end

      "flush_clear_after_ack": begin
      // request ? complete ? acknowledge ? clear state ? idle
        $display("Running TC=flush_clear_after_ack");

        out_afvalid_i = 1'b1;
        wait_all_src_afvalid_high("flush request active");
        @(posedge src_clk_i);
        pulse_nbr_afready_done();
        pulse_sys_afready_done();
        pulse_ins_afready_done();

        wait_out_afready_high("flush ack asserted after all sources complete");

        // Keep AFVALID high long enough for the ACK to cross back into src domain
        repeat (4) @(posedge src_clk_i);

        // Now end the flush request
        out_afvalid_i = 1'b0;

        wait_all_src_afvalid_low("source-side afvalids clear after flush teardown");
        wait_all_flush_complete_low("destination flush_complete bits clear after flush teardown");
        check_idle("design returns to idle after flush teardown");
    end
    endcase

    $display("====================================================");
    $display("TC %s PASSED", tc_name);
    $display("====================================================");
    $finish;
  end

endmodule