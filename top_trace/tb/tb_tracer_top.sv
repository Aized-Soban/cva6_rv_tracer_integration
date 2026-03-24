module tb_tracer_top;

  import connector_pkg::*;

  localparam int unsigned NRET           = 2;
  localparam int unsigned N              = 1;
  localparam int unsigned FIFO_DEPTH     = 16;
  localparam int unsigned APB_ADDR_WIDTH = 32;
  localparam int unsigned ONLY_BRANCHES  =  1;

  // Match tracer_top defaults/params as needed
  localparam int unsigned DATA_LEN         = 32;
  localparam int unsigned ENCAP_FIFO_DEPTH = 16;

  logic clk_i, rst_ni;
  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  task automatic step(int n=1);
    repeat (n) @(posedge clk_i);
  endtask

  // Inputs
  logic [NRET-1:0]                  cpu_valid_i;
  logic [NRET-1:0][XLEN-1:0]        cpu_pc_i;
  fu_op [NRET-1:0]                 cpu_op_i;
  logic [NRET-1:0]                  cpu_is_compressed_i;

  logic                             cpu_branch_valid_i;
  logic                             cpu_is_taken_i;
  cf_t                              cpu_cf_type_i;
  logic [XLEN-1:0]                  cpu_disc_pc_i;

  logic                             cpu_ex_valid_i;
  logic [XLEN-1:0]                  cpu_tval_i;
  logic [XLEN-1:0]                  cpu_cause_i;
  logic [PRIV_LEN-1:0]              cpu_priv_lvl_i;

  logic [te_pkg::TIME_LEN-1:0]      time_i;
  logic [te_pkg::XLEN-1:0]          tvec_i, epc_i;

  // APB
  logic [APB_ADDR_WIDTH-1:0]        paddr_i;
  logic                             pwrite_i, psel_i, penable_i;
  logic [31:0]                      pwdata_i;
  logic                             pready_o;
  logic [31:0]                      prdata_o;

  // ATB
  logic                             atready_i;
  logic                             afvalid_i;
  logic [$clog2(DATA_LEN)-4:0]      atbytes_o;
  logic [DATA_LEN-1:0]              atdata_o;
  logic [6:0]                       atid_o;
  logic                             atvalid_o;
  logic                             afready_o;

  logic                             stall_o;

  tracer_top #(
    .NRET            (NRET),
    .N               (N),
    .FIFO_DEPTH       (FIFO_DEPTH),
    .ONLY_BRANCHES    (ONLY_BRANCHES),
    .APB_ADDR_WIDTH   (APB_ADDR_WIDTH),
    .DATA_LEN         (DATA_LEN),
    .ENCAP_FIFO_DEPTH (ENCAP_FIFO_DEPTH)
  ) dut (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),

    .cpu_valid_i         (cpu_valid_i),
    .cpu_pc_i            (cpu_pc_i),
    .cpu_op_i            (cpu_op_i),
    .cpu_is_compressed_i (cpu_is_compressed_i),

    .cpu_branch_valid_i  (cpu_branch_valid_i),
    .cpu_is_taken_i      (cpu_is_taken_i),
    .cpu_cf_type_i       (cpu_cf_type_i),
    .cpu_disc_pc_i       (cpu_disc_pc_i),

    .cpu_ex_valid_i      (cpu_ex_valid_i),
    .cpu_tval_i          (cpu_tval_i),
    .cpu_cause_i         (cpu_cause_i),
    .cpu_priv_lvl_i      (cpu_priv_lvl_i),

    .time_i              (time_i),
    .tvec_i              (tvec_i),
    .epc_i               (epc_i),

    .paddr_i             (paddr_i),
    .pwrite_i            (pwrite_i),
    .psel_i              (psel_i),
    .penable_i           (penable_i),
    .pwdata_i            (pwdata_i),
    .pready_o            (pready_o),
    .prdata_o            (prdata_o),

    .atready_i           (atready_i),
    .afvalid_i           (afvalid_i),
    .atbytes_o           (atbytes_o),
    .atdata_o            (atdata_o),
    .atid_o              (atid_o),
    .atvalid_o           (atvalid_o),
    .afready_o           (afready_o),

    .stall_o             (stall_o)
  );

  task automatic drive_defaults();
    cpu_valid_i          = '0;
    cpu_pc_i             = '0;
    cpu_op_i[0]          = ADD;
    cpu_op_i[1]          = ADD;
    cpu_is_compressed_i  = '0;

    cpu_branch_valid_i   = 1'b0;
    cpu_is_taken_i       = 1'b0;
    cpu_cf_type_i        = NoCF;
    cpu_disc_pc_i        = '0;

    cpu_ex_valid_i       = 1'b0;
    cpu_tval_i           = '0;
    cpu_cause_i          = '0;
    cpu_priv_lvl_i       = '0;

    paddr_i              = '0;
    pwrite_i             = 1'b0;
    psel_i               = 1'b0;
    penable_i            = 1'b0;
    pwdata_i             = '0;

    tvec_i               = '0;
    epc_i                = '0;

    atready_i            = 1'b1; // IMPORTANT: keep ATB always ready
    afvalid_i            = 1'b0;
  endtask

  // make time progress
  always_ff @(posedge clk_i) begin
    if (!rst_ni) time_i <= '0;
    else        time_i <= time_i + 1;
  end

  // FIXED APB write: clocked wait + timeout (NO ZERO-TIME while loop!)
  task automatic apb_write32(
    input logic [APB_ADDR_WIDTH-1:0] addr,
    input logic [31:0]               data,
    input int unsigned               timeout_cycles = 200
  );
    int unsigned c;

    @(negedge clk_i);
    paddr_i   <= addr;
    pwdata_i  <= data;
    pwrite_i  <= 1'b1;
    psel_i    <= 1'b1;
    penable_i <= 1'b0;

    @(negedge clk_i);
    penable_i <= 1'b1;

    c = 0;
    while (!pready_o) begin
      @(negedge clk_i);
      c++;
      if (c >= timeout_cycles) begin
        $fatal(1, "[TB] APB TIMEOUT waiting for pready_o (addr=0x%0h data=0x%0h t=%0t)",
               addr, data, $time);
      end
    end

    @(negedge clk_i);
    psel_i    <= 1'b0;
    penable_i <= 1'b0;
    pwrite_i  <= 1'b0;
    paddr_i   <= '0;
    pwdata_i  <= '0;
  endtask

  // SAME stimulus style as your tb: pending branch + retire EQ
task automatic do_one_branch_safe(input logic [XLEN-1:0] pc, input logic taken);

  // wait until DUT is not stalling (prevents internal FIFO/arb edge cases)
  while (stall_o) @(posedge clk_i);

  // ---- pending branch record ----
  @(negedge clk_i);
  cpu_branch_valid_i <= 1'b1;
  //cpu_is_taken_i     <= taken;
  cpu_cf_type_i      <= Branch;
  cpu_disc_pc_i      <= pc;
/*
  @(posedge clk_i);
  @(negedge clk_i);
  cpu_branch_valid_i <= 1'b0;
  cpu_is_taken_i     <= 1'b0;
  cpu_cf_type_i      <= NoCF;
  cpu_disc_pc_i      <= '0;  */

  // *** IMPORTANT spacing (avoid same-cycle internal feedback) ***
  @(posedge clk_i);

  // wait again if DUT asserts stall after branch bookkeeping
  while (stall_o) @(posedge clk_i);

  // ---- retire branch instruction (EQ) ----
  @(negedge clk_i);
  cpu_valid_i[0] <= 1'b1;
  cpu_pc_i[0]    <= pc;
  cpu_op_i[0]    <= EQ;

  @(posedge clk_i);
  @(negedge clk_i);
  cpu_valid_i[0] <= 1'b0;
  cpu_pc_i[0]    <= '0;
  cpu_op_i[0]    <= ADD;

  // *** another spacing ***
  @(posedge clk_i);

endtask


  // Debug monitors
  int unsigned pkt_cnt, atb_cnt;

  // INTERNAL packet emission from tracer_top (hierarchical signals)
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      if (dut.pkt_valid[0]) begin
        pkt_cnt++;
        $display("[PKT] t=%0t cnt=%0d type=0x%0h len=%0d payload[127:0]=0x%0h",
                 $time, pkt_cnt, dut.pkt_type[0], dut.pkt_length[0], dut.pkt_payload[0][127:0]);
      end
      if (stall_o) $display("[STALL] t=%0t stall_o=1", $time);
    end
  end

  // ATB beats 
  /*
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      if (atvalid_o && atready_i) begin
        atb_cnt++;
        $display("[ATB] t=%0t beat=%0d bytes=%0d id=0x%0h data=0x%0h",
                 $time, atb_cnt, atbytes_o, atid_o, atdata_o);
      end
    end
  end */
/*
  // Global watchdog
  initial begin
    int unsigned cyc = 0;
    wait (rst_ni === 1'b1);
    forever begin
      @(posedge clk_i);
      cyc++;
      if (cyc > 50000) $fatal(1, "[TB] GLOBAL TIMEOUT t=%0t pkt_cnt=%0d atb_cnt=%0d", $time, pkt_cnt, atb_cnt);
    end
  end  
always @(posedge clk_i) begin
  //$display("HEARTBEAT t=%0t", $time);
end
initial begin
  int unsigned dc = 0;
  wait(rst_ni);
  forever begin
    #0; // advance delta-cycle (NOT time)
    dc++;
    if (dc == 1000000) begin
      $fatal(1, "[TB] DELTA-CYCLE HANG detected at t=%0t", $time);
    end
  end
end   */
  // MAIN
  logic [XLEN-1:0] pc_base;
  initial begin
    rst_ni = 1'b0;
drive_defaults();

// hold reset for a few cycles
 repeat (1) @(posedge clk_i);

// RELEASE RESET OFF EDGE
//@(negedge clk_i);
//#1ps;
rst_ni = 1'b1;

$display("[TB] Reset released at t=%0t", $time);

    step(10);

    //$display("[TB] APB enable trace TRACE_STATE=1");
    //apb_write32(APB_ADDR_WIDTH'(te_pkg::TRACE_STATE), 32'h1);
    //step(10);

    pc_base = 64'h0000_0000_0000_8000;

    $display("[TB] Doing 200 branch events (pending + EQ retire)...");
    for (int i=0; i<200; i++) begin
      //do_one_branch_safe(pc_base + (i*4), (i & 1));
      //do_one_branch_safe(pc_base + (i*4),0);
      do_one_branch_safe(pc_base + (i*4),1);
      
    end

    $display("[TB] Drain 300 cycles...");
    step(3000);

    $display("[TB] SUMMARY pkt_cnt=%0d atb_cnt=%0d at t=%0t", pkt_cnt, atb_cnt, $time);
    $finish;
  end

  //initial begin
  //$monitor("T=%0t | DUT STATE = %p", $time, dut);
  //end

    initial begin
      $display("rv_tracer: %m");
    end

endmodule
