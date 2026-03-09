// =============================================================================
// tb_stats.sv — Test: operation counters (record, retire, queries, snapshots)
// =============================================================================

`include "../src/sys_reg_snap.sv"

module tb_stats;

  localparam ID_WIDTH   = 6;
  localparam REG_WIDTH  = 32;
  localparam ADDR_WIDTH = 8;

  typedef logic [ID_WIDTH-1:0]   rid_t;
  typedef logic [ADDR_WIDTH-1:0] addr_t;
  typedef logic [REG_WIDTH-1:0]  data_t;

  int pass_cnt = 0;
  int fail_cnt = 0;

  function void check(string test_name, bit condition);
    if (condition) begin
      $display("  [PASS] %s", test_name);
      pass_cnt++;
    end else begin
      $display("  [FAIL] %s", test_name);
      fail_cnt++;
    end
  endfunction

  /* verilator lint_off UNUSEDSIGNAL */
  /* verilator lint_off IGNOREDRETURN */
  initial begin
    data_t val;
    sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) snap;
    bit hit;
    bit miss;

    $display("\n=== %m ===");

    snap = new("test_snap");
    snap.enable_log = 0;

    // --- Test 1: record_update counter ---
    // Perform 3 record_update calls; stat_record_cnt should be 3
    snap.record_update(6'd10, 8'h00, 32'hAAAAAAAA);
    snap.record_update(6'd11, 8'h04, 32'hBBBBBBBB);
    snap.record_update(6'd12, 8'h08, 32'hCCCCCCCC);

    check("stat_record_cnt == 3 after 3 updates", snap.stat_record_cnt == 3);

    // --- Test 2: get_value_at hit counter ---
    // Query for rid=5 with reg=8'h00: should hit (rid=10 is younger)
    hit = snap.get_value_at(6'd5, 8'h00, val);
    check("get_value_at hit for younger RID", hit == 1);
    check("stat_query_hit_cnt == 1 after hit", snap.stat_query_hit_cnt == 1);

    // --- Test 3: get_value_at miss counter ---
    // Query for rid=15 with reg=8'h00: should miss (no record younger than rid=15)
    miss = snap.get_value_at(6'd15, 8'h00, val);
    check("get_value_at miss for older records", miss == 0);
    check("stat_query_miss_cnt == 1 after miss", snap.stat_query_miss_cnt == 1);

    // --- Test 4: stat_peak_size counter ---
    // After 3 records, peak should be at least 3
    check("stat_peak_size >= 3 after 3 updates", snap.stat_peak_size >= 3);

    // --- Test 5: get_snapshot_at counter ---
    // Call get_snapshot_at to test counter
    snap.get_snapshot_at(6'd8);
    check("stat_snapshot_cnt == 1 after snapshot", snap.stat_snapshot_cnt == 1);

    // --- Test 6: retire counter ---
    // Call retire to increment counter
    snap.retire(6'd10);
    check("stat_retire_cnt == 1 after retire", snap.stat_retire_cnt == 1);

    // --- Test 7: hit and miss with multiple queries ---
    snap.record_update(6'd20, 8'h10, 32'hDDDDDDDD);
    snap.get_value_at(6'd15, 8'h10, val);  // hit (rid=20 is younger)
    snap.get_value_at(6'd25, 8'h10, val);  // miss (rid=20 not younger)
    check("stat_query_hit_cnt == 2 after 2 hits", snap.stat_query_hit_cnt == 2);
    check("stat_query_miss_cnt == 2 after 2 misses", snap.stat_query_miss_cnt == 2);

    // --- Test 8: dump contains all stat labels ---
    snap.dump();

    // --- Result summary (DO NOT MODIFY) ---
    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end
  /* verilator lint_on UNUSEDSIGNAL */
  /* verilator lint_on IGNOREDRETURN */

endmodule
