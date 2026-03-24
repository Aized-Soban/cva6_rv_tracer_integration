
module tb_tracer_top;

  import connector_pkg::*;

  localparam int unsigned NRET           = 2;
  localparam int unsigned N              = 1;
  localparam int unsigned FIFO_DEPTH     = 16;
  localparam int unsigned APB_ADDR_WIDTH = 32;

  // Clock/reset
  logic clk_i, rst_ni;
  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  task automatic step(int n=1);
    repeat (n) @(posedge clk_i);
  endtask

  // Connector inputs
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

  // Connector outputs
  logic [N-1:0]                     te_valid_c;
  logic [N-1:0][IRETIRE_LEN-1:0]    te_iretire_c;
  logic [N-1:0]                     te_ilastsize_c;
  logic [N-1:0][ITYPE_LEN-1:0]      te_itype_c;
  logic [XLEN-1:0]                  te_cause_c;
  logic [XLEN-1:0]                  te_tval_c;
  logic [PRIV_LEN-1:0]              te_priv_c;
  logic [N-1:0][XLEN-1:0]           te_iaddr_c;

  // rv_tracer wiring (use te_pkg namespace)
  logic [N-1:0]                             te_valid;
  logic [N-1:0][te_pkg::IRETIRE_LEN-1:0]    te_iretire;
  logic [N-1:0]                             te_ilastsize;
  logic [N-1:0][te_pkg::ITYPE_LEN-1:0]      te_itype;
  logic [te_pkg::XLEN-1:0]                  te_cause;
  logic [te_pkg::XLEN-1:0]                  te_tval;
  logic [te_pkg::PRIV_LEN-1:0]              te_priv;
  logic [N-1:0][te_pkg::XLEN-1:0]           te_iaddr;

  assign te_valid     = te_valid_c;
  assign te_ilastsize = te_ilastsize_c;
  assign te_cause     = te_cause_c;
  assign te_tval      = te_tval_c;
  assign te_priv      = te_priv_c;

  genvar gi;
  generate
    for (gi=0; gi<N; gi++) begin : G_CAST
      assign te_iretire[gi] = te_iretire_c[gi];
      assign te_itype[gi]   = te_itype_c[gi];
      assign te_iaddr[gi]   = te_iaddr_c[gi];
    end
  endgenerate

  // APB + support for rv_tracer
  logic [APB_ADDR_WIDTH-1:0]        paddr_i;
  logic                             pwrite_i, psel_i, penable_i;
  logic [31:0]                      pwdata_i;
  logic                             pready_o;
  logic [31:0]                      prdata_o;

  logic [te_pkg::TIME_LEN-1:0]      time_i;
  logic [te_pkg::XLEN-1:0]          tvec_i, epc_i;
  logic                             encapsulator_ready_i;

  logic [N-1:0]                           packet_valid_o;
  te_pkg::it_packet_type_e [N-1:0]        packet_type_o;
  logic [N-1:0][te_pkg::P_LEN-1:0]        packet_length_o;
  logic [N-1:0][te_pkg::PAYLOAD_LEN-1:0]  packet_payload_o;
  logic                                  stall_o;

  // Instantiate connector
  cva6_te_connector #(
    .NRET       (NRET),
    .N          (N),
    .FIFO_DEPTH (FIFO_DEPTH)
  ) u_conn (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),

    .valid_i          (cpu_valid_i),
    .pc_i             (cpu_pc_i),
    .op_i             (cpu_op_i),
    .is_compressed_i  (cpu_is_compressed_i),

    .branch_valid_i   (cpu_branch_valid_i),
    .is_taken_i       (cpu_is_taken_i),
    .cf_type_i        (cpu_cf_type_i),
    .disc_pc_i        (cpu_disc_pc_i),

    .ex_valid_i       (cpu_ex_valid_i),
    .tval_i           (cpu_tval_i),
    .cause_i          (cpu_cause_i),
    .priv_lvl_i       (cpu_priv_lvl_i),

    .valid_o          (te_valid_c),
    .iretire_o        (te_iretire_c),
    .ilastsize_o      (te_ilastsize_c),
    .itype_o          (te_itype_c),
    .cause_o          (te_cause_c),
    .tval_o           (te_tval_c),
    .priv_o           (te_priv_c),
    .iaddr_o          (te_iaddr_c)
  );

  // Instantiate rv_tracer
  rv_tracer #(
    .N              (N),
    .ONLY_BRANCHES  (1),
    .APB_ADDR_WIDTH (APB_ADDR_WIDTH)
  ) u_rv (
    .clk_i                 (clk_i),
    .rst_ni                (rst_ni),

    .valid_i               (te_valid),
    .itype_i               (te_itype),
    .cause_i               (te_cause),
    .tval_i                (te_tval),
    .priv_i                (te_priv),
    .iaddr_i               (te_iaddr),
    .iretire_i             (te_iretire),
    .ilastsize_i           (te_ilastsize),

    .time_i                (time_i),
    .tvec_i                (tvec_i),
    .epc_i                 (epc_i),
    .encapsulator_ready_i  (encapsulator_ready_i),

    .paddr_i               (paddr_i),
    .pwrite_i              (pwrite_i),
    .psel_i                (psel_i),
    .penable_i             (penable_i),
    .pwdata_i              (pwdata_i),

    .packet_valid_o        (packet_valid_o),
    .packet_type_o         (packet_type_o),
    .packet_length_o       (packet_length_o),
    .packet_payload_o      (packet_payload_o),
    .stall_o               (stall_o),

    .pready_o              (pready_o),
    .prdata_o              (prdata_o)
  );

  // Print connector blocks + packets (ALL lanes)
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      for (int k=0; k<N; k++) begin
        if (te_valid_c[k]) begin
          $display("[CONN] t=%0t k=%0d itype=%0d iaddr=%h iretire=%0d ilast=%0b",
                   $time, k, te_itype_c[k], te_iaddr_c[k], te_iretire_c[k], te_ilastsize_c[k]);
        end
      end
      for (int k=0; k<N; k++) begin
        if (packet_valid_o[k]) begin
          $display("[PKT ] t=%0t lane%0d type=%0d len=%0d payload[63:0]=%h",
                   $time, k, packet_type_o[k], packet_length_o[k], packet_payload_o[k][63:0]);
        end
      end
      if (stall_o) begin
        $display("[STALL] t=%0t stall_o=1", $time);
      end
    end
  end

  // Defaults
  task automatic drive_defaults();
    cpu_valid_i         = '0;
    cpu_pc_i            = '0;
    cpu_op_i[0]         = ADD;
    //cpu_op_i[1]         = ADD;
    cpu_is_compressed_i = '0;

    cpu_branch_valid_i  = 1'b0;
    cpu_is_taken_i      = 1'b0;
    cpu_cf_type_i       = NoCF;
    cpu_disc_pc_i       = '0;

    cpu_ex_valid_i      = 1'b0;
    cpu_tval_i          = '0;
    cpu_cause_i         = '0;
    cpu_priv_lvl_i      = '0;

    paddr_i             = '0;
    pwrite_i            = 1'b0;
    psel_i              = 1'b0;
    penable_i           = 1'b0;
    pwdata_i            = '0;

    time_i              = '0;
    tvec_i              = '0;
    epc_i               = '0;
    encapsulator_ready_i= 1'b1;
  endtask

  // APB write
  task automatic apb_write32(input logic [APB_ADDR_WIDTH-1:0] addr, input logic [31:0] data);
    @(negedge clk_i);
    paddr_i   <= addr;
    pwdata_i  <= data;
    pwrite_i  <= 1'b1;
    psel_i    <= 1'b1;
    penable_i <= 1'b0;

    @(negedge clk_i);
    penable_i <= 1'b1;

    do @(negedge clk_i); while (!pready_o);

    psel_i    <= 1'b0;
    penable_i <= 1'b0;
    pwrite_i  <= 1'b0;
    paddr_i   <= '0;
    pwdata_i  <= '0;
  endtask

  // One branch event (pending + retire EQ)
  task automatic do_one_branch(input logic [XLEN-1:0] pc, input logic taken);
    // push pending record
    @(negedge clk_i);
    cpu_branch_valid_i <= 1'b1;
    cpu_is_taken_i     <= taken;
    cpu_cf_type_i      <= Branch;
    cpu_disc_pc_i      <= pc;
    @(posedge clk_i);
    @(negedge clk_i);
    cpu_branch_valid_i <= 1'b0;
    cpu_is_taken_i     <= 1'b0;
    cpu_cf_type_i      <= NoCF;
    cpu_disc_pc_i      <= '0;

    // retire branch instruction
    @(negedge clk_i);
    cpu_valid_i[0] <= 1'b1;
    cpu_pc_i[0]    <= pc;
    cpu_op_i[0]    <= EQ;
    @(posedge clk_i);
    @(negedge clk_i);
    cpu_valid_i[0] <= 1'b0;
    cpu_pc_i[0]    <= '0;
    cpu_op_i[0]    <= ADD;
  endtask

  // Wait for any packet on any lane
  task automatic wait_any_packet(input int unsigned timeout_cycles=2000);
    for (int c=0; c<timeout_cycles; c++) begin
      @(posedge clk_i);
      if (|packet_valid_o) return;
    end
    $fatal(1, "[TB] TIMEOUT: no packet emitted");
  endtask
  logic [XLEN-1:0] pc_base;

  // ----------------------------
  // Main
  // ----------------------------
  initial begin
    drive_defaults();

    rst_ni = 1'b0;
    step(5);
    rst_ni = 1'b1;
    $display("[TB] Reset released at t=%0t", $time);
    step(10);

    // Enable trace
    $display("[TB] APB enable trace TRACE_STATE=1");
    apb_write32(APB_ADDR_WIDTH'(te_pkg::TRACE_STATE), 32'h1);
    step(10);

    // ------------------------------------------------------------
    // 65 branch retirements
    // ------------------------------------------------------------
    
    pc_base = 64'h0000_0000_0000_8000;

    $display("[TB] Doing 65 branch events (pending + EQ retire), alternating taken/not-taken...");
    for (int i=0; i<65; i++) begin
      do_one_branch(pc_base + (i*4), (i % 2));
    end

    $display("[TB] Waiting for any packet after 65 branches...");
    wait_any_packet();

    $display("[TB] PASS: at least one packet emitted (see [PKT] above).");
    step(50);
    $finish;
  end

endmodule
