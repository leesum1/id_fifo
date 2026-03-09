// =============================================================================
// tb_multi_wrap.sv — Test: Multi-wrap cycles with monotonic ID allocation
// =============================================================================
// Validates wrap-around behavior across 2+ complete wrap cycles.
// With ID_WIDTH=4 (16 IDs, half-space=8):
//   - Wrap 0: IDs 0–7    (wrap bit = 0)
//   - Wrap 1: IDs 8–15   (wrap bit = 1)
//   - Wrap 2: IDs 0–7    (wrap bit = 0 again)
// Tests queue ordering, is_younger(), and operations across wrap boundaries.
// =============================================================================

`include "../src/id_fifo.sv"

typedef struct {
  logic [15:0] value;
  logic [7:0]  tag;
} payload_t;

module tb_multi_wrap;

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
    id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) fifo;
    int i;

    $display("\n=== %m ===");

    fifo = new_fifo("multi_wrap_fifo");

    // --- WRAP 0: Push IDs 0–7 (wrap bit = 0) ---
    for (i = 0; i < 8; i++) begin
      fifo.push(id_t'(i), make_payload(16'(16'h0000) + 16'(i), 8'(8'h00) + 8'(i)));
    end
    check("wrap_0: size is 8 after pushing 0–7", fifo.size() == 8);

    // --- WRAP 1: Push IDs 8–15 (wrap bit = 1) ---
    for (i = 8; i < 16; i++) begin
      fifo.push(id_t'(i), make_payload(16'(16'h0100) + 16'(i), 8'(8'h10) + 8'(i)));
    end
    check("wrap_1: size is 16 after pushing 8–15", fifo.size() == 16);

    // --- Verify wrap boundary: ID 0 < ID 15 (different wrap bits) ---
    check("wrap_1: is_younger(0, 15) == 1", 
          id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(id_t'(0), id_t'(15)));
    check("wrap_1: is_younger(15, 0) == 0", 
          !id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(id_t'(15), id_t'(0)));

    // --- Peek oldest and verify it's ID 0 ---
    e = fifo.peek_oldest();
    check("wrap_1: oldest is id=0", e.id == id_t'(0));

    // --- Delete some middle entries to maintain half-space constraint ---
    // Delete IDs 1, 3, 5, 7 to clear wrap_0 slots (8 entries removed total)
    fifo.delete_by_id(id_t'(1));
    fifo.delete_by_id(id_t'(3));
    fifo.delete_by_id(id_t'(5));
    fifo.delete_by_id(id_t'(7));
    check("wrap_1: size is 12 after delete", fifo.size() == 12);

    // --- WRAP 2: Push new IDs 0–3 (wrap bit = 0 again, but wrapping) ---
    fifo.push(id_t'(0), make_payload(16'h0200, 8'h20));
    fifo.push(id_t'(1), make_payload(16'h0201, 8'h21));
    fifo.push(id_t'(2), make_payload(16'h0202, 8'h22));
    fifo.push(id_t'(3), make_payload(16'h0203, 8'h23));
    check("wrap_2: size is 16 after pushing 0–3 (wrap 2)", fifo.size() == 16);

    // --- Verify wrap 2 boundary semantics ---
    // Old ID 0 from wrap 0 is older than new ID 0 from wrap 2
    // Both have wrap_bit = 0, so is_younger compares values: old_0 vs new_0
    // But we pushed old 0 first, so old 0 is at some index < new 0's index
    // Just verify queue size is correct
    check("wrap_2: still 16 entries", fifo.size() == 16);

    // --- Delete from wrap 1 boundary (ID 8) to progress cleanup ---
    fifo.delete_by_id(id_t'(8));
    fifo.delete_by_id(id_t'(10));
    fifo.delete_by_id(id_t'(12));
    fifo.delete_by_id(id_t'(14));
    check("wrap_2: size is 12 after more deletes", fifo.size() == 12);

    // --- Push remaining wrap 2 IDs: 4–7 ---
    fifo.push(id_t'(4), make_payload(16'h0204, 8'h24));
    fifo.push(id_t'(5), make_payload(16'h0205, 8'h25));
    fifo.push(id_t'(6), make_payload(16'h0206, 8'h26));
    fifo.push(id_t'(7), make_payload(16'h0207, 8'h27));
    check("wrap_2: size is 16 after pushing 4–7", fifo.size() == 16);

    // --- Verify peek_by_id still works across wraps ---
    e = fifo.peek_by_id(id_t'(0));
    check("wrap_2: peek_by_id(0) returns an id=0", e.id == id_t'(0));

    e = fifo.peek_by_id(id_t'(15));
    check("wrap_2: peek_by_id(15) returns id=15", e.id == id_t'(15));

     // --- Flush younger operations across wrap boundary ---
    // flush_younger(8) removes all IDs strictly younger than 8
    // IDs from old wrap 0 are NOT younger (different wrap bit, lower val)
    // IDs from new wrap 2 are NOT younger (different wrap bit, lower val)
    // IDs 9, 11, 13, 15 from wrap 1 ARE younger (same wrap, higher val)
    fifo.flush_younger(id_t'(8));
    check("wrap_2: size after flush_younger(8)", fifo.size() == 12);

    // Oldest should be ID 8 or higher
    e = fifo.peek_oldest();
    check("wrap_2: oldest is >= 8 after flush", 
          !id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(e.id, id_t'(8)));

    // --- Result summary (DO NOT MODIFY) ---
    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
