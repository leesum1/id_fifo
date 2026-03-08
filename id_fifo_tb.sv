// =============================================================================
// id_fifo_tb.sv — Testbench for id_fifo class
// =============================================================================

`include "id_fifo.sv"

// Simple payload type for testing
typedef struct {
  logic [15:0] value;
  logic [7:0]  tag;
} payload_t;

module id_fifo_tb;

  // Use 4-bit ID (bit 3 = wrap bit, bits [2:0] = value → range 0-15)
  localparam ID_WIDTH = 4;

  typedef logic [ID_WIDTH-1:0] id_t;

  int pass_cnt = 0;
  int fail_cnt = 0;

  // --------------------------------------------------------------------------
  // Helper: check and report
  // --------------------------------------------------------------------------
  function void check(string name, bit condition);
    if (condition) begin
      $display("  [PASS] %s", name);
      pass_cnt++;
    end else begin
      $display("  [FAIL] %s", name);
      fail_cnt++;
    end
  endfunction

  // --------------------------------------------------------------------------
  // Helper: build payload
  // --------------------------------------------------------------------------
  function payload_t make_payload(logic [15:0] v, logic [7:0] t);
    payload_t p;
    p.value = v;
    p.tag   = t;
    return p;
  endfunction

  function automatic id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) new_fifo(string inst_name, bit allow_dup = 0);
    id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) f;
    f = new(inst_name);
    f.enable_log = 1;
    f.allow_dup  = allow_dup;
    return f;
  endfunction

  // --------------------------------------------------------------------------
  // Main test
  // --------------------------------------------------------------------------
  initial begin
    id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::entry_t e;

    // ========================================================================
    $display("\n=== Test 1: is_younger — same wrap bit ===");
    // ========================================================================
    check("3 is younger than 2 (same wrap)",  id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(4'd3, 4'd2));
    check("2 is NOT younger than 3",         !id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(4'd2, 4'd3));
    check("5 is NOT younger than 5 (equal)", !id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(4'd5, 4'd5));

    // ========================================================================
    $display("\n=== Test 2: is_younger — different wrap bit (wrap-around) ===");
    // ========================================================================
    // ID 4'b1_001 (9) vs 4'b0_110 (6): wrap bits differ, val 1 < 6 → 9 is younger
    check("9 (wrap=1,val=1) is younger than 6 (wrap=0,val=6)",
          id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(4'd9, 4'd6));
    // ID 4'b0_110 (6) vs 4'b1_001 (9): wrap bits differ, val 6 > 1 → 6 is NOT younger
    check("6 is NOT younger than 9",
         !id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(4'd6, 4'd9));
    // ID 4'b1_000 (8) vs 4'b0_111 (7): wrap bits differ, val 0 < 7 → 8 is younger
    check("8 (just wrapped) is younger than 7",
          id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(4'd8, 4'd7));

    // ========================================================================
    $display("\n=== Test 3: push & peek_oldest ===");
    // ========================================================================
    begin
      id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) fifo;
      fifo = new_fifo("t3_fifo");

      fifo.push(4'd2, make_payload(16'hAAAA, 8'h01));
      fifo.push(4'd5, make_payload(16'hBBBB, 8'h02));
      fifo.push(4'd3, make_payload(16'hCCCC, 8'h03));
      check("size is 3", fifo.size() == 3);
      check("not empty",  !fifo.empty());

      e = fifo.peek_oldest();
      check("peek_oldest returns id=2", e.id == 4'd2);
      check("peek_oldest data correct",  e.data.value == 16'hAAAA);
    end

    // ========================================================================
    $display("\n=== Test 4: delete_by_id ===");
    // ========================================================================
    begin
      id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) fifo;
      fifo = new_fifo("t4_fifo");

      fifo.push(4'd2, make_payload(16'hAAAA, 8'h01));
      fifo.push(4'd5, make_payload(16'hBBBB, 8'h02));
      fifo.push(4'd3, make_payload(16'hCCCC, 8'h03));

      fifo.delete_by_id(4'd2);
      check("size is 2 after delete", fifo.size() == 2);
      e = fifo.peek_oldest();
      check("oldest is now id=5", e.id == 4'd5);
    end

    // ========================================================================
    $display("\n=== Test 5: flush_younger ===");
    // ========================================================================
    begin
      id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) fifo;
      fifo = new_fifo("t5_fifo");

      // Current: [id=5, id=3].  5 is younger than 3 → flush_younger(3) removes id=5
      fifo.push(4'd5, make_payload(16'hBBBB, 8'h02));
      fifo.push(4'd3, make_payload(16'hCCCC, 8'h03));

      fifo.flush_younger(4'd3);
      check("size is 1 after flush_younger(3)", fifo.size() == 1);
      e = fifo.peek_oldest();
      check("remaining entry is id=3", e.id == 4'd3);
    end

    // ========================================================================
    $display("\n=== Test 6: wrap-around flush_younger ===");
    // ========================================================================
    begin
      id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) fifo;
      fifo = new_fifo("t6_fifo");

      // Push IDs across a wrap boundary: 6, 7, 8(=wrap), 9(=wrap)
      fifo.push(4'd6,  make_payload(16'h0006, 8'h00));
      fifo.push(4'd7,  make_payload(16'h0007, 8'h00));
      fifo.push(4'd8,  make_payload(16'h0008, 8'h00)); // 1_000 (wrapped)
      fifo.push(4'd9,  make_payload(16'h0009, 8'h00)); // 1_001 (wrapped)
      check("size is 4", fifo.size() == 4);

      // flush_younger(7): 8 and 9 are younger than 7 (wrap-around), should be flushed
      fifo.flush_younger(4'd7);
      check("after flush_younger(7): size=2", fifo.size() == 2);
      e = fifo.peek_oldest();
      check("oldest is id=6", e.id == 4'd6);
    end

    // ========================================================================
    $display("\n=== Test 7: dump (visual check) ===");
    // ========================================================================
    begin
      id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) fifo;
      fifo = new_fifo("t7_fifo");
      fifo.push(4'd6, make_payload(16'h0006, 8'h00));
      fifo.push(4'd7, make_payload(16'h0007, 8'h00));
      fifo.dump();
    end

    // ========================================================================
    $display("\n=== Test 8: peek_by_id ===");
    // ========================================================================
    begin
      id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) fifo;
      fifo = new_fifo("t8_fifo");

      fifo.push(4'd6, make_payload(16'h0006, 8'h00));
      fifo.push(4'd7, make_payload(16'h0007, 8'h00));

      e = fifo.peek_by_id(4'd7);
      check("peek_by_id(7): id correct",   e.id == 4'd7);
      check("peek_by_id(7): data correct", e.data.value == 16'h0007);
      check("size unchanged after peek",   fifo.size() == 2);

      e = fifo.peek_by_id(4'd6);
      check("peek_by_id(6): id correct",   e.id == 4'd6);
    end

    // ========================================================================
    $display("\n=== Test 9: allow_dup — push duplicate IDs ===");
    // ========================================================================
    begin
      id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) dup_fifo;
      dup_fifo = new_fifo("dup_fifo", 1'b1);

      dup_fifo.push(4'd3, make_payload(16'hAA01, 8'h10));
      dup_fifo.push(4'd5, make_payload(16'hBB02, 8'h20));
      dup_fifo.push(4'd3, make_payload(16'hCC03, 8'h30));
      dup_fifo.push(4'd7, make_payload(16'hDD04, 8'h40));
      dup_fifo.push(4'd3, make_payload(16'hEE05, 8'h50));
      check("dup_fifo size is 5", dup_fifo.size() == 5);

      e = dup_fifo.peek_oldest();
      check("oldest is first pushed id=3", e.id == 4'd3 && e.data.value == 16'hAA01);

      // delete_by_id removes ALL entries with id=3
      dup_fifo.delete_by_id(4'd3);
      check("size is 2 after deleting all id=3", dup_fifo.size() == 2);

      e = dup_fifo.peek_oldest();
      check("oldest is now id=5", e.id == 4'd5);

      // flush_younger also works with remaining entries
      dup_fifo.push(4'd3, make_payload(16'hFF06, 8'h60));
      dup_fifo.push(4'd3, make_payload(16'hFF07, 8'h70));
      check("size is 4 after re-adding dups", dup_fifo.size() == 4);

      // flush_younger(5): 7 is younger than 5 → removed; 3's are older → kept
      dup_fifo.flush_younger(4'd5);
      check("after flush_younger(5): size=3", dup_fifo.size() == 3);
    end

    // ========================================================================
    $display("\n=== Test 10: peek_all_by_id with allow_dup ===");
    // ========================================================================
    begin
      id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) dup_fifo;
      id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::entry_queue_t all;
      dup_fifo = new_fifo("t10_dup_fifo", 1'b1);

      // dup_fifo now holds [id=5, id=3, id=3]
      dup_fifo.push(4'd5, make_payload(16'hBB02, 8'h20));
      dup_fifo.push(4'd3, make_payload(16'hFF06, 8'h60));
      dup_fifo.push(4'd3, make_payload(16'hFF07, 8'h70));

      all = dup_fifo.peek_all_by_id(4'd3);
      check("peek_all_by_id(3): found 2 entries",      all.size() == 2);
      check("peek_all_by_id(3): first data=0xFF06",    all[0].data.value == 16'hFF06);
      check("peek_all_by_id(3): second data=0xFF07",   all[1].data.value == 16'hFF07);
      check("size unchanged after peek_all",           dup_fifo.size() == 3);

      all = dup_fifo.peek_all_by_id(4'd5);
      check("peek_all_by_id(5): found 1 entry",        all.size() == 1);
    end

    // ========================================================================
    $display("\n=== Test 11: flush_younger_or_eq ===");
    // ========================================================================
    begin
      id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) f;
      f = new_fifo("flush_eq_fifo");

      f.push(4'd2, make_payload(16'h0002, 8'h00));
      f.push(4'd3, make_payload(16'h0003, 8'h00));
      f.push(4'd5, make_payload(16'h0005, 8'h00));
      f.push(4'd7, make_payload(16'h0007, 8'h00));

      // flush_younger_or_eq(5): removes 5, 7 (younger); keeps 2, 3 (older)
      f.flush_younger_or_eq(4'd5);
      check("flush_younger_or_eq(5): size=2", f.size() == 2);
      e = f.peek_oldest();
      check("oldest is id=2", e.id == 4'd2);
      e = f.peek_by_id(4'd3);
      check("id=3 still present", e.id == 4'd3);

      // wrap-around: push IDs across boundary then flush_younger_or_eq(8)
      f.push(4'd8,  make_payload(16'h0008, 8'h00)); // 1_000 (wrapped)
      f.push(4'd9,  make_payload(16'h0009, 8'h00)); // 1_001 (wrapped)
      f.flush_younger_or_eq(4'd8);
      // 8 itself is removed; 9 is younger → removed; 2,3 remain
      check("after flush_younger_or_eq(8): size=2", f.size() == 2);
      e = f.peek_oldest();
      check("oldest still id=2", e.id == 4'd2);
    end

    // ========================================================================
    $display("\n=== Test 12: wrap boundary 15->0 is_younger ===");
    // ========================================================================
    check("0 is younger than 15 at wrap boundary",
          id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(4'd0, 4'd15));
    check("15 is NOT younger than 0 at wrap boundary",
         !id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(4'd15, 4'd0));

    // ========================================================================
    $display("\n=== Test 13: wrap boundary flush_younger_or_eq(15) ===");
    // ========================================================================
    begin
      id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) f;
      f = new_fifo("t13_wrap_fifo");

      // Sequence across boundary: 14, 15, 0, 1
      f.push(4'd14, make_payload(16'h000E, 8'h00));
      f.push(4'd15, make_payload(16'h000F, 8'h00));
      f.push(4'd0,  make_payload(16'h0000, 8'h00));
      f.push(4'd1,  make_payload(16'h0001, 8'h00));
      check("t13 size is 4", f.size() == 4);

      // <=15 should remove 15 itself and younger IDs 0/1; keep 14
      f.flush_younger_or_eq(4'd15);
      check("t13 size is 1 after flush", f.size() == 1);
      e = f.peek_oldest();
      check("t13 remaining id is 14", e.id == 4'd14);
    end

    // ========================================================================
    $display("\n=== Test 14: sort by age (oldest first) ===");
    // ========================================================================
    begin
      id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) f;
      f = new_fifo("t14_sort_fifo");

      // Intentionally shuffled across wrap boundary.
      // In this set {14,15,0,1}, oldest is 14.
      f.push(4'd0,  make_payload(16'h1000, 8'h00));
      f.push(4'd14, make_payload(16'h100E, 8'h00));
      f.push(4'd1,  make_payload(16'h1001, 8'h00));
      f.push(4'd15, make_payload(16'h100F, 8'h00));

      f.sort();

      e = f.peek_oldest();
      check("sort oldest is 14", e.id == 4'd14);
      f.delete_by_id(4'd14);
      e = f.peek_oldest();
      check("sort next is 15", e.id == 4'd15);
      f.delete_by_id(4'd15);
      e = f.peek_oldest();
      check("sort next is 0", e.id == 4'd0);
      f.delete_by_id(4'd0);
      e = f.peek_oldest();
      check("sort next is 1", e.id == 4'd1);
    end

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
