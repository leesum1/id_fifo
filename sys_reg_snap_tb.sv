// =============================================================================
// sys_reg_snap_tb.sv — Testbench for sys_reg_snap class
// =============================================================================

`include "sys_reg_snap.sv"

module sys_reg_snap_tb;

  localparam ID_WIDTH   = 4;   // 4-bit RID: MSB=wrap, bits[2:0]=value
  localparam REG_WIDTH  = 16;
  localparam ADDR_WIDTH = 4;

  typedef logic [ID_WIDTH-1:0]   rid_t;
  typedef logic [ADDR_WIDTH-1:0] addr_t;
  typedef logic [REG_WIDTH-1:0]  data_t;

  sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) snap;

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

  initial begin
    data_t val;
    sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH))::snap_queue_t snaps;

    snap = new("snap");
    snap.enable_log = 1;

    // ========================================================================
    $display("\n=== Test 1: miss (no history) ===");
    // ========================================================================
    check("miss on empty snap", snap.get_value_at(4'd3, 4'h1, val) == 0);
    check("snap is empty",      snap.empty());

    // ========================================================================
    $display("\n=== Test 2: motivating example — ADD + MSR ===");
    // ========================================================================
    // REG1 wire = 0x0014 (20).  MSR(rid=2) is about to write 10.
    // Record pre_value before MSR executes.
    snap.record_update(4'd2, 4'h1, 16'h0014);

    // ADD(rid=1): no MSR younger than rid=1 → miss → use wire (which is now 10)
    // But wait: with the new design, miss means "use current wire" — which for
    // instructions OLDER than all MSRs is WRONG unless we have the pre_value.
    // The hit case: rid=1 < rid=2, so rid=2 IS younger than rid=1 → hit, pre=0x14 ✓
    check("ADD(rid=1) hits, gets pre-MSR value", snap.get_value_at(4'd1, 4'h1, val));
    check("value is 0x0014 (20)",                val == 16'h0014);

    // rid=3 (after MSR): rid=2 is NOT younger than rid=3 → miss → wire correct
    check("rid=3 miss (use wire=10)", snap.get_value_at(4'd3, 4'h1, val) == 0);

    // rid=2 itself: rid=2 NOT younger than rid=2 → miss
    check("rid=2 miss (exact)",       snap.get_value_at(4'd2, 4'h1, val) == 0);

    // ========================================================================
    $display("\n=== Test 3: multiple MSRs to same register ===");
    // ========================================================================
    // State: REG1 pre-record at rid=2(pre=0x0014)
    // MSR(rid=4) executes next (in order). Wire is now 10 (0x000A).
    snap.record_update(4'd4, 4'h1, 16'h000A);

    // rid=1 should get oldest younger MSR → rid=2 (pre=0x0014)
    check("rid=1 gets oldest younger rid=2", snap.get_value_at(4'd1, 4'h1, val));
    check("value is 0x0014",                 val == 16'h0014);

    // rid=3: younger MSRs are rid=4 only (rid=2 is older) → pre of rid=4 = 0x000A
    check("rid=3 gets oldest younger rid=4", snap.get_value_at(4'd3, 4'h1, val));
    check("value is 0x000A",                 val == 16'h000A);

    // rid=5: no younger MSR → miss
    check("rid=5 miss",                      snap.get_value_at(4'd5, 4'h1, val) == 0);

    // ========================================================================
    $display("\n=== Test 4: multiple registers ===");
    // ========================================================================
    // REG2 wire = 0x0020.  MSR(rid=3) writes REG2.
    snap.record_update(4'd3, 4'h2, 16'h0020);

    // rid=1 for REG2: rid=3 younger → pre=0x0020
    check("rid=1 hits REG2",        snap.get_value_at(4'd1, 4'h2, val));
    check("REG2 pre=0x0020",        val == 16'h0020);

    // rid=5 for REG2: rid=3 not younger → miss
    check("rid=5 misses REG2",      snap.get_value_at(4'd5, 4'h2, val) == 0);

    // ========================================================================
    $display("\n=== Test 5: get_snapshot_at ===");
    // ========================================================================
    // Records: REG1@rid=2(pre=0x0014), REG1@rid=4(pre=0x000A), REG2@rid=3(pre=0x0020)

    // Snapshot at rid=1: younger MSRs are rid=2(REG1), rid=4(REG1), rid=3(REG2)
    //   REG1: oldest younger = rid=2 → 0x0014
    //   REG2: oldest younger = rid=3 → 0x0020
    snaps = snap.get_snapshot_at(4'd1);
    check("snapshot at rid=1: 2 regs", snaps.size() == 2);
    begin
      bit found_r1;
      bit found_r2;
      found_r1 = 0; found_r2 = 0;
      foreach (snaps[i]) begin
        if (snaps[i].reg_addr == 4'h1 && snaps[i].value == 16'h0014) found_r1 = 1;
        if (snaps[i].reg_addr == 4'h2 && snaps[i].value == 16'h0020) found_r2 = 1;
      end
      check("snapshot rid=1: REG1=0x0014", found_r1);
      check("snapshot rid=1: REG2=0x0020", found_r2);
    end

    // Snapshot at rid=3: younger MSRs are rid=4(REG1) only (rid=2,3 not younger)
    //   REG1: oldest younger = rid=4 → 0x000A
    //   REG2: no younger → omitted
    snaps = snap.get_snapshot_at(4'd3);
    check("snapshot at rid=3: 1 reg", snaps.size() == 1);
    check("snapshot rid=3: REG1=0x000A",
          snaps.size() == 1 && snaps[0].reg_addr == 4'h1 && snaps[0].value == 16'h000A);

    // Snapshot at rid=5: no younger MSRs → empty
    snaps = snap.get_snapshot_at(4'd5);
    check("snapshot at rid=5: 0 regs", snaps.size() == 0);

    // ========================================================================
    $display("\n=== Test 6: retire ===");
    // ========================================================================
    // retire(rid=3): removes rid=2(REG1), rid=3(REG2); keeps rid=4(REG1)
    snap.retire(4'd3);
    check("size=1 after retire(3)", snap.size() == 1);

    // rid=1 for REG1: only rid=4 remains; it is younger → pre=0x000A
    check("rid=1 now gets rid=4 pre", snap.get_value_at(4'd1, 4'h1, val));
    check("value=0x000A",             val == 16'h000A);

    // REG2 fully retired → miss
    check("REG2 miss after retire",   snap.get_value_at(4'd1, 4'h2, val) == 0);

    // rid=5 for REG1: rid=4 not younger → miss
    check("rid=5 miss REG1 after retire", snap.get_value_at(4'd5, 4'h1, val) == 0);

    // ========================================================================
    $display("\n=== Test 7: wrap-around RID ===");
    // ========================================================================
    begin
      sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) ws;
      ws = new("wrap_snap");
      ws.enable_log = 1;

      // ID_WIDTH=4: wrap at 0b1xxx.  Sequence: ...6,7,8(wrapped),9,...
      // is_younger(8,7)=true (8 wrapped, 7 not; val_8=0 < val_7=7)
      ws.record_update(4'd6, 4'h0, 16'hFF00); // REG0 pre before rid=6 writes
      ws.record_update(4'd8, 4'h0, 16'hFF06); // REG0 pre before rid=8 writes
      ws.record_update(4'd9, 4'h1, 16'hEE00); // REG1 pre before rid=9 writes

      // query rid=5: younger MSRs for REG0 are rid=6,8
      //   oldest among younger = rid=6 → pre=0xFF00
      check("wrap: rid=5 gets rid=6 pre=0xFF00", ws.get_value_at(4'd5, 4'h0, val));
      check("wrap: val=0xFF00",                  val == 16'hFF00);

      // query rid=7: younger MSRs for REG0 are rid=8 only (rid=6 not younger than 7)
      //   oldest = rid=8 → pre=0xFF06
      check("wrap: rid=7 gets rid=8 pre=0xFF06", ws.get_value_at(4'd7, 4'h0, val));
      check("wrap: val=0xFF06",                  val == 16'hFF06);

      // query rid=8: rid=8 NOT younger than itself → no younger MSR for REG0 → miss
      check("wrap: rid=8 miss REG0",             ws.get_value_at(4'd8, 4'h0, val) == 0);

      // query rid=7 for REG1: rid=9 is younger (wrapped) → pre=0xEE00
      check("wrap: rid=7 gets REG1 pre=0xEE00", ws.get_value_at(4'd7, 4'h1, val));
      check("wrap: REG1 val=0xEE00",             val == 16'hEE00);

      // snapshot at rid=7: REG0(rid=8)=0xFF06, REG1(rid=9)=0xEE00
      snaps = ws.get_snapshot_at(4'd7);
      check("wrap: snapshot at rid=7: 2 regs", snaps.size() == 2);
    end

    // ========================================================================
    $display("\n=== Test 8: same RID, different registers (legal) ===");
    // ========================================================================
    begin
      sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) mr;
      mr = new("multi_reg_snap");
      mr.enable_log = 1;

      // One MSR instruction writing two registers at rid=3 (legal)
      mr.record_update(4'd3, 4'h0, 16'h1000);
      mr.record_update(4'd3, 4'h1, 16'h2000);

      check("mr: rid=1 hits REG0 (younger rid=3)", mr.get_value_at(4'd1, 4'h0, val));
      check("mr: REG0 pre=0x1000",                 val == 16'h1000);
      check("mr: rid=1 hits REG1 (younger rid=3)", mr.get_value_at(4'd1, 4'h1, val));
      check("mr: REG1 pre=0x2000",                 val == 16'h2000);

      // rid=3 itself: no younger MSR → miss
      check("mr: rid=3 miss REG0",  mr.get_value_at(4'd3, 4'h0, val) == 0);

      snaps = mr.get_snapshot_at(4'd1);
      check("mr: snapshot at rid=1 has 2 regs", snaps.size() == 2);
    end

    // ========================================================================
    $display("\n=== Test 9: dump (visual check) ===");
    // ========================================================================
    snap.dump();

    // ========================================================================
    // Summary
    // ========================================================================
    $display("\n============================================");
    $display("  PASSED: %0d / %0d", pass_cnt, pass_cnt + fail_cnt);
    if (fail_cnt > 0)
      $display("  FAILED: %0d", fail_cnt);
    else
      $display("  ALL TESTS PASSED");
    $display("============================================\n");

    $finish;
  end

endmodule
