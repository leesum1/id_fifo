// =============================================================================
// tb_retire_idempotent.sv — Test retire idempotence
// =============================================================================
// Tests that repeated retire() calls on the same or already-retired frontier
// are safe and maintain stable state. Validates:
// 1. Retire same RID multiple times (idempotent)
// 2. Retire with frontier that's already been retired (no records to remove)
// 3. History depth remains constant after redundant operations
// 4. Remaining records are not corrupted

`include "../src/sys_reg_snap.sv"

module tb_retire_idempotent;

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

    $display("\n=== Test: retire idempotence ===");

    // ========================================================================
    // Scenario 1: Populated history, retire with same frontier repeatedly
    // ========================================================================
    begin
      sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) snap1;
      snap1 = new_snap("scenario1_populated");

      // Add 5 records across 2 registers
      snap1.record_update(4'd1, 4'h0, 16'h0001);
      snap1.record_update(4'd2, 4'h1, 16'h1002);
      snap1.record_update(4'd3, 4'h0, 16'h0003);
      snap1.record_update(4'd4, 4'h1, 16'h1004);
      snap1.record_update(4'd5, 4'h2, 16'h2005);

      check("scenario1: initial size = 5", snap1.size() == 5);

      // First retire(2): removes rid=1,2 → size should be 3
      snap1.retire(4'd2);
      check("scenario1: size after retire(2) = 3", snap1.size() == 3);

      // Verify remaining records are correct
      // After retire(2), remaining REG0: rid=3 (rid=0,2 removed)
      // Query rid=0 for REG0: rid=3 is younger → pre=0x0003
      check("scenario1: rid=0 REG0 gets rid=3 pre=0x0003", snap1.get_value_at(4'd0, 4'h0, val));
      check("scenario1: val = 0x0003",                      val == 16'h0003);
      check("scenario1: rid=0 REG1 gets rid=4 pre=0x1004", snap1.get_value_at(4'd0, 4'h1, val));
      check("scenario1: val = 0x1004",                      val == 16'h1004);

      // Second retire(2): idempotent operation, nothing to remove
      // Size should remain 3
      snap1.retire(4'd2);
      check("scenario1: size after 2nd retire(2) = 3 (unchanged)", snap1.size() == 3);

      // Verify surviving records are still intact and queryable
      check("scenario1: after idempotent retire, rid=3 REG0 still queryable", snap1.get_value_at(4'd2, 4'h0, val));
      check("scenario1: val = 0x0003",                                       val == 16'h0003);
      check("scenario1: after idempotent retire, rid=0 REG1 still queryable", snap1.get_value_at(4'd0, 4'h1, val));
      check("scenario1: val = 0x1004",                                       val == 16'h1004);

      // Third retire(2): again, idempotent
      snap1.retire(4'd2);
      check("scenario1: size after 3rd retire(2) = 3 (still stable)", snap1.size() == 3);

      // Query should still work
      check("scenario1: rid=1 REG2 gets rid=5 pre=0x2005", snap1.get_value_at(4'd1, 4'h2, val));
      check("scenario1: val = 0x2005",                      val == 16'h2005);
    end

    // ========================================================================
    // Scenario 2: Empty history (all records retired), retire frontier again
    // ========================================================================
    begin
      sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) snap2;
      snap2 = new_snap("scenario2_empty");

      // Add 3 records
      snap2.record_update(4'd1, 4'h0, 16'hAAAA);
      snap2.record_update(4'd2, 4'h1, 16'hBBBB);
      snap2.record_update(4'd3, 4'h0, 16'hCCCC);

      check("scenario2: initial size = 3", snap2.size() == 3);

      // Retire all: retire(3) removes rid=1,2,3
      snap2.retire(4'd3);
      check("scenario2: size after retire(3) = 0 (all retired)", snap2.size() == 0);

      // Now retire with same frontier on empty history
      // Second retire(3): should be safe, no-op
      snap2.retire(4'd3);
      check("scenario2: size after 2nd retire(3) = 0 (remains empty)", snap2.size() == 0);

      // Third retire(3): still safe
      snap2.retire(4'd3);
      check("scenario2: size after 3rd retire(3) = 0 (still empty)", snap2.size() == 0);

      // All queries should miss (no history)
      check("scenario2: REG0 miss on empty", snap2.get_value_at(4'd0, 4'h0, val) == 0);
      check("scenario2: REG1 miss on empty", snap2.get_value_at(4'd0, 4'h1, val) == 0);
    end

    // ========================================================================
    // Scenario 3: Partial retire, advance frontier, then retry old frontier
    // ========================================================================
    begin
      sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) snap3;
      snap3 = new_snap("scenario3_partial");

      // Add 6 records
      snap3.record_update(4'd1, 4'h0, 16'h0001);
      snap3.record_update(4'd2, 4'h1, 16'h1002);
      snap3.record_update(4'd3, 4'h0, 16'h0003);
      snap3.record_update(4'd4, 4'h1, 16'h1004);
      snap3.record_update(4'd5, 4'h0, 16'h0005);
      snap3.record_update(4'd6, 4'h2, 16'h2006);

      check("scenario3: initial size = 6", snap3.size() == 6);

      // Retire to frontier rid=2: removes rid=1,2 → size = 4
      snap3.retire(4'd2);
      check("scenario3: size after retire(2) = 4", snap3.size() == 4);

      // Now advance frontier to rid=4: removes rid=3,4 → size = 2
      snap3.retire(4'd4);
      check("scenario3: size after retire(4) = 2", snap3.size() == 2);

      // Retry old frontier retire(2): idempotent, should not affect size
      snap3.retire(4'd2);
      check("scenario3: size after retire(2) again = 2 (unchanged)", snap3.size() == 2);

      // Verify the 2 remaining records (rid=5,6) are intact
      check("scenario3: rid=3 REG0 gets rid=5 pre=0x0005", snap3.get_value_at(4'd3, 4'h0, val));
      check("scenario3: val = 0x0005",                      val == 16'h0005);
      check("scenario3: rid=3 REG2 gets rid=6 pre=0x2006", snap3.get_value_at(4'd3, 4'h2, val));
      check("scenario3: val = 0x2006",                      val == 16'h2006);

      // Retire to old frontier again
      snap3.retire(4'd4);
      check("scenario3: size after retire(4) again = 2 (unchanged)", snap3.size() == 2);

      // Verify same records still queryable
      check("scenario3: after retry retire(4), rid=4 REG0 still gets rid=5 pre=0x0005", snap3.get_value_at(4'd4, 4'h0, val));
      check("scenario3: val = 0x0005", val == 16'h0005);
    end

    // ========================================================================
    // Scenario 4: Multiple consecutive retires on advancing frontier
    // ========================================================================
    begin
      sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) snap4;
      snap4 = new_snap("scenario4_advancing");

      // Add 8 records
      snap4.record_update(4'd0, 4'h0, 16'h0000);
      snap4.record_update(4'd1, 4'h1, 16'h1001);
      snap4.record_update(4'd2, 4'h0, 16'h0002);
      snap4.record_update(4'd3, 4'h1, 16'h1003);
      snap4.record_update(4'd4, 4'h0, 16'h0004);
      snap4.record_update(4'd5, 4'h1, 16'h1005);
      snap4.record_update(4'd6, 4'h0, 16'h0006);
      snap4.record_update(4'd7, 4'h1, 16'h1007);

      check("scenario4: initial size = 8", snap4.size() == 8);

      // Retire to rid=1 → removes rid=0,1 → size = 6
      snap4.retire(4'd1);
      check("scenario4: size after retire(1) = 6", snap4.size() == 6);

      // Retry retire(1) → idempotent, size = 6
      snap4.retire(4'd1);
      check("scenario4: size after 2nd retire(1) = 6", snap4.size() == 6);

      // Retire to rid=3 → removes rid=2,3 → size = 4
      snap4.retire(4'd3);
      check("scenario4: size after retire(3) = 4", snap4.size() == 4);

      // Retry retire(1) → idempotent on older frontier, size = 4
      snap4.retire(4'd1);
      check("scenario4: size after retry retire(1) = 4 (unchanged)", snap4.size() == 4);

      // Retry retire(3) → idempotent on current frontier, size = 4
      snap4.retire(4'd3);
      check("scenario4: size after retry retire(3) = 4 (unchanged)", snap4.size() == 4);

      // Remaining records: rid=4,5,6,7 should all be queryable
      check("scenario4: rid=2 REG0 gets rid=4 pre=0x0004", snap4.get_value_at(4'd2, 4'h0, val));
      check("scenario4: val = 0x0004",                      val == 16'h0004);
      check("scenario4: rid=2 REG1 gets rid=5 pre=0x1005", snap4.get_value_at(4'd2, 4'h1, val));
      check("scenario4: val = 0x1005",                      val == 16'h1005);
    end

    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
