// =============================================================================
// tb_multi_wrap.sv — Test multi-wrap cycle correctness
// =============================================================================
// Tests that sys_reg_snap maintains correct query semantics across
// at least 2 complete wrap cycles using monotonic RID allocation.
// For ID_WIDTH=4: RIDs 0-7 (wrap 0), 8-15 (wrap 1), 0-7 (wrap 2).
//
// is_younger(a, b) returns true if a is younger (newer) than b:
// - Same wrap bit: younger has larger value
// - Different wrap bit: younger has smaller value (wrapped around)

`include "../src/sys_reg_snap.sv"

module tb_multi_wrap;

  localparam ID_WIDTH   = 4;
  localparam REG_WIDTH  = 16;
  localparam ADDR_WIDTH = 4;

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

  function automatic sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) new_snap(string inst_name);
    sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) s;
    s = new(inst_name);
    s.enable_log = 1;
    return s;
  endfunction

  initial begin
    data_t val;
    sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH))::snap_queue_t snaps;

    $display("\n=== Test: multi-wrap cycle correctness ===");

    begin
      sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) mw;
      mw = new_snap("multi_wrap");

      // ======================================================================
      // Wrap Cycle 0 (RIDs 0-7, wrap bit = 0)
      // ======================================================================
      // Record: REG0 pre-values as RID increases
      mw.record_update(4'd0, 4'h0, 16'h0000);
      mw.record_update(4'd2, 4'h0, 16'h0002);
      mw.record_update(4'd4, 4'h0, 16'h0004);
      mw.record_update(4'd6, 4'h0, 16'h0006);

      // Record: REG1 at different RIDs
      mw.record_update(4'd1, 4'h1, 16'h1001);
      mw.record_update(4'd5, 4'h1, 16'h1005);

      // Query within wrap 0: rid=3 for REG0
      // Younger records: rid=4(val>3), rid=6(val>3) all same wrap
      // Oldest younger: rid=4 → pre=0x0004
      check("wrap0: rid=3 REG0 gets rid=4 pre=0x0004", mw.get_value_at(4'd3, 4'h0, val));
      check("wrap0: val=0x0004",                         val == 16'h0004);

      // Query within wrap 0: rid=0 for REG1
      // Younger records: rid=1(val>0), rid=5(val>0) all same wrap
      // Oldest younger: rid=1 → pre=0x1001
      check("wrap0: rid=0 REG1 gets rid=1 pre=0x1001", mw.get_value_at(4'd0, 4'h1, val));
      check("wrap0: val=0x1001",                         val == 16'h1001);

      // ======================================================================
      // Wrap Cycle 1 (RIDs 8-15, wrap bit = 1)
      // ======================================================================
      // Add records in wrap 1 at same registers
      mw.record_update(4'd8, 4'h0, 16'h0008);
      mw.record_update(4'd10, 4'h0, 16'h000A);
      mw.record_update(4'd12, 4'h0, 16'h000C);

      // Add record at REG1 in wrap 1
      mw.record_update(4'd9, 4'h1, 16'h1009);

      // Query in wrap 0 towards wrap 1: rid=7 for REG0
      // Younger records: rid=8,10,12 (wrap=1, diff wrap, val<7) all younger
      // (wrap=0 records 0-6 are not younger than 7 same wrap)
      // Oldest younger: rid=8 → pre=0x0008
      check("wrap0->1: rid=7 REG0 gets rid=8 pre=0x0008", mw.get_value_at(4'd7, 4'h0, val));
      check("wrap0->1: val=0x0008",                        val == 16'h0008);

      // Query within wrap 1: rid=8 for REG0
      // Younger records for REG0 in wrap 1: rid=10,12 (same wrap)
      // Oldest younger: rid=10 → pre=0x000A
      check("wrap1: rid=8 REG0 gets rid=10 pre=0x000A", mw.get_value_at(4'd8, 4'h0, val));
      check("wrap1: val=0x000A",                         val == 16'h000A);

      // Query within wrap 1: rid=8 for REG1
      // Younger records for REG1 in wrap 1: rid=9 (same wrap)
      // Oldest younger: rid=9 → pre=0x1009
      check("wrap1: rid=8 REG1 gets rid=9 pre=0x1009", mw.get_value_at(4'd8, 4'h1, val));
      check("wrap1: val=0x1009",                        val == 16'h1009);

      // ======================================================================
      // Wrap Cycle 2 (RIDs 0-7 again, wrap bit = 0 after full wrap)
      // ======================================================================
      // Add records in wrap 2 (same RID range as wrap 0, but logically after wrap 1)
      mw.record_update(4'd0, 4'h2, 16'h2000);  // New register REG2, rid=0 in wrap 2
      mw.record_update(4'd3, 4'h1, 16'h1103);  // REG1, rid=3 in wrap 2
      mw.record_update(4'd7, 4'h0, 16'h0007);  // REG0, rid=7 in wrap 2

      // Query in wrap 2: rid=2 for REG0
      // Records for REG0: rid=0,2,4,6 (wrap0) + rid=8,10,12 (wrap1) + rid=7 (wrap2)
      // For query rid=2 (wrap=0):
      //   wrap0: rid=4,6 (val>2) younger, rid=0,2 (val<=2) not younger
      //   wrap1: rid=8,10,12 (diff wrap, val<2) younger
      // Oldest younger in program order: rid=4 → pre=0x0004
      check("wrap2: rid=2 REG0 gets rid=4 pre=0x0004", mw.get_value_at(4'd2, 4'h0, val));
      check("wrap2: val=0x0004",                        val == 16'h0004);

      // Query in wrap 2: rid=6 for REG0  
      // For query rid=6 (wrap=0):
      //   wrap0: rid=0,2,4 (val<6) not younger
      //   wrap1: rid=8,10,12 (diff wrap, val<6) younger
      //   wrap2: rid=7 (wrap=0, val>6) younger
      // Oldest younger: rid=8 → pre=0x0008
      check("wrap2: rid=6 REG0 gets rid=8 pre=0x0008", mw.get_value_at(4'd6, 4'h0, val));
      check("wrap2: val=0x0008",                        val == 16'h0008);

      // Query in wrap 2: rid=5 for REG1
      // Records for REG1: rid=1 (wrap0), rid=5 (wrap0), rid=9 (wrap1), rid=3 (wrap2)
      // For query rid=5 (wrap=0):
      //   wrap0: rid=1 (val<5) not younger, rid=5 (equal) not younger
      //   wrap1: rid=9 (diff wrap, val<5) younger
      //   wrap2: rid=3 (wrap=0, val<5) not younger
      // Oldest younger: rid=9 → pre=0x1009
      check("wrap2: rid=5 REG1 gets rid=9 pre=0x1009", mw.get_value_at(4'd5, 4'h1, val));
      check("wrap2: val=0x1009",                        val == 16'h1009);

      // Query REG2 in wrap 2: rid=1 for REG2
      // Records for REG2: rid=0 (wrap2, wrap=0)
      // Query rid=1 (wrap=0): rid=0 (val<1) not younger
      check("wrap2: rid=1 REG2 miss", mw.get_value_at(4'd1, 4'h2, val) == 0);

      // Snapshot at rid=7 in wrap 2 context:
      // REG0: younger than rid=7 (wrap=0) are rid=8,10,12 (wrap1, diff wrap)
      //       oldest: rid=8 → pre=0x0008
      // REG1: younger than rid=7 (wrap=0) are rid=9 (wrap1, diff wrap)
      //       oldest: rid=9 → pre=0x1009
      // REG2: rid=0 (wrap=0, val<7) not younger
      snaps = mw.get_snapshot_at(4'd7);
      check("wrap2: snapshot size at rid=7 is 2", snaps.size() == 2);

      // Final consistency check: size after all records
      check("multi_wrap: final size", mw.size() == 13);
    end

    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
