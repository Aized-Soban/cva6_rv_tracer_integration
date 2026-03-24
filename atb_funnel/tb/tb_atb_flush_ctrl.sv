`timescale 1ns/1ps

module tb_atb_flush_ctrl;

  // ---------------------------------------------------------------------------
  // DUT signals
  // ---------------------------------------------------------------------------
  logic       clk_i;
  logic       rst_ni;

  logic       afvalid_i;
  logic       src_afready_i;
  logic       flush_ack_i;

  logic       src_afvalid_o;
  logic       flush_complete_o;
  logic       busy_o;
  logic [1:0] state_o;

  // ---------------------------------------------------------------------------
  // DUT
  // ---------------------------------------------------------------------------
  atb_flush_ctrl dut (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .afvalid_i        (afvalid_i),
    .src_afready_i    (src_afready_i),
    .flush_ack_i      (flush_ack_i),
    .src_afvalid_o    (src_afvalid_o),
    .flush_complete_o (flush_complete_o),
    .busy_o           (busy_o),
    .state_o          (state_o)
  );

  // ---------------------------------------------------------------------------
  // State encodings (must match DUT)
  // ---------------------------------------------------------------------------
  localparam logic [1:0] IDLE_S     = 2'b00;
  localparam logic [1:0] FLUSH_S    = 2'b01;
  localparam logic [1:0] WAIT_ACK_S = 2'b10;

  // ---------------------------------------------------------------------------
  // Clock generation
  // ---------------------------------------------------------------------------
  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;   // 100 MHz
  end

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  task automatic reset_dut();
    begin
      afvalid_i     = 1'b0;
      src_afready_i = 1'b0;
      flush_ack_i   = 1'b0;

      rst_ni        = 1'b0;
      repeat (3) @(posedge clk_i);
      rst_ni        = 1'b1;
      @(posedge clk_i);
    end
  endtask

  task automatic check_state(
    input logic [1:0] exp_state,
    input logic       exp_src_afvalid,
    input logic       exp_flush_complete,
    input logic       exp_busy,
    input string      msg
  );
    begin
      #1; // allow combinational outputs to settle after clk edge
      if (state_o !== exp_state) begin
        $error("[%0t] %s : state mismatch. got=%0b exp=%0b",
               $time, msg, state_o, exp_state);
        $fatal;
      end

      if (src_afvalid_o !== exp_src_afvalid) begin
        $error("[%0t] %s : src  _afvalid_o mismatch. got=%0b exp=%0b",
               $time, msg, src_afvalid_o, exp_src_afvalid);
        $fatal;
      end

      if (flush_complete_o !== exp_flush_complete) begin
        $error("[%0t] %s : flush_complete_o mismatch. got=%0b exp=%0b",
               $time, msg, flush_complete_o, exp_flush_complete);
        $fatal;
      end

      if (busy_o !== exp_busy) begin
        $error("[%0t] %s : busy_o mismatch. got=%0b exp=%0b",
               $time, msg, busy_o, exp_busy);
        $fatal;
      end

      $display("[%0t] PASS: %s", $time, msg);
    end
  endtask

  task automatic pulse_afvalid_new_flush();
    begin
      afvalid_i = 1'b1;
      @(posedge clk_i);
    end
  endtask

  task automatic drop_afvalid();
    begin
      afvalid_i = 1'b0;
      @(posedge clk_i);
    end
  endtask

  task automatic pulse_src_afready();
    begin
      src_afready_i = 1'b1;
      @(posedge clk_i);
      src_afready_i = 1'b0;
    end
  endtask

  task automatic pulse_flush_ack();
    begin
      flush_ack_i = 1'b1;
      @(posedge clk_i);
      flush_ack_i = 1'b0;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Optional wave dump
  // ---------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_atb_flush_ctrl.vcd");
    $dumpvars(0, tb_atb_flush_ctrl);
  end

  // ---------------------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------------------
  initial begin
    $display("====================================================");
    $display("Starting tb_atb_flush_ctrl");
    $display("====================================================");

    reset_dut();

    // -------------------------------------------------------------------------
    // Test 0: after reset
    // -------------------------------------------------------------------------
    check_state(IDLE_S, 1'b0, 1'b0, 1'b0, "reset -> IDLE");

    // -------------------------------------------------------------------------
    // Test 1: afvalid rising edge starts flush
    // -------------------------------------------------------------------------
    pulse_afvalid_new_flush();
    check_state(FLUSH_S, 1'b1, 1'b0, 1'b1,
                "new afvalid rising edge -> FLUSH");

    // stay in FLUSH until source-side afready arrives
    repeat (2) begin
      @(posedge clk_i);
      check_state(FLUSH_S, 1'b1, 1'b0, 1'b1,
                  "remain in FLUSH while src_afready_i=0");
    end

    // -------------------------------------------------------------------------
    // Test 2: source afready completes local flush
    // FLUSH -> WAIT_ACK, flush_complete_o asserted
    // -------------------------------------------------------------------------
    pulse_src_afready();
    check_state(WAIT_ACK_S, 1'b0, 1'b1, 1'b1,
                "src_afready_i -> WAIT_ACK and flush_complete_o=1");

    // hold in WAIT_ACK until destination ack comes
    repeat (2) begin
      @(posedge clk_i);
      check_state(WAIT_ACK_S, 1'b0, 1'b1, 1'b1,
                  "remain in WAIT_ACK while flush_ack_i=0");
    end

    // -------------------------------------------------------------------------
    // Test 3: destination ack releases controller
    // WAIT_ACK -> IDLE, flush_complete_o clears
    // Keep afvalid_i high on purpose to verify no retrigger without new edge
    // -------------------------------------------------------------------------
    pulse_flush_ack();
    check_state(IDLE_S, 1'b0, 1'b0, 1'b0,
                "flush_ack_i -> IDLE and clear flush_complete_o");

    // afvalid_i is STILL HIGH here, but there is no new rising edge
    // so controller must stay in IDLE
    repeat (2) begin
      @(posedge clk_i);
      check_state(IDLE_S, 1'b0, 1'b0, 1'b0,
                  "no retrigger while afvalid_i remains high");
    end

    // now drop afvalid_i
    drop_afvalid();
    check_state(IDLE_S, 1'b0, 1'b0, 1'b0,
                "drop afvalid_i, remain IDLE");

    // -------------------------------------------------------------------------
    // Test 4: second clean flush request
    // -------------------------------------------------------------------------
    pulse_afvalid_new_flush();
    check_state(FLUSH_S, 1'b1, 1'b0, 1'b1,
                "second afvalid rising edge -> FLUSH");

    // finish second flush
    pulse_src_afready();
    check_state(WAIT_ACK_S, 1'b0, 1'b1, 1'b1,
                "second flush: src_afready_i -> WAIT_ACK");

    pulse_flush_ack();
    check_state(IDLE_S, 1'b0, 1'b0, 1'b0,
                "second flush: flush_ack_i -> IDLE");

    // clean afvalid low again
    drop_afvalid();
    check_state(IDLE_S, 1'b0, 1'b0, 1'b0,
                "final idle");

    // -------------------------------------------------------------------------
    // Test 5: spurious flush_ack in IDLE should do nothing
    // -------------------------------------------------------------------------
    pulse_flush_ack();
    check_state(IDLE_S, 1'b0, 1'b0, 1'b0,
                "spurious flush_ack in IDLE ignored");

    // -------------------------------------------------------------------------
    // Test 6: src_afready in IDLE should do nothing
    // -------------------------------------------------------------------------
    pulse_src_afready();
    check_state(IDLE_S, 1'b0, 1'b0, 1'b0,
                "spurious src_afready in IDLE ignored");

    $display("====================================================");
    $display("All tests PASSED");
    $display("====================================================");
    $finish;
  end

endmodule