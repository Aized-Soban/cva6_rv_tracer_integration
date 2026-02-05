`timescale 1ns/1ps

// ============================================================
// tb_tracer_top.sv
// Full TB for tracer_top.sv with:
//  - robust APB (won't miss 1-cycle PREADY pulse)
//  - enables tracing via TRACE_STATE
//  - generates retire + branch + exception events
//  - ATB sink toggles atready to show movement/backpressure
// ============================================================

module tb_tracer_top;

  // -----------------------------
  // Parameters
  // -----------------------------
  localparam int unsigned NRET       = 1;
  localparam int unsigned N          = 1;
  localparam int unsigned FIFO_DEPTH = 8;

  localparam int unsigned APB_AW     = 32;
  localparam int unsigned DATA_LEN   = 32;
  localparam int unsigned ENCAP_FIFO = 8;

  // -----------------------------
  // Imports (make sure these packages are in your compile list)
  // -----------------------------
  import te_pkg::*;
  import connector_pkg::*;
  import encap_pkg::*;

  // -----------------------------
  // Clock / Reset
  // -----------------------------
  logic clk;
  logic rst_n;

  initial clk = 0;
  always #5 clk = ~clk; // 100 MHz

  // -----------------------------
  // DUT I/O
  // -----------------------------
  logic [NRET-1:0]                          cpu_valid;
  logic [NRET-1:0][connector_pkg::XLEN-1:0] cpu_pc;
  connector_pkg::fu_op [NRET-1:0]           cpu_op;
  logic [NRET-1:0]                          cpu_is_compressed;

  logic                                     cpu_branch_valid;
  logic                                     cpu_is_taken;
  connector_pkg::cf_t                       cpu_cf_type;
  logic [connector_pkg::XLEN-1:0]           cpu_disc_pc;

  logic                                     cpu_ex_valid;
  logic [connector_pkg::XLEN-1:0]           cpu_tval;
  logic [connector_pkg::XLEN-1:0]           cpu_cause;
  logic [connector_pkg::PRIV_LEN-1:0]       cpu_priv_lvl;

  logic [te_pkg::TIME_LEN-1:0]              time_q;
  logic [te_pkg::XLEN-1:0]                  tvec;
  logic [te_pkg::XLEN-1:0]                  epc;

  // APB
  logic [APB_AW-1:0]                        paddr;
  logic                                     pwrite;
  logic                                     psel;
  logic                                     penable;
  logic [31:0]                              pwdata;
  logic                                     pready;
  logic [31:0]                              prdata;

  // ATB
  logic                                     atready;
  logic                                     afvalid;

  logic [$clog2(DATA_LEN)-4:0]              atbytes;
  logic [DATA_LEN-1:0]                      atdata;
  logic [6:0]                               atid;
  logic                                     atvalid;
  logic                                     afready;

  logic                                     stall;

  // -----------------------------
  // DUT instance
  // -----------------------------
  tracer_top #(
    .NRET              ( NRET ),
    .N                 ( N ),
    .FIFO_DEPTH        ( FIFO_DEPTH ),

    .ONLY_BRANCHES     ( 0 ),
    .APB_ADDR_WIDTH    ( APB_AW ),

    .DATA_LEN          ( DATA_LEN ),
    .ENCAP_FIFO_DEPTH  ( ENCAP_FIFO )
  ) dut (
    .clk_i              ( clk ),
    .rst_ni             ( rst_n ),

    .cpu_valid_i        ( cpu_valid ),
    .cpu_pc_i           ( cpu_pc ),
    .cpu_op_i           ( cpu_op ),
    .cpu_is_compressed_i( cpu_is_compressed ),

    .cpu_branch_valid_i ( cpu_branch_valid ),
    .cpu_is_taken_i     ( cpu_is_taken ),
    .cpu_cf_type_i      ( cpu_cf_type ),
    .cpu_disc_pc_i      ( cpu_disc_pc ),

    .cpu_ex_valid_i     ( cpu_ex_valid ),
    .cpu_tval_i         ( cpu_tval ),
    .cpu_cause_i        ( cpu_cause ),
    .cpu_priv_lvl_i     ( cpu_priv_lvl ),

    .time_i             ( time_q ),
    .tvec_i             ( tvec ),
    .epc_i              ( epc ),

    .paddr_i            ( paddr ),
    .pwrite_i           ( pwrite ),
    .psel_i             ( psel ),
    .penable_i          ( penable ),
    .pwdata_i           ( pwdata ),
    .pready_o           ( pready ),
    .prdata_o           ( prdata ),

    .atready_i          ( atready ),
    .afvalid_i          ( afvalid ),

    .atbytes_o          ( atbytes ),
    .atdata_o           ( atdata ),
    .atid_o             ( atid ),
    .atvalid_o          ( atvalid ),
    .afready_o          ( afready ),

    .stall_o            ( stall )
  );

  // -----------------------------
  // Timestamp generator
  // -----------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) time_q <= '0;
    else        time_q <= time_q + 1;
  end

  // -----------------------------
  // Robust APB tasks (handles 1-cycle PREADY pulse)
  // -----------------------------
  task automatic apb_write(input logic [APB_AW-1:0] addr,
                           input logic [31:0]       data,
                           input int unsigned       timeout_cycles = 10);
    int unsigned k;
    begin
      // SETUP phase: drive stable before posedge
      @(negedge clk);
      paddr   <= addr;
      pwdata  <= data;
      pwrite  <= 1'b1;
      psel    <= 1'b1;
      penable <= 1'b0;

      @(posedge clk); // captures setup

      // ACCESS phase
      @(negedge clk);
      penable <= 1'b1;

      @(posedge clk);
      #1; // sample inside access cycle
      if (!pready) begin
        for (k = 0; k < timeout_cycles && !pready; k++) begin
          @(posedge clk);
          #1;
        end
        if (!pready)
          $fatal(1, "[%0t] APB WRITE TIMEOUT addr=0x%08h data=0x%08h", $time, addr, data);
      end

      // COMPLETE
      @(negedge clk);
      psel    <= 1'b0;
      penable <= 1'b0;
      pwrite  <= 1'b0;
      paddr   <= '0;
      pwdata  <= '0;
    end
  endtask

  task automatic apb_read(input  logic [APB_AW-1:0] addr,
                          output logic [31:0]       data,
                          input  int unsigned       timeout_cycles = 10);
    int unsigned k;
    begin
      // SETUP
      @(negedge clk);
      paddr   <= addr;
      pwrite  <= 1'b0;
      psel    <= 1'b1;
      penable <= 1'b0;

      @(posedge clk);

      // ACCESS
      @(negedge clk);
      penable <= 1'b1;

      @(posedge clk);
      #1;
      if (!pready) begin
        for (k = 0; k < timeout_cycles && !pready; k++) begin
          @(posedge clk);
          #1;
        end
        if (!pready)
          $fatal(1, "[%0t] APB READ TIMEOUT addr=0x%08h", $time, addr);
      end

      data = prdata;

      // COMPLETE
      @(negedge clk);
      psel    <= 1'b0;
      penable <= 1'b0;
      paddr   <= '0;
    end
  endtask

  // -----------------------------
  // ATB sink behavior (toggle ready to show movement)
  // -----------------------------
  // This creates backpressure bursts so you can see:
  // atvalid may stay high and data beats drain when ready returns.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      atready <= 1'b0;
      afvalid <= 1'b1;
    end else begin
      // 3 cycles ready, 2 cycles not-ready pattern
      if (($time/10) % 5 < 3) atready <= 1'b1;
      else                    atready <= 1'b0;

      // keep AFVALID asserted (or toggle if you want funnel effects)
      afvalid <= 1'b1;
    end
  end

  // ATB logger
  int unsigned beat_count;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      beat_count <= 0;
    end else if (atvalid && atready) begin
      beat_count <= beat_count + 1;
      $display("[%0t] ATB beat=%0d id=0x%0h bytes=%0d data=0x%08h stall=%0b",
               $time, beat_count, atid, atbytes, atdata, stall);
    end
  end

  // -----------------------------
  // Event generators
  // -----------------------------
  task automatic retire_insn(input logic [connector_pkg::XLEN-1:0] pc_val,
                             input logic                            is_comp = 1'b0);
    begin
      cpu_valid[0]         <= 1'b1;
      cpu_pc[0]            <= pc_val;
      cpu_op[0]            <= connector_pkg::fu_op'('0);
      cpu_is_compressed[0] <= is_comp;

      // default: no branch / no exception
      cpu_branch_valid     <= 1'b0;
      cpu_is_taken         <= 1'b0;
      cpu_cf_type          <= connector_pkg::cf_t'('0);
      cpu_disc_pc          <= '0;

      cpu_ex_valid         <= 1'b0;
      cpu_tval             <= '0;
      cpu_cause            <= '0;
      cpu_priv_lvl         <= '0;

      @(posedge clk);
      cpu_valid[0] <= 1'b0;
    end
  endtask

  task automatic branch_event(input logic [connector_pkg::XLEN-1:0] disc_pc,
                              input logic taken);
    begin
      // make a cycle with branch_valid asserted
      cpu_valid[0]         <= 1'b1;
      cpu_pc[0]            <= disc_pc;
      cpu_op[0]            <= connector_pkg::fu_op'('0);
      cpu_is_compressed[0] <= 1'b0;

      cpu_branch_valid     <= 1'b1;
      cpu_is_taken         <= taken;
      cpu_cf_type          <= connector_pkg::cf_t'('0);
      cpu_disc_pc          <= disc_pc;

      cpu_ex_valid         <= 1'b0;

      @(posedge clk);
      cpu_valid[0]       <= 1'b0;
      cpu_branch_valid   <= 1'b0;
    end
  endtask

  task automatic exception_event(input logic [connector_pkg::XLEN-1:0] pc_val,
                                 input logic [connector_pkg::XLEN-1:0] cause_val,
                                 input logic [connector_pkg::XLEN-1:0] tval_val);
    begin
      cpu_valid[0]         <= 1'b1;
      cpu_pc[0]            <= pc_val;
      cpu_op[0]            <= connector_pkg::fu_op'('0);
      cpu_is_compressed[0] <= 1'b0;

      cpu_ex_valid         <= 1'b1;
      cpu_cause            <= cause_val;
      cpu_tval             <= tval_val;

      @(posedge clk);
      cpu_valid[0] <= 1'b0;
      cpu_ex_valid <= 1'b0;
    end
  endtask

  // -----------------------------
  // Main test sequence
  // -----------------------------
  logic [31:0] rdata;
  logic [31:0] TRACE_STATE_ADDR;

  initial begin
    // Defaults
    cpu_valid          = '0;
    cpu_pc             = '0;
    cpu_op             = '{default: connector_pkg::fu_op'('0)};
    cpu_is_compressed  = '0;

    cpu_branch_valid   = 1'b0;
    cpu_is_taken       = 1'b0;
    cpu_cf_type        = connector_pkg::cf_t'('0);
    cpu_disc_pc        = '0;

    cpu_ex_valid       = 1'b0;
    cpu_tval           = '0;
    cpu_cause          = '0;
    cpu_priv_lvl       = '0;

    tvec               = 32'h0000_0100;
    epc                = 32'h0000_0200;

    paddr              = '0;
    pwrite             = 1'b0;
    psel               = 1'b0;
    penable            = 1'b0;
    pwdata             = '0;

    beat_count         = 0;

    rst_n              = 1'b0;

    // Waves
    $dumpfile("tb_tracer_top.vcd");
    $dumpvars(0, tb_tracer_top);

    // Reset
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    // ----------------------------------------------------------
    // Enable tracing via APB:
    // te_reg decode is paddr[7:0], TRACE_STATE constant is 8'h1F
    // ----------------------------------------------------------
    TRACE_STATE_ADDR = 32'(te_pkg::TRACE_STATE); // 0x1F
    $display("[%0t] Enabling trace: write TRACE_STATE @0x%08h = 1", $time, TRACE_STATE_ADDR);

    apb_write(TRACE_STATE_ADDR, 32'h0000_0001);
    apb_read (TRACE_STATE_ADDR, rdata);
    $display("[%0t] TRACE_STATE readback @0x%08h = 0x%08h", $time, TRACE_STATE_ADDR, rdata);

    repeat (5) @(posedge clk);

    // ----------------------------------------------------------
    // Generate some activity
    // ----------------------------------------------------------
    retire_insn(32'h8000_0000);
    retire_insn(32'h8000_0004);
    retire_insn(32'h8000_0008, 1'b1); // compressed sample
    retire_insn(32'h8000_000A, 1'b1); // compressed sample

    branch_event(32'h8000_0010, 1'b1);

    retire_insn(32'h8000_0014);
    exception_event(32'h8000_0018, 32'h0000_0002, 32'hDEAD_BEEF);
    retire_insn(32'h8000_001C);

    // Let encapsulator drain (and atready toggling show movement)
    repeat (300) @(posedge clk);

    $display("[%0t] DONE. Total ATB beats observed: %0d", $time, beat_count);
    $finish;
  end

endmodule
