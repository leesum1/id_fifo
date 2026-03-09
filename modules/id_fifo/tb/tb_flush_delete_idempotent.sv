// =============================================================================
// tb_flush_delete_idempotent.sv — Test: Idempotence of repeated flush/delete
// =============================================================================
// Proves that repeated calls to delete_by_id() and flush_*() preserve queue
// state when:
//   1. Deleting a non-existent ID (safe no-op)
//   2. Flushing an empty queue (safe no-op)
//   3. Flushing with same boundary ID repeatedly (no additional removals)
// Tests both empty-state and populated-state scenarios.
// =============================================================================

`include "../src/id_fifo.sv"

typedef struct {
  logic [15:0] value;
  logic [7:0]  tag;
} payload_t;

module tb_flush_delete_idempotent;

  localparam ID_WIDTH = 4;
  typedef logic [ID_WIDTH-1:0] id_t;

  int pass_cnt = 0;
  int fail_cnt = 0;

  function void check(string name, bit condition);
    if (condition) begin
      $display("  [PASS] %s", name);
      pass_cnt++;
    end else begin
      $display("  [FAIL] %s", name);
      fail_cnt++;
    end
  endfunction

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


  initial begin
    id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::entry_t e;
    id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::entry_t baseline_oldest_1;
    id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) fifo1, fifo2, fifo3, fifo4, fifo5;
    int baseline_size_1;
    int size_after_delete;
    int size_after_flush_eq;
    int size_after_first_flush;

    $display("\n=== %m ===");

    // =========================================================================
    // Scenario 1: Delete non-existent ID is idempotent
    // =========================================================================
    $display("\n[Scenario 1: Delete non-existent ID]");
    fifo1 = new_fifo("scen1_fifo1");
    fifo1.push(id_t'(2), make_payload(16'hAAAA, 8'hAA));
    fifo1.push(id_t'(5), make_payload(16'hBBBB, 8'hBB));

    // Store baseline state
    baseline_size_1 = fifo1.size();
    baseline_oldest_1 = fifo1.peek_oldest();

    // Try to delete non-existent IDs repeatedly
    fifo1.delete_by_id(id_t'(0));
    check("scen1: size unchanged after delete non-existent (attempt 1)", fifo1.size() == baseline_size_1);
    e = fifo1.peek_oldest();
    check("scen1: oldest unchanged after delete non-existent (attempt 1)", e.id == baseline_oldest_1.id);

    fifo1.delete_by_id(id_t'(0));
    check("scen1: size unchanged after delete non-existent (attempt 2)", fifo1.size() == baseline_size_1);
    e = fifo1.peek_oldest();
    check("scen1: oldest unchanged after delete non-existent (attempt 2)", e.id == baseline_oldest_1.id);

    fifo1.delete_by_id(id_t'(15));
    check("scen1: size unchanged after delete non-existent (attempt 3)", fifo1.size() == baseline_size_1);
    e = fifo1.peek_oldest();
    check("scen1: oldest unchanged after delete non-existent (attempt 3)", e.id == baseline_oldest_1.id);

    // =========================================================================
    // Scenario 2: Flush empty queue is idempotent
    // =========================================================================
    $display("\n[Scenario 2: Flush empty queue]");
    fifo2 = new_fifo("scen2_fifo");

    // Flush empty queue once
    fifo2.flush_younger(id_t'(5));
    check("scen2: size is 0 after flush_younger on empty", fifo2.size() == 0);

    // Flush empty queue again
    fifo2.flush_younger(id_t'(3));
    check("scen2: size still 0 after flush_younger again", fifo2.size() == 0);

    // Flush_younger_or_eq on empty queue
    fifo2.flush_younger_or_eq(id_t'(7));
    check("scen2: size still 0 after flush_younger_or_eq on empty", fifo2.size() == 0);

     // =========================================================================
    // Scenario 3: Repeated flush with same boundary ID
    // =========================================================================
    $display("\n[Scenario 3: Repeated flush with same boundary]");
    fifo3 = new_fifo("scen3_fifo");
    fifo3.push(id_t'(1), make_payload(16'h1111, 8'h11));
    fifo3.push(id_t'(3), make_payload(16'h3333, 8'h33));
    fifo3.push(id_t'(5), make_payload(16'h5555, 8'h55));
    fifo3.push(id_t'(7), make_payload(16'h7777, 8'h77));

    // First flush_younger(4) removes IDs 5 and 7 (is_younger = 5>4, 7>4 in same wrap)
    // Keeps IDs 1 and 3 (is_younger = 1>4? no, 3>4? no)
    fifo3.flush_younger(id_t'(4));
    size_after_first_flush = fifo3.size();
    check("scen3: size reduced after flush_younger(4)", size_after_first_flush == 2);

    // Second flush_younger(4) on same state: no more removals
    fifo3.flush_younger(id_t'(4));
    check("scen3: size unchanged after second flush_younger(4)", fifo3.size() == size_after_first_flush);

    // Third flush_younger(4): still no change
    fifo3.flush_younger(id_t'(4));
    check("scen3: size unchanged after third flush_younger(4)", fifo3.size() == size_after_first_flush);

    // Verify oldest is now ID 1
    e = fifo3.peek_oldest();
    check("scen3: oldest is id=1 after flushes", e.id == id_t'(1));

    // =========================================================================
    // Scenario 4: Delete existing ID is idempotent when ID no longer exists
    // =========================================================================
    $display("\n[Scenario 4: Delete existing then repeat]");
    fifo4 = new_fifo("scen4_fifo");
    fifo4.push(id_t'(2), make_payload(16'h2222, 8'h22));
    fifo4.push(id_t'(4), make_payload(16'h4444, 8'h44));
    fifo4.push(id_t'(6), make_payload(16'h6666, 8'h66));

    // Delete ID 4
    fifo4.delete_by_id(id_t'(4));
    size_after_delete = fifo4.size();
    check("scen4: size is 2 after deleting id=4", size_after_delete == 2);

    // Try to delete ID 4 again (doesn't exist)
    fifo4.delete_by_id(id_t'(4));
    check("scen4: size unchanged when delete non-existent id=4", fifo4.size() == size_after_delete);

    // Try again
    fifo4.delete_by_id(id_t'(4));
    check("scen4: size unchanged on third delete of non-existent id=4", fifo4.size() == size_after_delete);

    // =========================================================================
    // Scenario 5: Flush_younger_or_eq repeated on populated queue
    // =========================================================================
    $display("\n[Scenario 5: flush_younger_or_eq repeated]");
    fifo5 = new_fifo("scen5_fifo");
    fifo5.push(id_t'(1), make_payload(16'h1111, 8'h11));
    fifo5.push(id_t'(3), make_payload(16'h3333, 8'h33));
    fifo5.push(id_t'(5), make_payload(16'h5555, 8'h55));
    fifo5.push(id_t'(7), make_payload(16'h7777, 8'h77));

    // flush_younger_or_eq(3) removes IDs where is_younger(id, 3) OR id == 3
    // is_younger(1, 3) = (1 > 3? no) = false, but 1 != 3, so keep
    // is_younger(3, 3) = false, but 3 == 3, so remove
    // is_younger(5, 3) = (5 > 3? yes) = true, so remove
    // is_younger(7, 3) = (7 > 3? yes) = true, so remove
    // Remaining: ID 1 (size = 1)
    fifo5.flush_younger_or_eq(id_t'(3));
    size_after_flush_eq = fifo5.size();
    check("scen5: size is 1 after flush_younger_or_eq(3)", size_after_flush_eq == 1);

    // Second flush with same boundary: no change
    fifo5.flush_younger_or_eq(id_t'(3));
    check("scen5: size unchanged on second flush_younger_or_eq(3)", fifo5.size() == size_after_flush_eq);

    // Third: still no change
    fifo5.flush_younger_or_eq(id_t'(3));
    check("scen5: size unchanged on third flush_younger_or_eq(3)", fifo5.size() == size_after_flush_eq);

    e = fifo5.peek_oldest();
    check("scen5: oldest is id=1", e.id == id_t'(1));

    // --- Result summary (DO NOT MODIFY) ---
    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
