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

  id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) fifo;

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

  // --------------------------------------------------------------------------
  // Main test
  // --------------------------------------------------------------------------
  initial begin
    id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::entry_t e;

    fifo = new("main_fifo");
    fifo.enable_log = 1;

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
    fifo.push(4'd2, make_payload(16'hAAAA, 8'h01));
    fifo.push(4'd5, make_payload(16'hBBBB, 8'h02));
    fifo.push(4'd3, make_payload(16'hCCCC, 8'h03));
    check("size is 3", fifo.size() == 3);
    check("not empty",  !fifo.empty());

    e = fifo.peek_oldest();
    check("peek_oldest returns id=2", e.id == 4'd2);
    check("peek_oldest data correct",  e.data.value == 16'hAAAA);

    // ========================================================================
    $display("\n=== Test 4: delete_by_id ===");
    // ========================================================================
    fifo.delete_by_id(4'd2);
    check("size is 2 after delete", fifo.size() == 2);
    e = fifo.peek_oldest();
    check("oldest is now id=5", e.id == 4'd5);

    // ========================================================================
    $display("\n=== Test 5: flush_younger ===");
    // ========================================================================
    // Current: [id=5, id=3].  5 is younger than 3 → flush_younger(3) removes id=5
    fifo.flush_younger(4'd3);
    check("size is 1 after flush_younger(3)", fifo.size() == 1);
    e = fifo.peek_oldest();
    check("remaining entry is id=3", e.id == 4'd3);

    // ========================================================================
    $display("\n=== Test 6: wrap-around flush_younger ===");
    // ========================================================================
    fifo.delete_by_id(4'd3); // clear
    check("empty after clearing", fifo.empty());

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

    // ========================================================================
    $display("\n=== Test 7: dump (visual check) ===");
    // ========================================================================
    fifo.dump();

    // ========================================================================
    $display("\n=== Test 8: peek_by_id ===");
    // ========================================================================
    // fifo currently holds [id=6, id=7]
    e = fifo.peek_by_id(4'd7);
    check("peek_by_id(7): id correct",   e.id == 4'd7);
    check("peek_by_id(7): data correct", e.data.value == 16'h0007);
    check("size unchanged after peek",   fifo.size() == 2);

    e = fifo.peek_by_id(4'd6);
    check("peek_by_id(6): id correct",   e.id == 4'd6);

    // ========================================================================
    $display("\n=== Test 9: allow_dup — push duplicate IDs ===");
    // ========================================================================
    begin
      id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) dup_fifo;
      dup_fifo = new("dup_fifo");
      dup_fifo.enable_log = 1;
      dup_fifo.allow_dup  = 1;

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

      // ======================================================================
      $display("\n=== Test 10: peek_all_by_id with allow_dup ===");
      // ======================================================================
      // dup_fifo now holds [id=5, id=3, id=3]
      begin
        id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::entry_queue_t all;

        all = dup_fifo.peek_all_by_id(4'd3);
        check("peek_all_by_id(3): found 2 entries",      all.size() == 2);
        check("peek_all_by_id(3): first data=0xFF06",    all[0].data.value == 16'hFF06);
        check("peek_all_by_id(3): second data=0xFF07",   all[1].data.value == 16'hFF07);
        check("size unchanged after peek_all",           dup_fifo.size() == 3);

        all = dup_fifo.peek_all_by_id(4'd5);
        check("peek_all_by_id(5): found 1 entry",        all.size() == 1);
      end
    end

    // ========================================================================
    // Summary
    // ========================================================================
    $display("\n=== Test 11: flush_younger_or_eq ===");
    // ========================================================================
    begin
      id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) f;
      f = new("flush_eq_fifo");
      f.enable_log = 1;

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
