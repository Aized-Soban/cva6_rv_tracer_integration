`timescale 1ns/1ps

module tb_rv_tracer_only;

  localparam int unsigned N              = 1;
  // IMPORTANT: set this to 0 so other itypes are not blocked by the ONLY_BRANCHES build.
  localparam int unsigned ONLY_BRANCHES  = 0;
  localparam int unsigned APB_ADDR_WIDTH = 32;

  import te_pkg::*;

  logic clk_i;
  logic rst_ni;

  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  // DUT inputs
  logic [N-1:0]                        valid_i;
  logic [N-1:0][ITYPE_LEN-1:0]         itype_i;
  logic [XLEN-1:0]                     cause_i;
  logic [XLEN-1:0]                     tval_i;
  logic [PRIV_LEN-1:0]                 priv_i;
  logic [N-1:0][XLEN-1:0]              iaddr_i;
  logic [N-1:0][IRETIRE_LEN-1:0]       iretire_i;
  logic [N-1:0]                        ilastsize_i;
  logic [TIME_LEN-1:0]                 time_i;
  logic [XLEN-1:0]                     tvec_i;
  logic [XLEN-1:0]                     epc_i;
  logic                                encapsulator_ready_i;

  // APB in
  logic [APB_ADDR_WIDTH-1:0]           paddr_i;
  logic                                pwrite_i;
  logic                                psel_i;
  logic                                penable_i;
  logic [31:0]                         pwdata_i;

  // DUT outputs
  logic [N-1:0]                        packet_valid_o;
  it_packet_type_e [N-1:0]             packet_type_o;
  logic [N-1:0][P_LEN-1:0]             packet_length_o;
  logic [N-1:0][PAYLOAD_LEN-1:0]       packet_payload_o;
  logic                                stall_o;

  // APB out
  logic                                pready_o;
  logic [31:0]                         prdata_o;

  rv_tracer #(
    .N(N),
    .ONLY_BRANCHES(ONLY_BRANCHES),
    .APB_ADDR_WIDTH(APB_ADDR_WIDTH)
  ) dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .valid_i(valid_i),
    .itype_i(itype_i),
    .cause_i(cause_i),
    .tval_i(tval_i),
    .priv_i(priv_i),
    .iaddr_i(iaddr_i),
    .iretire_i(iretire_i),
    .ilastsize_i(ilastsize_i),
    .time_i(time_i),
    .tvec_i(tvec_i),
    .epc_i(epc_i),
    .encapsulator_ready_i(encapsulator_ready_i),

    .paddr_i(paddr_i),
    .pwrite_i(pwrite_i),
    .psel_i(psel_i),
    .penable_i(penable_i),
    .pwdata_i(pwdata_i),

    .packet_valid_o(packet_valid_o),
    .packet_type_o(packet_type_o),
    .packet_length_o(packet_length_o),
    .packet_payload_o(packet_payload_o),
    .stall_o(stall_o),

    .pready_o(pready_o),
    .prdata_o(prdata_o)
  );

  // ---------------- APB tasks ----------------
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

  task automatic apb_read(input logic [APB_ADDR_WIDTH-1:0] addr, output logic [31:0] data);
    @(posedge clk_i);
    paddr_i   <= addr;
    pwrite_i  <= 1'b0;
    psel_i    <= 1'b1;
    penable_i <= 1'b0;

    @(posedge clk_i);
    penable_i <= 1'b1;

    while (!pready_o) @(posedge clk_i);
    data = prdata_o;

    @(posedge clk_i);
    psel_i    <= 1'b0;
    penable_i <= 1'b0;
    paddr_i   <= '0;
  endtask

  // ---------------- Main stimulus primitive ----------------
  // You control itype here.
  // iretire_i is in HALFWORDS (your previous TB used 2 for one 32-bit inst).
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
      valid_i[0]      <= 1'b1;
      itype_i[0]      <= logic'(itype_val[ITYPE_LEN-1:0]);
      iaddr_i[0]      <= pc;
      iretire_i[0]    <= halfwords_retired;
      ilastsize_i[0]  <= last_is_32b ? 1'b1 : 1'b0;

      cause_i         <= cause;
      epc_i           <= epc;
      tval_i          <= tval;
      tvec_i          <= tvec;
      priv_i          <= priv;

      @(posedge clk_i);

      valid_i[0]      <= 1'b0;
      itype_i[0]      <= '0;
      iaddr_i[0]      <= '0;
      iretire_i[0]    <= '0;
      ilastsize_i[0]  <= '0;

      // keep cause/epc/tval/tvec stable if you want, or clear:
      // cause_i <= '0; epc_i <= '0; tval_i <= '0; tvec_i <= '0;

      @(posedge clk_i);
    end
  endtask

  // ---------------- Console monitors ----------------
  // Packet prints
  always_ff @(posedge clk_i) begin
    if (rst_ni && packet_valid_o[0]) begin
      $display("[PKT] t=%0t type=%0d len=%0d payload=0x%0h",
               $time, packet_type_o[0], packet_length_o[0], packet_payload_o[0]);
    end
    if (rst_ni && stall_o) begin
      $display("[STALL] t=%0t stall_o=1", $time);
    end
  end

  // “Progress” prints when key TB-driven inputs change (helps pinpoint last good cycle)
  logic [ITYPE_LEN-1:0] itype_prev;
  logic                 valid_prev;
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      itype_prev <= '0;
      valid_prev <= 1'b0;
    end else begin
      if ((itype_i[0] != itype_prev) || (valid_i[0] != valid_prev)) begin
        $display("[IN ] t=%0t valid=%0b itype=%0d pc=0x%0h iretire=%0d ilastsize=%0b time=%0d",
                 $time, valid_i[0], itype_i[0], iaddr_i[0], iretire_i[0], ilastsize_i[0], time_i);
      end
      itype_prev <= itype_i[0];
      valid_prev <= valid_i[0];
    end
  end

  // ---------------- Helpers: parse +ITYPES=4,5,1,... ----------------
  int unsigned itype_list [0:255];
  int unsigned itype_count;

  function automatic int unsigned parse_u32_token(string s);
    int unsigned v;
    if ($sscanf(s, "%d", v) != 1) v = 0;
    return v;
  endfunction

  task automatic load_itypes_from_plusarg();
    string arg, tok;
    int idx, n;
    begin
      itype_count = 0;
      if ($value$plusargs("ITYPES=%s", arg)) begin
        idx = 0;
        while (idx < arg.len() && itype_count < 256) begin
          // grab token until comma
          tok = "";
          while (idx < arg.len() && arg[idx] != ",") begin
            tok = {tok, arg[idx]};
            idx++;
          end
          if (tok.len() > 0) begin
            itype_list[itype_count] = parse_u32_token(tok);
            itype_count++;
          end
          // skip comma
          if (idx < arg.len() && arg[idx] == ",") idx++;
        end
      end
    end
  endtask

  // ---------------- Main ----------------
  logic [31:0] rdata;
  int unsigned single_itype;
  bit use_single;
  bit use_mixed;

  initial begin
    // defaults
    rst_ni               = 1'b0;
    valid_i              = '0;
    itype_i              = '0;
    cause_i              = '0;
    tval_i               = '0;
    priv_i               = 2'b11;
    iaddr_i              = '0;
    iretire_i            = '0;
    ilastsize_i          = '0;
    time_i               = '0;
    tvec_i               = '0;
    epc_i                = '0;
    encapsulator_ready_i = 1'b1;

    paddr_i              = '0;
    pwrite_i             = 1'b0;
    psel_i               = 1'b0;
    penable_i            = 1'b0;
    pwdata_i             = '0;

    // mode select
    use_single = $value$plusargs("SINGLE_ITYPE=%d", single_itype);
    use_mixed  = $test$plusargs("MIXED");

    load_itypes_from_plusarg();

    repeat (20) @(posedge clk_i);
    rst_ni = 1'b1;
    $display("[TB] Reset released at t=%0t", $time);

    repeat (10) @(posedge clk_i);

    apb_read (32'h0000_001c, rdata);
    $display("[TB] TRACE_STATE readback = 0x%08x", rdata);

    apb_write(32'h0000_001c, 32'h0000_0001); // enable/activate

    // Run
    if (use_single) begin
      $display("[TB] Running SINGLE itype=%0d for 300 events", single_itype);
      for (int k = 0; k < 300; k++) begin
        time_i <= time_i + 64'd1;
        drive_event(single_itype,
                    64'h0000_0000_0000_1200 + (k*4),
                    32'd2, 1'b1,
                    32'h0, 32'h0, 32'h0, 32'h0, 2'b11);
      end
    end
    else if (itype_count != 0) begin
      $display("[TB] Running custom ITYPES list (count=%0d)", itype_count);
      for (int k = 0; k < 300; k++) begin
        int unsigned it = itype_list[k % itype_count];
        time_i <= time_i + 64'd1;

        // For “exception-like” itypes you can optionally drive cause/epc/tval/tvec nonzero
        drive_event(it,
                    64'h0000_0000_0000_1200 + (k*4),
                    32'd2, 1'b1,
                    (it == 2) ? 32'h0000_000B : 32'h0,     // example: cause=11
                    (it == 2) ? 32'h0000_2000 : 32'h0,     // epc
                    (it == 2) ? 32'hDEAD_BEEF : 32'h0,     // tval
                    (it == 2) ? 32'h0000_1000 : 32'h0,     // tvec
                    2'b11);
      end
    end
    else begin
      // Default mixed pattern focusing on your suspected deadlock itypes 4/5
      $display("[TB] Running MIXED default pattern for 400 events (includes itype 4 & 5)");
      for (int k = 0; k < 400; k++) begin
        int unsigned it;
        time_i <= time_i + 64'd1;

        unique case (k % 10)
          0,1,2,3: it = 4;   // branch class A
          4,5:     it = 5;   // branch class B (suspect)
          6:       it = 0;   // “normal/none”
          7:       it = 1;   // another type
          8:       it = 2;   // “exception-like” example
          default:  it = 3;  // another type
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
    end

    repeat (200) @(posedge clk_i);
    $display("[TB] DONE.");
    $finish;
  end

endmodule
