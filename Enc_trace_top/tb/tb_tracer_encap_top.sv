`timescale 1ns/1ps

module tb_tracer_encap_top;

  localparam int unsigned N              = 1;
  localparam int unsigned ONLY_BRANCHES  = 0;
  localparam int unsigned APB_ADDR_WIDTH = 32;
  localparam int unsigned DATA_LEN       = 32;

  import te_pkg::*;

  logic clk_i, rst_ni;
  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  // tracer inputs
  logic [N-1:0]                    valid_i;
  logic [N-1:0][ITYPE_LEN-1:0]     itype_i;
  logic [XLEN-1:0]                 cause_i;
  logic [XLEN-1:0]                 tval_i;
  logic [PRIV_LEN-1:0]             priv_i;
  logic [N-1:0][XLEN-1:0]          iaddr_i;
  logic [N-1:0][IRETIRE_LEN-1:0]   iretire_i;
  logic [N-1:0]                    ilastsize_i;
  logic [TIME_LEN-1:0]             time_i;
  logic [XLEN-1:0]                 tvec_i, epc_i;

  // APB
  logic [APB_ADDR_WIDTH-1:0]       paddr_i;
  logic                            pwrite_i, psel_i, penable_i;
  logic [31:0]                     pwdata_i;
  logic                            pready_o;
  logic [31:0]                     prdata_o;

  // ATB
  logic                            atready_i;
  logic                            afvalid_i;
  logic [$clog2(DATA_LEN)-4:0]     atbytes_o;
  logic [DATA_LEN-1:0]             atdata_o;
  logic [6:0]                      atid_o;
  logic                            atvalid_o;
  logic                            afready_o;

  logic                            stall_o;

  tracer_encap_top #(
    .N              (N),
    .ONLY_BRANCHES  (ONLY_BRANCHES),
    .APB_ADDR_WIDTH (APB_ADDR_WIDTH),
    .DATA_LEN       (DATA_LEN),
    .ENCAP_FIFO_DEPTH(16)
  ) dut (
    .clk_i, .rst_ni,

    .valid_i, .itype_i, .cause_i, .tval_i, .priv_i,
    .iaddr_i, .iretire_i, .ilastsize_i,

    .time_i, .tvec_i, .epc_i,

    .paddr_i, .pwrite_i, .psel_i, .penable_i, .pwdata_i,
    .pready_o, .prdata_o,

    .atready_i, .afvalid_i,
    .atbytes_o, .atdata_o, .atid_o, .atvalid_o, .afready_o,

    .stall_o
  );

  // ---------- APB write ----------
  task automatic apb_write(input logic [APB_ADDR_WIDTH-1:0] addr, input logic [31:0] data);
    @(posedge clk_i);
    paddr_i   <= addr;
    pwdata_i  <= data;
    pwrite_i  <= 1'b1;
    psel_i    <= 1'b1;
    penable_i <= 1'b0;

    @(posedge clk_i);
    penable_i <= 1'b1;

    while (!pready_o) @(posedge clk_i);

    @(posedge clk_i);
    psel_i    <= 1'b0;
    penable_i <= 1'b0;
    pwrite_i  <= 1'b0;
    pwdata_i  <= '0;
    paddr_i   <= '0;
  endtask

  // ---------- Drive one TE event ----------
  task automatic drive_event(
    input int unsigned itype_val,
    input logic [XLEN-1:0] pc,
    input logic [IRETIRE_LEN-1:0] halfwords_retired,
    input logic last_is_32b,
    input logic [XLEN-1:0] cause,
    input logic [XLEN-1:0] epc,
    input logic [XLEN-1:0] tval,
    input logic [XLEN-1:0] tvec,
    input logic [PRIV_LEN-1:0] priv
  );
    begin
      valid_i[0]     <= 1'b1;
      itype_i[0]     <= logic'(itype_val[ITYPE_LEN-1:0]);
      iaddr_i[0]     <= pc;
      iretire_i[0]   <= halfwords_retired;
      ilastsize_i[0] <= last_is_32b;

      cause_i        <= cause;
      epc_i          <= epc;
      tval_i         <= tval;
      tvec_i         <= tvec;
      priv_i         <= priv;

      @(posedge clk_i);

      valid_i[0]     <= 1'b0;
      itype_i[0]     <= '0;
      iaddr_i[0]     <= '0;
      iretire_i[0]   <= '0;
      ilastsize_i[0] <= '0;

      @(posedge clk_i);
    end
  endtask

  // ---------- Monitors ----------
  int unsigned atb_count;
  assign tb_count    = 0;

  always_ff @(posedge clk_i) begin
    if (rst_ni && atvalid_o && atready_i) begin
      atb_count++;
      $display("[ATB] t=%0t beat=%0d atid=0x%0h atbytes=%0d atdata=0x%08x",
               $time, atb_count, atid_o, atbytes_o, atdata_o);
    end
    if (rst_ni && stall_o) begin
      $display("[STALL] t=%0t stall_o=1", $time);
    end
  end
int unsigned it;
  // ---------- Main ----------
  initial begin
    rst_ni   = 1'b0;

    valid_i      = '0;
    itype_i      = '0;
    cause_i      = '0;
    tval_i       = '0;
    priv_i       = 2'b11;
    iaddr_i      = '0;
    iretire_i    = '0;
    ilastsize_i  = '0;
    time_i       = '0;
    tvec_i       = '0;
    epc_i        = '0;

    paddr_i      = '0;
    pwrite_i     = 1'b0;
    psel_i       = 1'b0;
    penable_i    = 1'b0;
    pwdata_i     = '0;

    atready_i    = 1'b1;
    afvalid_i    = 1'b1;

    //atb_count    = 0;

    repeat (20) @(posedge clk_i);
    rst_ni = 1'b1;
    $display("[TB] Reset released @ t=%0t", $time);

    // Enable tracing (same addr you used successfully before)
    apb_write(32'h0000_001c, 32'h0000_0001);
    $display("[TB] TRACE_STATE written = 1");

    // Drive many events to ensure packets form
    for (int k = 0; k < 200; k++) begin
      time_i <= time_i + 64'd1;

      // Use mixed safe set (not just 4/5)
      
      unique case (k % 6)
        0: it = 0;   // STD
        1: it = 1;
        2: it = 2;   // exception-like
        3: it = 3;
        4: it = 8;
        default: it = 12;
      endcase

      drive_event(it,
                  64'h0000_0000_0000_1200 + (k*4),
                  32'd2, 1'b1,
                  (it == 2) ? 32'h0000_000B : 32'h0,
                  (it == 2) ? 32'h0000_2000 : 32'h0,
                  (it == 2) ? 32'hDEAD_BEEF : 32'h0,
                  (it == 2) ? 32'h0000_1000 : 32'h0,
                  2'b11);
    end

    repeat (300) @(posedge clk_i);

    if (atb_count == 0) begin
      $fatal(1, "[TB] ERROR: No ATB beats observed. Encapsulator path is not emitting.");
    end else begin
      $display("[TB] PASS: ATB beats observed = %0d", atb_count);
    end

    $finish;
  end

endmodule
