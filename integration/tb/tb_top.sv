`timescale 1ns/1ps

module tb_top;

  logic clk_i;
  logic rst_ni;

  localparam config_pkg::cva6_cfg_t CVA6Cfg =
  build_config_pkg::build_config(cva6_config_pkg::cva6_cfg);

  logic [CVA6Cfg.VLEN-1:0] boot_addr_i;
  logic [31:0] tb_exit_o;


typedef `RVFI_INSTR_T(CVA6Cfg)        rvfi_instr_t;
typedef `RVFI_CSR_ELMT_T(CVA6Cfg)     rvfi_csr_elmt_t;
typedef `RVFI_CSR_T(CVA6Cfg, rvfi_csr_elmt_t) rvfi_csr_t;


rvfi_instr_t [CVA6Cfg.NrCommitPorts-1:0] rvfi_o;
rvfi_csr_t                               rvfi_csr_o;


// clock generation
  initial begin
    clk_i = 1'b0;
    forever #5 clk_i = ~clk_i;
  end
  // boot address
  initial begin
    rst_ni = 1'b0;
    boot_addr_i = 'h8000_0000;
    repeat (20) @(posedge clk_i);
    rst_ni = 1'b1;
  end

  cva6_wrapper #(
    .CVA6Cfg(CVA6Cfg),
    .AXI_USER_EN(0),
    .NUM_WORDS(2**25)
  ) dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .boot_addr_i(boot_addr_i),
    .tb_exit_o(tb_exit_o),
    .rvfi_o(rvfi_o),
    .rvfi_csr_o(rvfi_csr_o)
  );

  //(VCD)
  initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb_top);
  end

  // -----------------------------
  // Stop conditions
  // -----------------------------
  // 1) stop when tb_exit_o changes (your rvfi_tracer drives end_of_test_o)
  // 2) stop after timeout
  /*
  initial begin : watchdog
    int unsigned cycles = 0;
    int unsigned max_cycles = 2_000_000; // adjust as needed

    // Wait until reset deassert
    wait (rst_ni === 1'b1);

    while (cycles < max_cycles) begin
      @(posedge clk_i);
      cycles++;

      // If your tracer uses tb_exit_o as "end", stop when non-zero
      if (tb_exit_o !== 32'b0) begin
        $display("[TB] tb_exit_o=%0d (0x%08x) at cycle %0d. Finishing.",
                 tb_exit_o, tb_exit_o, cycles);
        #20;
        $finish;
      end
    end

    $display("[TB] TIMEOUT after %0d cycles. Finishing.", max_cycles);
    $finish;
  end
  */

endmodule