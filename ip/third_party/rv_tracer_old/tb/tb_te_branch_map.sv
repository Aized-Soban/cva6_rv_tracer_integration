`timescale 1ns/1ps


module tb_te_branch_map;

  localparam int N = 4;

  // ----------------------------
  // Clock / reset
  // ----------------------------
  logic clk_i;
  logic rst_ni;

  // ----------------------------
  // DUT I/O
  // ----------------------------
  logic [N-1:0] valid_i;
  logic [N-1:0] branch_taken_i;
  logic         flush_i;

  logic [te_pkg::BRANCH_MAP_LEN-1:0]    map_o;
  logic [te_pkg::BRANCH_COUNT_LEN-1:0]  branches_o;
  logic                                 is_full_o;
  logic                                 is_empty_o;
  logic [te_pkg::BRANCH_MAP_LEN-1:0] map_full_snapshot;
  // ----------------------------
  // Instantiate DUT
  // ----------------------------
  te_branch_map #(.N(N)) dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .valid_i(valid_i),
    .branch_taken_i(branch_taken_i),
    .flush_i(flush_i),
    .map_o(map_o),
    .branches_o(branches_o),
    .is_full_o(is_full_o),
    .is_empty_o(is_empty_o)
  );

  // ----------------------------
  // Clock generation: 100MHz
  // ----------------------------
  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  // ----------------------------
  // Reference model
  // ----------------------------
  logic [te_pkg::BRANCH_MAP_LEN-1:0] ref_map;
  int unsigned                       ref_cnt; // 0..31

  // buffered (leftover) branches: store taken bits, oldest at index 0
  bit status_q[$];

  // The DUT registers inputs into valid_q/branch_taken_q and uses those in always_comb.
  // So, functionality has a 1-cycle latency w.r.t. valid_i/branch_taken_i.
  logic [N-1:0] prev_valid;
  logic [N-1:0] prev_taken;

  function automatic logic calc_full(int unsigned cnt, logic fl);
    return (cnt == 31) && ~fl;
  endfunction

  task automatic check_outputs(string tag);
    logic [te_pkg::BRANCH_COUNT_LEN-1:0] ref_cnt_slv;
    logic ref_full, ref_empty;

    ref_cnt_slv = ref_cnt[te_pkg::BRANCH_COUNT_LEN-1:0];
    ref_full    = calc_full(ref_cnt, flush_i);
    ref_empty   = (ref_cnt == 0);

    if (map_o !== ref_map) begin
      $error("[%0t] %s: MAP mismatch\n  dut=%b\n  ref=%b", $time, tag, map_o, ref_map);
      $fatal(1);
    end

    if (branches_o !== ref_cnt_slv) begin
      $error("[%0t] %s: COUNT mismatch dut=%0d ref=%0d", $time, tag, branches_o, ref_cnt);
      $fatal(1);
    end

    if (is_full_o !== ref_full) begin
      $error("[%0t] %s: FULL mismatch dut=%0b ref=%0b (ref_cnt=%0d)", $time, tag, is_full_o, ref_full, ref_cnt);
      $fatal(1);
    end

    if (is_empty_o !== ref_empty) begin
      $error("[%0t] %s: EMPTY mismatch dut=%0b ref=%0b (ref_cnt=%0d)", $time, tag, is_empty_o, ref_empty, ref_cnt);
      $fatal(1);
    end
  endtask

  // One reference-model step per clock (mirrors the DUT behavior as closely as possible)
  task automatic ref_step();
    int unsigned served;
    int unsigned to_serve;

    served   = 0;
    to_serve = status_q.size();

    // flush behavior in DUT: clears map and count, but DOES NOT clear status_left_q.
    if (flush_i) begin
      ref_cnt = 0;
      ref_map = '0;
    end

    // append branches from prev_valid/prev_taken (1-cycle delayed inputs)
    for (int i = 0; i < N; i++) begin
      if (prev_valid[i]) begin
        status_q.push_back(prev_taken[i]);
        to_serve++;
      end
    end

    // serve as many as possible into the 31-entry map
    while ((ref_cnt < 31) && (status_q.size() > 0)) begin
      bit taken_bit;
      taken_bit = status_q.pop_front();
      // spec encoding implemented by DUT: 0=taken, 1=not taken
      ref_map[ref_cnt] = ~taken_bit;
      ref_cnt++;
      served++;
    end

    // DUT has this extra special-case, but it effectively yields the same as above:
    // if (flush_i && |valid_q == '0) map/count reset again.
    if (flush_i && (prev_valid == '0)) begin
      ref_cnt = 0;
      ref_map = '0;
    end

    // if served==to_serve, valid_left_d becomes 0. Our queue is already empty then.
    // (no action needed)
  endtask

  // Drive one cycle (inputs stable before posedge)
  task automatic drive_cycle(input logic [N-1:0] v,
                             input logic [N-1:0] t,
                             input logic         fl,
                             input string        tag);
    valid_i        = v;
    branch_taken_i = t;
    flush_i        = fl;

    @(posedge clk_i);

    // First update ref-model using the *previous* cycle's inputs (prev_*)
    ref_step();

    // Then advance the 1-cycle input pipeline in the ref model
    prev_valid <= valid_i;
    prev_taken <= branch_taken_i;

    // allow combinational settle
    #1;
    check_outputs(tag);
  endtask

  // ----------------------------
  // Main test
  // ----------------------------
  initial begin
    // init
    valid_i        = '0;
    branch_taken_i = '0;
    flush_i        = 1'b0;

    ref_map   = '0;
    ref_cnt   = 0;
    status_q.delete();
    prev_valid = '0;
    prev_taken = '0;

    // reset
    rst_ni = 1'b0;
    repeat (3) @(posedge clk_i);
    rst_ni = 1'b1;

    // After reset (and a delta), expect empty
    #1;
    check_outputs("after_reset");

    // NOTE: because DUT uses registered valid_q/taken_q, the very first
    // non-zero valid_i will be *consumed* one cycle later.

    // 1) deterministic sanity sequence
    drive_cycle(4'b0000, 4'b0000, 1'b0, "no_branch_0");
    drive_cycle(4'b0001, 4'b0001, 1'b0, "one_branch_taken");
    drive_cycle(4'b1010, 4'b0110, 1'b0, "two_branches_sparse");
    drive_cycle(4'b1111, 4'b0101, 1'b0, "four_branches");

    // 2) Fill-to-full test (force full deterministically)
    // Keep sending 4 valid branches/cycle until ref_cnt reaches 31.
    while (ref_cnt < 31) begin
      drive_cycle(4'b1111, $urandom_range(0, (1<<N)-1), 1'b0, "fill_to_full");
    end

    // When full, DUT must hold branches_o at 31 and is_full_o asserted (unless flush_i)
    if (ref_cnt != 31) $fatal(1, "Internal TB error: expected ref_cnt==31");

    // 3) Overflow/buffering test: keep injecting while full; map/count must not change
    map_full_snapshot = ref_map;
    repeat (5) begin
      drive_cycle(4'b1111, $urandom_range(0, (1<<N)-1), 1'b0, "overflow_buffering");
      if (ref_cnt != 31) $fatal(1, "Expected ref_cnt to stay 31 while full");
      if (ref_map !== map_full_snapshot) $fatal(1, "Expected map to stay constant while full");
    end

    // 4) Flush behavior:
    // - clears map and count immediately in that cycle's comb.
    // - BUT buffered leftovers are NOT cleared, so after flush deasserts, they can refill the map.
    drive_cycle(4'b0000, 4'b0000, 1'b1, "flush_asserted");
    drive_cycle(4'b0000, 4'b0000, 1'b0, "flush_released");

    // 5) Random regression (includes occasional flush)
    for (int k = 0; k < 200; k++) begin
      logic [N-1:0] rv;
      logic [N-1:0] rt;
      logic         fl;

      rv = $urandom_range(0, (1<<N)-1);
      rt = $urandom_range(0, (1<<N)-1);
      // bias to have activity
      if (rv == '0) rv = 1 << $urandom_range(0, N-1);
      fl = ($urandom_range(0, 39) == 0); // ~2.5% flush

      drive_cycle(rv, rt, fl, "random");
    end

    $display("\n*** TB PASSED: te_branch_map functional checks OK ***\n");
    $finish;
  end

endmodule
