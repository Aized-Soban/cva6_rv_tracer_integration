// ============================================================================
// tb_tracer_top_conn_stress.sv
//
// Stress TB for packet-based tracer_top:
//
//   rvfi_to_iti_t packet --> tracer_top --> cva6_connector --> rv_tracer
//                         --> rv_encapsulator --> ATB
//
// This testbench preserves the same overall functionality as the previous TB:
//   - Drives ~100 retired instructions
//   - Includes normal bundles, taken/non-taken branches,
//     occasional exceptions, and occasional MRET
//   - Uses NrCommitPorts = 2 at the input packet
//   - Keeps the wrapper / downstream tracer path single-lane (N = 1)
//
// Notes:
//   1) This TB assumes tracer_top now has a packet input:
//        input rvfi_to_iti_t rvfi_to_iti_i
//   2) This TB assumes tracer_top internally flattens the connector output
//      packet into rv_tracer flat inputs.
//   3) Lane [0] is used for control-flow / exception events to keep stimulus
//      unambiguous and easy to debug.
// ============================================================================

`timescale 1ns/1ps

`include "rvfi_types.svh"
`include "iti_types.svh"

module tb_tracer_top_conn_stress;

  // --------------------------------------------------------------------------
  // Configuration / Parameters
  // --------------------------------------------------------------------------
  localparam config_pkg::cva6_cfg_t CVA6Cfg =
    build_config_pkg::build_config(cva6_config_pkg::cva6_cfg);

  localparam int unsigned NRET = CVA6Cfg.NrCommitPorts;
  localparam int unsigned N    = 1;   // wrapper / rv_tracer path remains single-lane

  typedef `RVFI_TO_ITI_T(CVA6Cfg)    rvfi_to_iti_t;
  typedef `ITI_TO_ENCODER_T(CVA6Cfg) iti_to_encoder_t;

  // --------------------------------------------------------------------------
  // Clock / Reset
  // --------------------------------------------------------------------------
  logic clk_i;
  logic rst_ni;

  initial clk_i = 1'b0;
  always  #5 clk_i = ~clk_i;

  // --------------------------------------------------------------------------
  // DUT Inputs
  // --------------------------------------------------------------------------
  rvfi_to_iti_t                        rvfi_to_iti_i;

  logic [te_pkg::TIME_LEN-1:0]         time_i;
  logic [te_pkg::XLEN-1:0]             tvec_i;
  logic [te_pkg::XLEN-1:0]             epc_i;

  // APB
  logic [31:0]                         paddr_i;
  logic                                pwrite_i;
  logic                                psel_i;
  logic                                penable_i;
  logic [31:0]                         pwdata_i;
  logic                                pready_o;
  logic [31:0]                         prdata_o;

  // ATB
  logic                                atready_i;
  logic                                afvalid_i;
  logic [$clog2(32)-4:0]               atbytes_o;
  logic [31:0]                         atdata_o;
  logic [6:0]                          atid_o;
  logic                                atvalid_o;
  logic                                afready_o;

  logic                                stall_o;

  // --------------------------------------------------------------------------
  // Debug taps into DUT internals
  // --------------------------------------------------------------------------
  logic [N-1:0]                                 dbg_pkt_valid;
  te_pkg::it_packet_type_e [N-1:0]              dbg_pkt_type;
  logic [N-1:0][te_pkg::P_LEN-1:0]              dbg_pkt_length;
  logic [N-1:0][te_pkg::PAYLOAD_LEN-1:0]        dbg_pkt_payload;

  logic [N-1:0]                                 dbg_te_valid;
  logic [N-1:0][te_pkg::ITYPE_LEN-1:0]          dbg_te_itype;
  logic [N-1:0][te_pkg::XLEN-1:0]        dbg_te_iaddr;

  // These taps assume tracer_top keeps the same internal names
  assign dbg_pkt_valid   = dut.pkt_valid;
  assign dbg_pkt_type    = dut.pkt_type;
  assign dbg_pkt_length  = dut.pkt_length;
  assign dbg_pkt_payload = dut.pkt_payload;

  assign dbg_te_valid    = dut.te_valid;
  assign dbg_te_itype    = dut.te_itype;
  assign dbg_te_iaddr    = dut.te_iaddr;

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  tracer_top #(
    .CVA6Cfg          (CVA6Cfg),
    .N                (N),
    .ONLY_BRANCHES    (0),
    .DATA_LEN         (32),
    .rvfi_to_iti_t    (rvfi_to_iti_t),
    .iti_to_encoder_t (iti_to_encoder_t)
  ) dut (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),

    .rvfi_to_iti_i (rvfi_to_iti_i),

    .time_i        (time_i),
    .tvec_i        (tvec_i),
    .epc_i         (epc_i),

    .paddr_i       (paddr_i),
    .pwrite_i      (pwrite_i),
    .psel_i        (psel_i),
    .penable_i     (penable_i),
    .pwdata_i      (pwdata_i),
    .pready_o      (pready_o),
    .prdata_o      (prdata_o),

    .atready_i     (atready_i),
    .afvalid_i     (afvalid_i),

    .atbytes_o     (atbytes_o),
    .atdata_o      (atdata_o),
    .atid_o        (atid_o),
    .atvalid_o     (atvalid_o),
    .afready_o     (afready_o),

    .stall_o       (stall_o)
  );

  // --------------------------------------------------------------------------
  // APB Helper
  // --------------------------------------------------------------------------
  task automatic apb_write(input logic [31:0] addr, input logic [31:0] data);
    begin
      @(negedge clk_i);
      paddr_i   <= addr;
      pwdata_i  <= data;
      pwrite_i  <= 1'b1;
      psel_i    <= 1'b1;
      penable_i <= 1'b0;

      @(negedge clk_i);
      penable_i <= 1'b1;

      while (!pready_o) @(negedge clk_i);

      @(negedge clk_i);
      psel_i    <= 1'b0;
      penable_i <= 1'b0;
      pwrite_i  <= 1'b0;
      paddr_i   <= '0;
      pwdata_i  <= '0;
    end
  endtask

  // --------------------------------------------------------------------------
  // Stimulus Helpers
  // --------------------------------------------------------------------------

  // Clear the entire packet for an idle cycle.
  task automatic clear_cycle_controls();
    begin
      rvfi_to_iti_i.valid         <= '0;
      rvfi_to_iti_i.pc            <= '0;
      rvfi_to_iti_i.op            <= '{default: ariane_pkg::ADD};
      rvfi_to_iti_i.is_compressed <= '0;
      rvfi_to_iti_i.branch_valid  <= '0;
      rvfi_to_iti_i.is_taken      <= '0;
      rvfi_to_iti_i.ex_valid      <= 1'b0;
      rvfi_to_iti_i.tval          <= '0;
      rvfi_to_iti_i.cause         <= '0;
      rvfi_to_iti_i.priv_lvl      <= riscv::PRIV_LVL_M;
      rvfi_to_iti_i.cycles        <= '0;
    end
  endtask

  // Wait until tracer path is not stalled.
  task automatic wait_no_stall();
    begin
      while (stall_o) @(posedge clk_i);
    end
  endtask

  // Drive a normal 2-wide retired bundle (no branch / no exception).
  task automatic retire_bundle2(
    input logic [CVA6Cfg.XLEN-1:0] pc0,
    input ariane_pkg::fu_op        op0,
    input logic                    c0,
    input logic [CVA6Cfg.XLEN-1:0] pc1,
    input ariane_pkg::fu_op        op1,
    input logic                    c1
  );
    begin
      wait_no_stall();
      @(negedge clk_i);

      rvfi_to_iti_i.valid[0]         <= 1'b1;
      rvfi_to_iti_i.pc[0]            <= pc0;
      rvfi_to_iti_i.op[0]            <= op0;
      rvfi_to_iti_i.is_compressed[0] <= c0;

      rvfi_to_iti_i.valid[1]         <= 1'b1;
      rvfi_to_iti_i.pc[1]            <= pc1;
      rvfi_to_iti_i.op[1]            <= op1;
      rvfi_to_iti_i.is_compressed[1] <= c1;

      rvfi_to_iti_i.branch_valid     <= '0;
      rvfi_to_iti_i.is_taken         <= '0;
      rvfi_to_iti_i.ex_valid         <= 1'b0;
      rvfi_to_iti_i.cause            <= '0;
      rvfi_to_iti_i.tval             <= '0;

      @(negedge clk_i);
      rvfi_to_iti_i.valid            <= '0;

      @(negedge clk_i);
    end
  endtask

  // Drive one conditional branch event on lane 0.
  // The simple ITI detector classifies branch type using:
  //   - op_i  : conditional branch opcode (EQ/NE/LTS/GES/LTU/GEU)
  //   - is_taken[0]
  task automatic retire_branch(
    input logic [CVA6Cfg.XLEN-1:0] pc,
    input logic                    taken
  );
    begin
      wait_no_stall();
      @(negedge clk_i);

      rvfi_to_iti_i.valid[0]         <= 1'b1;
      rvfi_to_iti_i.pc[0]            <= pc;
      rvfi_to_iti_i.op[0]            <= ariane_pkg::EQ;
      rvfi_to_iti_i.is_compressed[0] <= 1'b0;

      rvfi_to_iti_i.valid[1]         <= 1'b0;
      rvfi_to_iti_i.pc[1]            <= '0;
      rvfi_to_iti_i.op[1]            <= ariane_pkg::ADD;
      rvfi_to_iti_i.is_compressed[1] <= 1'b0;

      rvfi_to_iti_i.branch_valid     <= '0;
      rvfi_to_iti_i.is_taken         <= '0;
      rvfi_to_iti_i.branch_valid[0]  <= 1'b1;
      rvfi_to_iti_i.is_taken[0]      <= taken;

      rvfi_to_iti_i.ex_valid         <= 1'b0;
      rvfi_to_iti_i.cause            <= '0;
      rvfi_to_iti_i.tval             <= '0;

      @(negedge clk_i);
      rvfi_to_iti_i.valid[0]         <= 1'b0;
      rvfi_to_iti_i.branch_valid[0]  <= 1'b0;

      @(negedge clk_i);
    end
  endtask

  // Drive one exception event on lane 0.
  task automatic retire_exception(
    input logic [CVA6Cfg.XLEN-1:0] pc,
    input logic [CVA6Cfg.XLEN-1:0] cause,
    input logic [CVA6Cfg.XLEN-1:0] tval
  );
    begin
      wait_no_stall();
      @(negedge clk_i);

      rvfi_to_iti_i.valid[0]         <= 1'b1;
      rvfi_to_iti_i.pc[0]            <= pc;
      rvfi_to_iti_i.op[0]            <= ariane_pkg::ECALL;
      rvfi_to_iti_i.is_compressed[0] <= 1'b0;

      rvfi_to_iti_i.valid[1]         <= 1'b0;
      rvfi_to_iti_i.op[1]            <= ariane_pkg::ADD;
      rvfi_to_iti_i.is_compressed[1] <= 1'b0;

      rvfi_to_iti_i.branch_valid     <= '0;
      rvfi_to_iti_i.is_taken         <= '0;

      rvfi_to_iti_i.ex_valid         <= 1'b1;
      rvfi_to_iti_i.cause            <= cause;
      rvfi_to_iti_i.tval             <= tval;

      @(negedge clk_i);
      rvfi_to_iti_i.valid[0]         <= 1'b0;
      rvfi_to_iti_i.ex_valid         <= 1'b0;

      @(negedge clk_i);
    end
  endtask

  // Drive one ERET event on lane 0.
  task automatic retire_eret(
    input logic [CVA6Cfg.XLEN-1:0] pc,
    input ariane_pkg::fu_op        eret_op
  );
    begin
      wait_no_stall();
      @(negedge clk_i);

      rvfi_to_iti_i.valid[0]         <= 1'b1;
      rvfi_to_iti_i.pc[0]            <= pc;
      rvfi_to_iti_i.op[0]            <= eret_op;
      rvfi_to_iti_i.is_compressed[0] <= 1'b0;

      rvfi_to_iti_i.valid[1]         <= 1'b0;
      rvfi_to_iti_i.op[1]            <= ariane_pkg::ADD;
      rvfi_to_iti_i.is_compressed[1] <= 1'b0;

      rvfi_to_iti_i.branch_valid     <= '0;
      rvfi_to_iti_i.is_taken         <= '0;
      rvfi_to_iti_i.ex_valid         <= 1'b0;
      rvfi_to_iti_i.cause            <= '0;
      rvfi_to_iti_i.tval             <= '0;

      @(negedge clk_i);
      rvfi_to_iti_i.valid[0]         <= 1'b0;

      @(negedge clk_i);
    end
  endtask

  // --------------------------------------------------------------------------
  // Monitors
  // --------------------------------------------------------------------------
  int unsigned atb_count;
  int unsigned evt_count;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      atb_count <= 0;
      evt_count <= 0;
    end else begin
      if (|rvfi_to_iti_i.valid) evt_count++;

      if (atvalid_o && atready_i) begin
        atb_count++;
        $display("[ATB] t=%0t beat=%0d atid=0x%0h atbytes=%0d atdata=0x%08x",
                 $time, atb_count, atid_o, atbytes_o, atdata_o);
      end

      if (dbg_te_valid[0]) begin
        $display("[TE ] t=%0t te_itype=%0d te_iaddr=0x%0h",
                 $time, dbg_te_itype[0], dbg_te_iaddr[0]);
      end

      if (stall_o) begin
        $display("[STALL] t=%0t stall_o=1", $time);
      end
    end
  end

  // Backpressure pattern on ATB: deassert ready 1/8 cycles.
  always_ff @(posedge clk_i) begin
    if (!rst_ni) atready_i <= 1'b1;
    else         atready_i <= (time_i[2:0] != 3'b111);
  end

  // Free-running time counter.
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      time_i <= '0;
    end else begin
      time_i <= time_i + 1;
    end
  end

  // Keep the cycle field in the packet aligned with time_i.
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      rvfi_to_iti_i.cycles <= '0;
    end else begin
      rvfi_to_iti_i.cycles <= time_i;
    end
  end

  // --------------------------------------------------------------------------
  // Main Test
  // --------------------------------------------------------------------------
  logic [CVA6Cfg.XLEN-1:0] pc;

  initial begin
    rst_ni = 1'b0;

    clear_cycle_controls();

    tvec_i   = 64'h0000_0000_0000_1000;
    epc_i    = '0;

    paddr_i   = '0;
    pwrite_i  = 1'b0;
    psel_i    = 1'b0;
    penable_i = 1'b0;
    pwdata_i  = '0;

    afvalid_i = 1'b1;

    repeat (10) @(negedge clk_i);
    rst_ni = 1'b1;

    // Optional tracer configuration can be restored here if needed.
    // Example:
    // apb_write(32'h0000_001c, 32'h0000_0001);

    pc = 64'h0000_0000_0000_1000;

    // ----------------------------------------------------------------------
    // Same functional spirit as previous TB:
    //   - mostly branches
    //   - some normal bundles
    //   - occasional exception / mret mixed in
    // ----------------------------------------------------------------------
    for (int i = 0; i < 100; i++) begin
      if ((i % 16) == 0)
        epc_i <= pc;

      if ((i % 33) == 7) begin
        retire_exception(pc, 64'hB, 64'hDEAD_BEEF);
        pc = pc + 64'd4;
      end
      else if ((i % 33) == 8) begin
        retire_eret(pc, ariane_pkg::MRET);
        pc = pc + 64'd4;
      end
      else if (i < 90) begin
        retire_branch(pc, (i[0] == 1'b0)); // alternate taken / non-taken
        pc = pc + 64'd4;
      end
      else begin
        ariane_pkg::fu_op op0, op1;
        logic c0, c1;

        unique case (i % 6)
          0: begin op0 = ariane_pkg::ADD;  op1 = ariane_pkg::XORL; end
          1: begin op0 = ariane_pkg::LD;   op1 = ariane_pkg::SD;   end
          2: begin op0 = ariane_pkg::ORL;  op1 = ariane_pkg::ANDL; end
          3: begin op0 = ariane_pkg::SLL;  op1 = ariane_pkg::SRL;  end
          4: begin op0 = ariane_pkg::MUL;  op1 = ariane_pkg::DIV;  end
          default: begin op0 = ariane_pkg::LW; op1 = ariane_pkg::SW; end
        endcase

        c0 = i[0];
        c1 = i[1];

        retire_bundle2(pc, op0, c0, pc + 64'd4, op1, c1);
        pc = pc + 64'd8;
      end
    end

    // Let the tracer / encapsulator drain.
    repeat (400) @(posedge clk_i);

    if (atb_count == 0)
      $fatal(1, "[TB] ERROR: No ATB beats observed. Trace is not emitting.");
    else
      $display("[TB] DONE: cycles-with-retire=%0d  atb_beats=%0d", evt_count, atb_count);

    $finish;
  end

endmodule