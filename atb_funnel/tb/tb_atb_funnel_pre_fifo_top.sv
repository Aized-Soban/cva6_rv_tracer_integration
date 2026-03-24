`timescale 1ns/1ps

module tb_atb_funnel_pre_fifo_top;

  localparam int ATDATA_W    = 32;
  localparam int ATBYTES_W   = 2;
  localparam int ATID_W      = 7;
  localparam int SYNC_STAGES = 2;

  localparam logic [1:0] SEL_NONE = 2'd0;
  localparam logic [1:0] SEL_NBR  = 2'd1;
  localparam logic [1:0] SEL_SYS  = 2'd2;
  localparam logic [1:0] SEL_INS  = 2'd3;

  // --------------------------------------------------------------------------
  // Clocks / resets
  // --------------------------------------------------------------------------
  logic src_clk_i;
  logic src_rst_ni;

  logic dst_clk_i;
  logic dst_rst_ni;

  // --------------------------------------------------------------------------
  // Shared destination-side flush controls
  // --------------------------------------------------------------------------
  logic dst_afvalid_i;
  logic dst_flush_ack_i;

  // --------------------------------------------------------------------------
  // Neighbor source
  // --------------------------------------------------------------------------
  logic [ATDATA_W-1:0]  nbr_atdata_i;
  logic [ATBYTES_W-1:0] nbr_atbytes_i;
  logic [ATID_W-1:0]    nbr_atid_i;
  logic                 nbr_atvalid_i;
  logic                 nbr_atready_o;
  logic                 nbr_src_afvalid_o;
  logic                 nbr_src_afready_i;

  // --------------------------------------------------------------------------
  // System source
  // --------------------------------------------------------------------------
  logic [ATDATA_W-1:0]  sys_atdata_i;
  logic [ATBYTES_W-1:0] sys_atbytes_i;
  logic [ATID_W-1:0]    sys_atid_i;
  logic                 sys_atvalid_i;
  logic                 sys_atready_o;
  logic                 sys_src_afvalid_o;
  logic                 sys_src_afready_i;

  // --------------------------------------------------------------------------
  // Instruction source
  // --------------------------------------------------------------------------
  logic [ATDATA_W-1:0]  ins_atdata_i;
  logic [ATBYTES_W-1:0] ins_atbytes_i;
  logic [ATID_W-1:0]    ins_atid_i;
  logic                 ins_atvalid_i;
  logic                 ins_atready_o;
  logic                 ins_src_afvalid_o;
  logic                 ins_src_afready_i;

  // --------------------------------------------------------------------------
  // Pre-FIFO mux outputs
  // --------------------------------------------------------------------------
  logic [ATDATA_W-1:0]  mux_atdata_o;
  logic [ATBYTES_W-1:0] mux_atbytes_o;
  logic [ATID_W-1:0]    mux_atid_o;
  logic                 mux_atvalid_o;
  logic                 mux_atready_i;

  logic                 nbr_flush_complete_o;
  logic                 sys_flush_complete_o;
  logic                 ins_flush_complete_o;

  logic [1:0]           mux_sel_o;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  atb_funnel_pre_fifo_top #(
    .ATDATA_W    ( ATDATA_W    ),
    .ATBYTES_W   ( ATBYTES_W   ),
    .ATID_W      ( ATID_W      ),
    .SYNC_STAGES ( SYNC_STAGES )
  ) dut (
    .src_clk_i             ( src_clk_i             ),
    .src_rst_ni            ( src_rst_ni            ),
    .dst_clk_i             ( dst_clk_i             ),
    .dst_rst_ni            ( dst_rst_ni            ),
    .dst_afvalid_i         ( dst_afvalid_i         ),
    .dst_flush_ack_i       ( dst_flush_ack_i       ),

    .nbr_atdata_i          ( nbr_atdata_i          ),
    .nbr_atbytes_i         ( nbr_atbytes_i         ),
    .nbr_atid_i            ( nbr_atid_i            ),
    .nbr_atvalid_i         ( nbr_atvalid_i         ),
    .nbr_atready_o         ( nbr_atready_o         ),
    .nbr_src_afvalid_o     ( nbr_src_afvalid_o     ),
    .nbr_src_afready_i     ( nbr_src_afready_i     ),

    .sys_atdata_i          ( sys_atdata_i          ),
    .sys_atbytes_i         ( sys_atbytes_i         ),
    .sys_atid_i            ( sys_atid_i            ),
    .sys_atvalid_i         ( sys_atvalid_i         ),
    .sys_atready_o         ( sys_atready_o         ),
    .sys_src_afvalid_o     ( sys_src_afvalid_o     ),
    .sys_src_afready_i     ( sys_src_afready_i     ),

    .ins_atdata_i          ( ins_atdata_i          ),
    .ins_atbytes_i         ( ins_atbytes_i         ),
    .ins_atid_i            ( ins_atid_i            ),
    .ins_atvalid_i         ( ins_atvalid_i         ),
    .ins_atready_o         ( ins_atready_o         ),
    .ins_src_afvalid_o     ( ins_src_afvalid_o     ),
    .ins_src_afready_i     ( ins_src_afready_i     ),

    .mux_atdata_o          ( mux_atdata_o          ),
    .mux_atbytes_o         ( mux_atbytes_o         ),
    .mux_atid_o            ( mux_atid_o            ),
    .mux_atvalid_o         ( mux_atvalid_o         ),
    .mux_atready_i         ( mux_atready_i         ),

    .nbr_flush_complete_o  ( nbr_flush_complete_o  ),
    .sys_flush_complete_o  ( sys_flush_complete_o  ),
    .ins_flush_complete_o  ( ins_flush_complete_o  ),
    .mux_sel_o             ( mux_sel_o             )
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
      dst_afvalid_i     = 1'b0;
      dst_flush_ack_i   = 1'b0;

      nbr_atdata_i      = 32'hA0A0_0001;
      nbr_atbytes_i     = 2'b01;
      nbr_atid_i        = 7'h11;
      nbr_atvalid_i     = 1'b0;
      nbr_src_afready_i = 1'b0;

      sys_atdata_i      = 32'hB1B1_0002;
      sys_atbytes_i     = 2'b10;
      sys_atid_i        = 7'h22;
      sys_atvalid_i     = 1'b0;
      sys_src_afready_i = 1'b0;

      ins_atdata_i      = 32'hC2C2_0003;
      ins_atbytes_i     = 2'b11;
      ins_atid_i        = 7'h33;
      ins_atvalid_i     = 1'b0;
      ins_src_afready_i = 1'b0;

      mux_atready_i     = 1'b1;
    end
  endtask

  task automatic apply_reset;
    begin
      clear_inputs();
      src_rst_ni = 1'b0;
      dst_rst_ni = 1'b0;

      repeat (4) @(posedge src_clk_i);
      repeat (4) @(posedge dst_clk_i);

      @(posedge src_clk_i);
      src_rst_ni = 1'b1;

      @(posedge dst_clk_i);
      dst_rst_ni = 1'b1;

      repeat (4) @(posedge src_clk_i);
      repeat (4) @(posedge dst_clk_i);
    end
  endtask

  task automatic check_idle(input string msg);
    begin
      #1;
      if (mux_atvalid_o !== 1'b0 ||
          mux_sel_o     !== SEL_NONE ||
          nbr_src_afvalid_o !== 1'b0 ||
          sys_src_afvalid_o !== 1'b0 ||
          ins_src_afvalid_o !== 1'b0 ||
          nbr_flush_complete_o !== 1'b0 ||
          sys_flush_complete_o !== 1'b0 ||
          ins_flush_complete_o !== 1'b0) begin
        $error("[%0t] %s : DUT not idle as expected", $time, msg);
        $fatal;
      end
      $display("[%0t] PASS: %s", $time, msg);
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
      @(posedge src_clk_i); // handshake edge
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

  task automatic expect_mux_selection(
    input logic [1:0]           exp_sel,
    input logic [ATDATA_W-1:0]  exp_data,
    input logic [ATBYTES_W-1:0] exp_bytes,
    input logic [ATID_W-1:0]    exp_id,
    input string                msg
  );
    int i;
    bit found;
    begin
      found = 0;
      for (i = 0; i < 80; i++) begin
        @(posedge dst_clk_i);
        #1;
        if (mux_sel_o     == exp_sel  &&
            mux_atvalid_o == 1'b1     &&
            mux_atdata_o  == exp_data &&
            mux_atbytes_o == exp_bytes &&
            mux_atid_o    == exp_id) begin
          found = 1;
          break;
        end
      end

      if (!found) begin
        $error("[%0t] %s : expected mux selection not observed", $time, msg);
        $fatal;
      end
      $display("[%0t] PASS: %s", $time, msg);
    end
  endtask

  task automatic expect_no_selection(input string msg);
    int i;
    bit ok;
    begin
      ok = 0;
      for (i = 0; i < 40; i++) begin
        @(posedge dst_clk_i);
        #1;
        if (mux_sel_o == SEL_NONE && mux_atvalid_o == 1'b0) begin
          ok = 1;
          break;
        end
      end
      if (!ok) begin
        $error("[%0t] %s : expected no selection", $time, msg);
        $fatal;
      end
      $display("[%0t] PASS: %s", $time, msg);
    end
  endtask

  task automatic check_mux_stable_for_cycles(
    input logic [1:0]           exp_sel,
    input logic [ATDATA_W-1:0]  exp_data,
    input logic [ATBYTES_W-1:0] exp_bytes,
    input logic [ATID_W-1:0]    exp_id,
    input int                   cycles,
    input string                msg
  );
    int i;
    begin
      for (i = 0; i < cycles; i++) begin
        @(posedge dst_clk_i);
        #1;
        if (mux_sel_o     !== exp_sel  ||
            mux_atvalid_o !== 1'b1     ||
            mux_atdata_o  !== exp_data ||
            mux_atbytes_o !== exp_bytes ||
            mux_atid_o    !== exp_id) begin
          $error("[%0t] %s : mux output not stable", $time, msg);
          $fatal;
        end
      end
      $display("[%0t] PASS: %s", $time, msg);
    end
  endtask

  task automatic wait_all_src_afvalid_high(input string msg);
    int i;
    bit ok;
    begin
      ok = 0;
      for (i = 0; i < 40; i++) begin
        @(posedge src_clk_i);
        #1;
        if (nbr_src_afvalid_o && sys_src_afvalid_o && ins_src_afvalid_o) begin
          ok = 1;
          break;
        end
      end
      if (!ok) begin
        $error("[%0t] %s : src flush requests did not all go high", $time, msg);
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
      for (i = 0; i < 60; i++) begin
        @(posedge src_clk_i);
        #1;
        if (!nbr_src_afvalid_o && !sys_src_afvalid_o && !ins_src_afvalid_o) begin
          ok = 1;
          break;
        end
      end
      if (!ok) begin
        $error("[%0t] %s : src flush requests did not all clear", $time, msg);
        $fatal;
      end
      $display("[%0t] PASS: %s", $time, msg);
    end
  endtask

  task automatic pulse_nbr_src_afready;
    begin
      nbr_src_afready_i = 1'b1;
      @(posedge src_clk_i);
      #1 nbr_src_afready_i = 1'b0;
    end
  endtask

  task automatic pulse_sys_src_afready;
    begin
      sys_src_afready_i = 1'b1;
      @(posedge src_clk_i);
      #1 sys_src_afready_i = 1'b0;
    end
  endtask

  task automatic pulse_ins_src_afready;
    begin
      ins_src_afready_i = 1'b1;
      @(posedge src_clk_i);
      #1 ins_src_afready_i = 1'b0;
    end
  endtask

  task automatic wait_nbr_flush_complete_high(input string msg);
    int i;
    bit ok;
    begin
      ok = 0;
      for (i = 0; i < 60; i++) begin
        @(posedge dst_clk_i);
        #1;
        if (nbr_flush_complete_o) begin
          ok = 1;
          break;
        end
      end
      if (!ok) begin
        $error("[%0t] %s : neighbor flush_complete did not go high", $time, msg);
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
      for (i = 0; i < 60; i++) begin
        @(posedge dst_clk_i);
        #1;
        if (sys_flush_complete_o) begin
          ok = 1;
          break;
        end
      end
      if (!ok) begin
        $error("[%0t] %s : system flush_complete did not go high", $time, msg);
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
      for (i = 0; i < 60; i++) begin
        @(posedge dst_clk_i);
        #1;
        if (ins_flush_complete_o) begin
          ok = 1;
          break;
        end
      end
      if (!ok) begin
        $error("[%0t] %s : instruction flush_complete did not go high", $time, msg);
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
      for (i = 0; i < 80; i++) begin
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

  task automatic pulse_dst_flush_ack;
    begin
      dst_flush_ack_i = 1'b1;
      repeat (2) @(posedge dst_clk_i);
      #1 dst_flush_ack_i = 1'b0;
    end
  endtask

  // --------------------------------------------------------------------------
  // Waves
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_atb_funnel_pre_fifo_top.vcd");
    $dumpvars(0, tb_atb_funnel_pre_fifo_top);
  end
  
  initial begin
    #50us;
    $fatal(1, "Global TB timeout");
  end

  // --------------------------------------------------------------------------
  // Tests
  // --------------------------------------------------------------------------
  //string tc_name = "single_nbr";
  //string tc_name = "idle";
  //string tc_name = "single_ins";
  //string tc_name = "base_prio";
  //string tc_name = "flush_broadcast";
  string tc_name = "flush_nbr_done";
  //string tc_name = "flush_sys_done";
  //string tc_name = "flush_all_done";
initial begin
  $display("====================================================");
  $display("Starting tb_atb_funnel_pre_fifo_top");
  $display("====================================================");

  if (!$value$plusargs("TC=%s", tc_name)) begin
    //tc_name = "idle";
  end

  // Only one POR-style reset for the whole simulation
  apply_reset();

  case (tc_name)

    "idle": begin
      $display("Running TC=idle");
      check_idle("reset -> idle");
    end

    "single_nbr": begin
      $display("Running TC=single_nbr");
      mux_atready_i = 1'b0;
      send_nbr_beat(32'h1111_0001, 2'b01, 7'h11);
      expect_mux_selection(SEL_NBR, 32'h1111_0001, 2'b01, 7'h11,
                           "single neighbor beat appears at mux");
      mux_atready_i = 1'b1;
      expect_no_selection("neighbor beat consumed after ready goes high");
    end

    "single_sys": begin
      $display("Running TC=single_sys");
      mux_atready_i = 1'b0;
      send_sys_beat(32'h2222_0002, 2'b10, 7'h22);
      expect_mux_selection(SEL_SYS, 32'h2222_0002, 2'b10, 7'h22,
                           "single system beat appears at mux");
      mux_atready_i = 1'b1;
      expect_no_selection("system beat consumed after ready goes high");
    end

    "single_ins": begin
      $display("Running TC=single_ins");
      mux_atready_i = 1'b0;
      send_ins_beat(32'h3333_0003, 2'b11, 7'h33);
      expect_mux_selection(SEL_INS, 32'h3333_0003, 2'b11, 7'h33,
                           "single instruction beat appears at mux");
      mux_atready_i = 1'b1;
      expect_no_selection("instruction beat consumed after ready goes high");
    end

    "base_prio": begin
      $display("Running TC=base_prio");
      mux_atready_i = 1'b0;

      send_ins_beat(32'hCCCC_0003, 2'b11, 7'h33);
      expect_mux_selection(SEL_INS, 32'hCCCC_0003, 2'b11, 7'h33,
                           "only instruction pending -> instruction selected");

      mux_atready_i = 1'b1;
      expect_no_selection("instruction beat consumed");

      mux_atready_i = 1'b0;
      send_sys_beat(32'hBBBB_0002, 2'b10, 7'h22);
      expect_mux_selection(SEL_SYS, 32'hBBBB_0002, 2'b10, 7'h22,
                           "only system pending -> system selected");

      mux_atready_i = 1'b1;
      expect_no_selection("system beat consumed");

      mux_atready_i = 1'b0;
      send_nbr_beat(32'hAAAA_0001, 2'b01, 7'h11);
      expect_mux_selection(SEL_NBR, 32'hAAAA_0001, 2'b01, 7'h11,
                           "only neighbor pending -> neighbor selected");

      mux_atready_i = 1'b1;
      expect_no_selection("neighbor beat consumed");
    end

    "flush_broadcast": begin
      $display("Running TC=flush_broadcast");
      dst_afvalid_i = 1'b1;
      wait_all_src_afvalid_high("flush request broadcast to all three source controllers");
    end

    "flush_nbr_done": begin
      $display("Running TC=flush_nbr_done");
      dst_afvalid_i = 1'b1;
      wait_all_src_afvalid_high("flush active before neighbor complete");
      @(posedge src_clk_i);   // give controller one full cycle to be firmly in FLUSH
      pulse_nbr_src_afready();
      wait_nbr_flush_complete_high("neighbor flush_complete synchronized to dst");
    end

    "flush_sys_done": begin
      $display("Running TC=flush_sys_done");
      dst_afvalid_i = 1'b1;
      wait_all_src_afvalid_high("flush active before system complete");
      @(posedge src_clk_i);   // give controller one full cycle to be firmly in FLUSH
      pulse_sys_src_afready();
      wait_sys_flush_complete_high("system flush_complete synchronized to dst");
    end

    "flush_all_done": begin
      $display("Running TC=flush_all_done");
      dst_afvalid_i = 1'b1;
      wait_all_src_afvalid_high("flush active before all complete");
      @(posedge src_clk_i);   // give controller one full cycle to be firmly in FLUSH
      pulse_nbr_src_afready();
      pulse_sys_src_afready();
      pulse_ins_src_afready();
      wait_nbr_flush_complete_high("neighbor complete high");
      wait_sys_flush_complete_high("system complete high");
      wait_ins_flush_complete_high("instruction complete high");
      expect_no_selection("all complete -> mux excludes all sources");
    end

    default: begin
      $fatal(1, "Unknown testcase: %s", tc_name);
    end
  endcase

  $display("====================================================");
  $display("TC %s PASSED", tc_name);
  $display("====================================================");
  $finish;
end

endmodule