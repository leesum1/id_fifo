// =============================================================================
// tb_sort_by_age.sv — Test 14: sort by age (oldest first)
// =============================================================================

`include "../src/id_fifo.sv"

typedef struct {
  logic [15:0] value;
  logic [7:0]  tag;
} payload_t;

module tb_sort_by_age;

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

    // Test 14: sort by age (oldest first)
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

    // --- Result summary (DO NOT MODIFY) ---
    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
