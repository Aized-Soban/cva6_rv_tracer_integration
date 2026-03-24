`timescale 1ns/1ps

module tb_atb_priority_mux;

  localparam int ATDATA_W  = 32;
  localparam int ATBYTES_W = 2;
  localparam int ATID_W    = 7;

  localparam logic [1:0] SEL_NONE = 2'd0;
  localparam logic [1:0] SEL_NBR  = 2'd1;
  localparam logic [1:0] SEL_SYS  = 2'd2;
  localparam logic [1:0] SEL_INS  = 2'd3;

  // --------------------------------------------------------------------------
  // DUT signals
  // --------------------------------------------------------------------------
  logic                    nbr_flush_complete_i;
  logic                    sys_flush_complete_i;
  logic                    ins_flush_complete_i;

  logic [ATDATA_W-1:0]     nbr_atdata_i;
  logic [ATBYTES_W-1:0]    nbr_atbytes_i;
  logic [ATID_W-1:0]       nbr_atid_i;
  logic                    nbr_atvalid_i;
  logic                    nbr_atready_o;

  logic [ATDATA_W-1:0]     sys_atdata_i;
  logic [ATBYTES_W-1:0]    sys_atbytes_i;
  logic [ATID_W-1:0]       sys_atid_i;
  logic                    sys_atvalid_i;
  logic                    sys_atready_o;

  logic [ATDATA_W-1:0]     ins_atdata_i;
  logic [ATBYTES_W-1:0]    ins_atbytes_i;
  logic [ATID_W-1:0]       ins_atid_i;
  logic                    ins_atvalid_i;
  logic                    ins_atready_o;

  logic [ATDATA_W-1:0]     mux_atdata_o;
  logic [ATBYTES_W-1:0]    mux_atbytes_o;
  logic [ATID_W-1:0]       mux_atid_o;
  logic                    mux_atvalid_o;
  logic                    mux_atready_i;

  logic [1:0]              sel_o;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  atb_priority_mux #(
    .ATDATA_W  ( ATDATA_W  ),
    .ATBYTES_W ( ATBYTES_W ),
    .ATID_W    ( ATID_W    )
  ) dut (
    .nbr_flush_complete_i ( nbr_flush_complete_i ),
    .sys_flush_complete_i ( sys_flush_complete_i ),
    .ins_flush_complete_i ( ins_flush_complete_i ),

    .nbr_atdata_i         ( nbr_atdata_i         ),
    .nbr_atbytes_i        ( nbr_atbytes_i        ),
    .nbr_atid_i           ( nbr_atid_i           ),
    .nbr_atvalid_i        ( nbr_atvalid_i        ),
    .nbr_atready_o        ( nbr_atready_o        ),

    .sys_atdata_i         ( sys_atdata_i         ),
    .sys_atbytes_i        ( sys_atbytes_i        ),
    .sys_atid_i           ( sys_atid_i           ),
    .sys_atvalid_i        ( sys_atvalid_i        ),
    .sys_atready_o        ( sys_atready_o        ),

    .ins_atdata_i         ( ins_atdata_i         ),
    .ins_atbytes_i        ( ins_atbytes_i        ),
    .ins_atid_i           ( ins_atid_i           ),
    .ins_atvalid_i        ( ins_atvalid_i        ),
    .ins_atready_o        ( ins_atready_o        ),

    .mux_atdata_o         ( mux_atdata_o         ),
    .mux_atbytes_o        ( mux_atbytes_o        ),
    .mux_atid_o           ( mux_atid_o           ),
    .mux_atvalid_o        ( mux_atvalid_o        ),
    .mux_atready_i        ( mux_atready_i        ),

    .sel_o                ( sel_o                )
  );

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------
task automatic init_inputs;
  begin
    nbr_flush_complete_i = 1'b0;
    sys_flush_complete_i = 1'b0;
    ins_flush_complete_i = 1'b0;

    nbr_atdata_i         = 32'hA0A0_0001;
    nbr_atbytes_i        = 2'b01;
    nbr_atid_i           = 7'h11;
    nbr_atvalid_i        = 1'b0;

    sys_atdata_i         = 32'h5151_0002;
    sys_atbytes_i        = 2'b10;
    sys_atid_i           = 7'h22;
    sys_atvalid_i        = 1'b0;

    ins_atdata_i         = 32'h1A51_0003;
    ins_atbytes_i        = 2'b11;
    ins_atid_i           = 7'h33;
    ins_atvalid_i        = 1'b0;

    mux_atready_i        = 1'b0;
  end
endtask

  task automatic check_outputs(
    input logic [1:0]           exp_sel,
    input logic                 exp_mux_valid,
    input logic [ATDATA_W-1:0]  exp_data,
    input logic [ATBYTES_W-1:0] exp_bytes,
    input logic [ATID_W-1:0]    exp_id,
    input logic                 exp_nbr_ready,
    input logic                 exp_sys_ready,
    input logic                 exp_ins_ready,
    input string                msg
  );
    begin
      #1;

      if (sel_o !== exp_sel) begin
        $error("[%0t] %s : sel_o mismatch. got=%0d exp=%0d",
               $time, msg, sel_o, exp_sel);
        $fatal;
      end

      if (mux_atvalid_o !== exp_mux_valid) begin
        $error("[%0t] %s : mux_atvalid_o mismatch. got=%0b exp=%0b",
               $time, msg, mux_atvalid_o, exp_mux_valid);
        $fatal;
      end

      if (mux_atdata_o !== exp_data) begin
        $error("[%0t] %s : mux_atdata_o mismatch. got=0x%08h exp=0x%08h",
               $time, msg, mux_atdata_o, exp_data);
        $fatal;
      end

      if (mux_atbytes_o !== exp_bytes) begin
        $error("[%0t] %s : mux_atbytes_o mismatch. got=0x%0h exp=0x%0h",
               $time, msg, mux_atbytes_o, exp_bytes);
        $fatal;
      end

      if (mux_atid_o !== exp_id) begin
        $error("[%0t] %s : mux_atid_o mismatch. got=0x%0h exp=0x%0h",
               $time, msg, mux_atid_o, exp_id);
        $fatal;
      end

      if (nbr_atready_o !== exp_nbr_ready) begin
        $error("[%0t] %s : nbr_atready_o mismatch. got=%0b exp=%0b",
               $time, msg, nbr_atready_o, exp_nbr_ready);
        $fatal;
      end

      if (sys_atready_o !== exp_sys_ready) begin
        $error("[%0t] %s : sys_atready_o mismatch. got=%0b exp=%0b",
               $time, msg, sys_atready_o, exp_sys_ready);
        $fatal;
      end

      if (ins_atready_o !== exp_ins_ready) begin
        $error("[%0t] %s : ins_atready_o mismatch. got=%0b exp=%0b",
               $time, msg, ins_atready_o, exp_ins_ready);
        $fatal;
      end

      $display("[%0t] PASS: %s", $time, msg);
    end
  endtask

  // --------------------------------------------------------------------------
  // Optional dump
  // --------------------------------------------------------------------------
  initial begin
   // $dumpfile("tb_atb_priority_mux.vcd");
   // $dumpvars(0, tb_atb_priority_mux);
  end

  // --------------------------------------------------------------------------
  // Stimulus
  // --------------------------------------------------------------------------
  initial begin
    $display("====================================================");
    $display("Starting tb_atb_priority_mux_3");
    $display("====================================================");

    init_inputs();

    // ------------------------------------------------------------------------
    // Test 0: no valid inputs
    // ------------------------------------------------------------------------
    check_outputs(
      SEL_NONE, 1'b0, '0, '0, '0, 1'b0, 1'b0, 1'b0,
      "no valid source -> no selection"
    );

    // ------------------------------------------------------------------------
    // Test 1: only neighbor valid
    // ------------------------------------------------------------------------
    init_inputs();
    nbr_atvalid_i = 1'b1;
    mux_atready_i = 1'b1;
    check_outputs(
      SEL_NBR, 1'b1, nbr_atdata_i, nbr_atbytes_i, nbr_atid_i,
      1'b1, 1'b0, 1'b0,
      "only neighbor valid -> select neighbor"
    );

    // ------------------------------------------------------------------------
    // Test 2: only system valid
    // ------------------------------------------------------------------------
    init_inputs();
    sys_atvalid_i = 1'b1;
    mux_atready_i = 1'b1;
    check_outputs(
      SEL_SYS, 1'b1, sys_atdata_i, sys_atbytes_i, sys_atid_i,
      1'b0, 1'b1, 1'b0,
      "only system valid -> select system"
    );

    // ------------------------------------------------------------------------
    // Test 3: only instruction valid
    // ------------------------------------------------------------------------
    init_inputs();
    ins_atvalid_i = 1'b1;
    mux_atready_i = 1'b1;
    check_outputs(
      SEL_INS, 1'b1, ins_atdata_i, ins_atbytes_i, ins_atid_i,
      1'b0, 1'b0, 1'b1,
      "only instruction valid -> select instruction"
    );

    // ------------------------------------------------------------------------
    // Test 4: all valid, none complete -> neighbor wins
    // ------------------------------------------------------------------------
    init_inputs();
    nbr_atvalid_i = 1'b1;
    sys_atvalid_i = 1'b1;
    ins_atvalid_i = 1'b1;
    mux_atready_i = 1'b1;
    check_outputs(
      SEL_NBR, 1'b1, nbr_atdata_i, nbr_atbytes_i, nbr_atid_i,
      1'b1, 1'b0, 1'b0,
      "all valid, all incomplete -> neighbor highest priority"
    );

    // ------------------------------------------------------------------------
    // Test 5: neighbor complete -> system wins over instruction
    // ------------------------------------------------------------------------
    init_inputs();
    nbr_atvalid_i         = 1'b1;
    sys_atvalid_i         = 1'b1;
    ins_atvalid_i         = 1'b1;
    nbr_flush_complete_i  = 1'b1;
    mux_atready_i         = 1'b1;
    check_outputs(
      SEL_SYS, 1'b1, sys_atdata_i, sys_atbytes_i, sys_atid_i,
      1'b0, 1'b1, 1'b0,
      "neighbor complete -> exclude neighbor, system wins"
    );

    // ------------------------------------------------------------------------
    // Test 6: system complete -> neighbor still wins
    // ------------------------------------------------------------------------
    init_inputs();
    nbr_atvalid_i         = 1'b1;
    sys_atvalid_i         = 1'b1;
    ins_atvalid_i         = 1'b1;
    sys_flush_complete_i  = 1'b1;
    mux_atready_i         = 1'b1;
    check_outputs(
      SEL_NBR, 1'b1, nbr_atdata_i, nbr_atbytes_i, nbr_atid_i,
      1'b1, 1'b0, 1'b0,
      "system complete -> exclude system, neighbor wins"
    );

    // ------------------------------------------------------------------------
    // Test 7: instruction complete -> neighbor wins over system
    // ------------------------------------------------------------------------
    init_inputs();
    nbr_atvalid_i         = 1'b1;
    sys_atvalid_i         = 1'b1;
    ins_atvalid_i         = 1'b1;
    ins_flush_complete_i  = 1'b1;
    mux_atready_i         = 1'b1;
    check_outputs(
      SEL_NBR, 1'b1, nbr_atdata_i, nbr_atbytes_i, nbr_atid_i,
      1'b1, 1'b0, 1'b0,
      "instruction complete -> exclude instruction, neighbor wins"
    );

    // ------------------------------------------------------------------------
    // Test 8: neighbor and system complete -> only instruction remains
    // ------------------------------------------------------------------------
    init_inputs();
    nbr_atvalid_i         = 1'b1;
    sys_atvalid_i         = 1'b1;
    ins_atvalid_i         = 1'b1;
    nbr_flush_complete_i  = 1'b1;
    sys_flush_complete_i  = 1'b1;
    mux_atready_i         = 1'b1;
    check_outputs(
      SEL_INS, 1'b1, ins_atdata_i, ins_atbytes_i, ins_atid_i,
      1'b0, 1'b0, 1'b1,
      "neighbor and system complete -> instruction selected"
    );

    // ------------------------------------------------------------------------
    // Test 9: all complete -> no selection
    // ------------------------------------------------------------------------
    init_inputs();
    nbr_atvalid_i         = 1'b1;
    sys_atvalid_i         = 1'b1;
    ins_atvalid_i         = 1'b1;
    nbr_flush_complete_i  = 1'b1;
    sys_flush_complete_i  = 1'b1;
    ins_flush_complete_i  = 1'b1;
    mux_atready_i         = 1'b1;
    check_outputs(
      SEL_NONE, 1'b0, '0, '0, '0, 1'b0, 1'b0, 1'b0,
      "all complete -> all excluded -> no selection"
    );

    // ------------------------------------------------------------------------
    // Test 10: selected source ready follows mux_atready_i = 0
    // ------------------------------------------------------------------------
    init_inputs();
    nbr_atvalid_i = 1'b1;
    sys_atvalid_i = 1'b1;
    ins_atvalid_i = 1'b1;
    mux_atready_i = 1'b0;
    check_outputs(
      SEL_NBR, 1'b1, nbr_atdata_i, nbr_atbytes_i, nbr_atid_i,
      1'b0, 1'b0, 1'b0,
      "selected source sees ready=0 when mux_atready_i=0"
    );

    // ------------------------------------------------------------------------
    // Test 11: completed source is excluded even if valid, so invalid lower
    // source can still cause no selection
    // ------------------------------------------------------------------------
    init_inputs();
    nbr_atvalid_i         = 1'b1;
    nbr_flush_complete_i  = 1'b1;
    sys_atvalid_i         = 1'b0;
    ins_atvalid_i         = 1'b0;
    mux_atready_i         = 1'b1;
    check_outputs(
      SEL_NONE, 1'b0, '0, '0, '0, 1'b0, 1'b0, 1'b0,
      "only completed valid source present -> no selection"
    );

    // ------------------------------------------------------------------------
    // Test 12: neighbor excluded, system invalid, instruction valid -> instruction
    // ------------------------------------------------------------------------
    init_inputs();
    nbr_atvalid_i         = 1'b1;
    nbr_flush_complete_i  = 1'b1;
    sys_atvalid_i         = 1'b0;
    ins_atvalid_i         = 1'b1;
    mux_atready_i         = 1'b1;
    check_outputs(
      SEL_INS, 1'b1, ins_atdata_i, ins_atbytes_i, ins_atid_i,
      1'b0, 1'b0, 1'b1,
      "neighbor excluded and system invalid -> instruction selected"
    );

    $display("====================================================");
    $display("All tests PASSED");
    $display("====================================================");
    $finish;
  end

endmodule