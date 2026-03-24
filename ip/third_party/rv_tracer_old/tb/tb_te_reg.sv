`timescale 1ns/1ps

module tb_te_reg;

logic [31:0] rdata;
  // -----------------------------
  // Clock / reset
  // -----------------------------
  logic clk_i;
  logic rst_ni;

  always #5 clk_i = ~clk_i;

  // -----------------------------
  // APB signals
  // -----------------------------
  logic        psel_i;
  logic        penable_i;
  logic        pwrite_i;
  logic [31:0] paddr_i;
  logic [31:0] pwdata_i;
  logic [31:0] prdata_o;
  logic        pready_o;

  // -----------------------------
  // Trace control inputs
  // -----------------------------
  logic trace_req_on_i;
  logic trace_req_off_i;
  logic encapsulator_ready_i;

  // -----------------------------
  // DUT outputs (not all checked yet)
  // -----------------------------
  logic trace_enable_o;
  logic trace_activated_o;

  // -----------------------------
  // DUT
  // -----------------------------
  te_reg dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .psel_i(psel_i),
    .penable_i(penable_i),
    .pwrite_i(pwrite_i),
    .paddr_i(paddr_i),
    .pwdata_i(pwdata_i),
    .prdata_o(prdata_o),
    .pready_o(pready_o),

    .trace_req_on_i(trace_req_on_i),
    .trace_req_off_i(trace_req_off_i),
    .encapsulator_ready_i(encapsulator_ready_i),

    .trace_enable_o(trace_enable_o),
    .trace_activated_o(trace_activated_o)
  );

  // -----------------------------
  // APB write task
  // -----------------------------
  task apb_write(input [31:0] addr, input [31:0] data);
    begin
      @(posedge clk_i);
      psel_i   <= 1;
      penable_i<= 0;
      pwrite_i <= 1;
      paddr_i  <= addr;
      pwdata_i <= data;

      @(posedge clk_i);
      penable_i <= 1;

      // wait for ready
      while (!pready_o) @(posedge clk_i);

      @(posedge clk_i);
      psel_i    <= 0;
      penable_i <= 0;
      pwrite_i  <= 0;
    end
  endtask

  // -----------------------------
  // APB read task
  // -----------------------------
  task apb_read(input [31:0] addr, output [31:0] data);
    begin
      @(posedge clk_i);
      psel_i   <= 1;
      penable_i<= 0;
      pwrite_i <= 0;
      paddr_i  <= addr;

      @(posedge clk_i);
      penable_i <= 1;

      while (!pready_o) @(posedge clk_i);

      data = prdata_o;

      @(posedge clk_i);
      psel_i    <= 0;
      penable_i <= 0;
    end
  endtask

  // -----------------------------
  // Test sequence
  // -----------------------------
  initial begin
    // init
    clk_i = 0;
    rst_ni = 0;
    psel_i = 0;
    penable_i = 0;
    pwrite_i = 0;
    paddr_i = 0;
    pwdata_i = 0;
    trace_req_on_i = 0;
    trace_req_off_i = 0;
    encapsulator_ready_i = 1;

    // reset
    repeat (5) @(posedge clk_i);
    rst_ni = 1;

    $display("TB: Reset released");

    // -------------------------
    // Example: write/read TRACE_STATE
    // -------------------------
    apb_write(te_pkg::TRACE_STATE, '1); // TRACE_STATE = 1 (example address)

    apb_read(te_pkg::TRACE_STATE, rdata);

    if (rdata[0] !== 1'b1)
      $error("FAIL: TRACE_STATE readback mismatch");
    else
      $display("PASS: TRACE_STATE readback OK");

    // -------------------------
    // Trigger trace on/off
    // -------------------------
    @(posedge clk_i);
    trace_req_on_i <= 1;
    @(posedge clk_i);
    trace_req_on_i <= 0;

    repeat (2) @(posedge clk_i);

    if (!trace_enable_o)
      $error("FAIL: trace_enable_o did not assert");
    else
      $display("PASS: trace_enable_o asserted");

    @(posedge clk_i);
    trace_req_off_i <= 1;
    @(posedge clk_i);
    trace_req_off_i <= 0;

    repeat (2) @(posedge clk_i);

    if (trace_enable_o)
      $error("FAIL: trace_enable_o did not deassert");
    else
      $display("PASS: trace_enable_o deasserted");

    $display("TB completed");
    $finish;
  end

endmodule
