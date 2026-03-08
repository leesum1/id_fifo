// =============================================================================
// tb_wrap_boundary_flush.sv — Test 13: wrap boundary flush_younger_or_eq(15)
// =============================================================================

`include "../src/id_fifo.sv"

typedef struct {
  logic [15:0] value;
  logic [7:0]  tag;
} payload_t;

module tb_wrap_boundary_flush;

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

    // Test 13: wrap boundary flush_younger_or_eq(15)
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

    // --- Result summary (DO NOT MODIFY) ---
    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
