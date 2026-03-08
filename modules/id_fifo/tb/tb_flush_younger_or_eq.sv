// =============================================================================
// tb_flush_younger_or_eq.sv — Test 11: flush_younger_or_eq
// =============================================================================

`include "../src/id_fifo.sv"

typedef struct {
  logic [15:0] value;
  logic [7:0]  tag;
} payload_t;

module tb_flush_younger_or_eq;

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
    id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) f;

    $display("\n=== %m ===");

    // Test 11: flush_younger_or_eq
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

    // --- Result summary (DO NOT MODIFY) ---
    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
