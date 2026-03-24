// tb_tracer_top_non45.sv
`timescale 1ns/1ps

module tb_tracer_top;

  // ----------------------------
  // Parameters
  // ----------------------------
  localparam int unsigned NRET = 2;
  localparam int unsigned N    = 1;   // keep 1 to avoid lane issues

  // ----------------------------
  // Clock / Reset
  // ----------------------------
  logic clk_i;
  logic rst_ni;

  initial clk_i = 0;
  always  #5 clk_i = ~clk_i;

  // ----------------------------
  // DUT inputs
  // ----------------------------
  logic [NRET-1:0]                          cpu_valid_i;
  logic [NRET-1:0][connector_pkg::XLEN-1:0]  cpu_pc_i;
  connector_pkg::fu_op [NRET-1:0]           cpu_op_i;
  logic [NRET-1:0]                          cpu_is_compressed_i;

  logic                                     cpu_branch_valid_i;
  logic                                     cpu_is_taken_i;
  connector_pkg::cf_t                       cpu_cf_type_i;
  logic [connector_pkg::XLEN-1:0]           cpu_disc_pc_i;

  logic                                     cpu_ex_valid_i;
  logic [connector_pkg::XLEN-1:0]           cpu_tval_i;
  logic [connector_pkg::XLEN-1:0]           cpu_cause_i;
  logic [connector_pkg::PRIV_LEN-1:0]       cpu_priv_lvl_i;

  logic [te_pkg::TIME_LEN-1:0]              time_i;
  logic [te_pkg::XLEN-1:0]                  tvec_i;
  logic [te_pkg::XLEN-1:0]                  epc_i;

  logic [31:0]                              paddr_i;
  logic                                     pwrite_i;
  logic                                     psel_i;
  logic                                     penable_i;
  logic [31:0]                              pwdata_i;
  logic                                     pready_o;
  logic [31:0]                              prdata_o;

  logic                                     atready_i;
  logic                                     afvalid_i;

  logic [$clog2(32)-4:0]                    atbytes_o;
  logic [31:0]                              atdata_o;
  logic [6:0]                               atid_o;
  logic                                     atvalid_o;
  logic                                     afready_o;
  logic                                     stall_o;

  // ----------------------------
  // DUT
  // ----------------------------
  tracer_top #(
    .NRET          (NRET),
    .N             (N),
    .ONLY_BRANCHES (0)    // IMPORTANT: allow non-branch packets
  ) dut (
    .clk_i,
    .rst_ni,

    .cpu_valid_i,
    .cpu_pc_i,
    .cpu_op_i,
    .cpu_is_compressed_i,

    .cpu_branch_valid_i,
    .cpu_is_taken_i,
    .cpu_cf_type_i,
    .cpu_disc_pc_i,

    .cpu_ex_valid_i,
    .cpu_tval_i,
    .cpu_cause_i,
    .cpu_priv_lvl_i,

    .time_i,
    .tvec_i,
    .epc_i,

    .paddr_i,
    .pwrite_i,
    .psel_i,
    .penable_i,
    .pwdata_i,
    .pready_o,
    .prdata_o,

    .atready_i,
    .afvalid_i,

    .atbytes_o,
    .atdata_o,
    .atid_o,
    .atvalid_o,
    .afready_o,

    .stall_o
  );

  // ----------------------------
  // APB helpers
  // ----------------------------
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

      @(negedge clk_i);
      psel_i    <= 1'b0;
      penable_i <= 1'b0;
      pwrite_i  <= 1'b0;
      paddr_i   <= '0;
      pwdata_i  <= '0;
    end
  endtask

  // ----------------------------
  // "Retire" helpers (NO itype 4/5)
  // ----------------------------
  task automatic retire_std(input logic [connector_pkg::XLEN-1:0] pc,
                            input connector_pkg::fu_op op);
    begin
      // No branch, no exception => STD (itype=0)
      cpu_pc_i[0]            <= pc;
      cpu_op_i[0]            <= op;
      cpu_valid_i[0]         <= 1'b1;
      cpu_is_compressed_i[0] <= 1'b0;

      cpu_branch_valid_i     <= 1'b0;
      cpu_is_taken_i         <= 1'b0;
      cpu_cf_type_i          <= connector_pkg::NoCF;
      cpu_disc_pc_i          <= '0;

      cpu_ex_valid_i         <= 1'b0;
      cpu_cause_i            <= '0;
      cpu_tval_i             <= '0;

      @(negedge clk_i);
      cpu_valid_i[0]         <= 1'b0;
      @(negedge clk_i);
    end
  endtask

  task automatic raise_exception(input logic [connector_pkg::XLEN-1:0] pc,
                                 input logic [connector_pkg::XLEN-1:0] cause,
                                 input logic [connector_pkg::XLEN-1:0] tval);
    begin
      // EXC (itype=1) via ex_valid
      cpu_pc_i[0]            <= pc;
      cpu_op_i[0]            <= connector_pkg::ECALL; // doesn't hurt
      cpu_valid_i[0]         <= 1'b1;
      cpu_is_compressed_i[0] <= 1'b0;

      cpu_branch_valid_i     <= 1'b0;
      cpu_is_taken_i         <= 1'b0;
      cpu_cf_type_i          <= connector_pkg::NoCF;
      cpu_disc_pc_i          <= '0;

      cpu_ex_valid_i         <= 1'b1;
      cpu_cause_i            <= cause;
      cpu_tval_i             <= tval;

      @(negedge clk_i);
      cpu_valid_i[0]         <= 1'b0;
      cpu_ex_valid_i         <= 1'b0;
      @(negedge clk_i);
    end
  endtask

  task automatic do_eret(input logic [connector_pkg::XLEN-1:0] pc,
                         input connector_pkg::fu_op eret_op);
    begin
      // ERET (itype=3): MRET/SRET/DRET
      cpu_pc_i[0]            <= pc;
      cpu_op_i[0]            <= eret_op;
      cpu_valid_i[0]         <= 1'b1;
      cpu_is_compressed_i[0] <= 1'b0;

      cpu_branch_valid_i     <= 1'b0;
      cpu_is_taken_i         <= 1'b0;
      cpu_cf_type_i          <= connector_pkg::NoCF;
      cpu_disc_pc_i          <= '0;

      cpu_ex_valid_i         <= 1'b0;
      cpu_cause_i            <= '0;
      cpu_tval_i             <= '0;

      @(negedge clk_i);
      cpu_valid_i[0]         <= 1'b0;
      @(negedge clk_i);
    end
  endtask

  task automatic do_jump_event(input logic [connector_pkg::XLEN-1:0] pc,
                               input logic [connector_pkg::XLEN-1:0] target,
                               input connector_pkg::cf_t cftype);
    begin
      // Jump/JumpR/Return event:
      // IMPORTANT: cftype != Branch, so you avoid NTB/TB (4/5)
      cpu_pc_i[0]            <= pc;
      cpu_op_i[0]            <= connector_pkg::JALR; // generic for jump-ish
      cpu_valid_i[0]         <= 1'b1;
      cpu_is_compressed_i[0] <= 1'b0;

      cpu_branch_valid_i     <= 1'b1;
      cpu_is_taken_i         <= 1'b1;
      cpu_cf_type_i          <= cftype;              // Jump / JumpR / Return
      cpu_disc_pc_i          <= target;

      cpu_ex_valid_i         <= 1'b0;
      cpu_cause_i            <= '0;
      cpu_tval_i             <= '0;

      @(negedge clk_i);
      cpu_valid_i[0]         <= 1'b0;
      cpu_branch_valid_i     <= 1'b0;
      @(negedge clk_i);
    end
  endtask

  // ----------------------------
  // Monitors
  // ----------------------------
  always @(posedge clk_i) begin
    if (rst_ni) begin
      // Watch connector output itype (lane0)
      $display("[t=%0t] te_valid=%0b te_itype=%0d  atvalid=%0b atbytes=%0d atdata=0x%08x stall=%0b",
               $time,
               dut.te_valid[0],
               dut.te_itype[0],
               atvalid_o,
               atbytes_o,
               atdata_o,
               stall_o);
    end
  end

  // ----------------------------
  // Main
  // ----------------------------
  initial begin
    // defaults
    cpu_valid_i          = '0;
    cpu_pc_i             = '0;
    cpu_op_i             = '{default: connector_pkg::ADD};
    cpu_is_compressed_i  = '0;

    cpu_branch_valid_i   = 1'b0;
    cpu_is_taken_i       = 1'b0;
    cpu_cf_type_i        = connector_pkg::NoCF;
    cpu_disc_pc_i        = '0;

    cpu_ex_valid_i       = 1'b0;
    cpu_tval_i           = '0;
    cpu_cause_i          = '0;
    cpu_priv_lvl_i       = '0;

    time_i               = '0;
    tvec_i               = '0;
    epc_i                = '0;

    paddr_i              = '0;
    pwrite_i             = 1'b0;
    psel_i               = 1'b0;
    penable_i            = 1'b0;
    pwdata_i             = '0;

    atready_i            = 1'b1;   // keep ready high
    afvalid_i            = 1'b1;   // allow aux flow

    // reset
    rst_ni = 1'b0;
    repeat (5) @(negedge clk_i);
    rst_ni = 1'b1;

    // time tick
    fork
      begin
        forever begin
          @(posedge clk_i);
          if (rst_ni) time_i <= time_i + 1;
        end
      end
    join_none

    // enable tracing (adjust addr/data if your te_reg differs)
    // Most PULP rv_tracer uses a "trace enable" bit in a control reg.
    // If your address differs, keep this but change the address.
    apb_write(32'h0000_0000, 32'h0000_0001);

    // ---- Drive events (NO branch CF) ----
    retire_std(64'h0000_1000, connector_pkg::ADD);
    retire_std(64'h0000_1004, connector_pkg::LD);

    do_jump_event(64'h0000_1008, 64'h0000_2000, connector_pkg::Jump);
    do_jump_event(64'h0000_100C, 64'h0000_3000, connector_pkg::JumpR);
    do_jump_event(64'h0000_1010, 64'h0000_4000, connector_pkg::Return);

    raise_exception(64'h0000_1014, 64'h0000_000B, 64'hDEAD_BEEF); // cause/tval example
    do_eret(64'h0000_1018, connector_pkg::MRET);

    // More STD noise
    repeat (20) begin
      retire_std(64'h0000_1100 + {$random} % 64, connector_pkg::XORL);
    end

    // run
    repeat (200) @(posedge clk_i);
    $finish;
  end

endmodule
