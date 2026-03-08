// =============================================================================
// tb_peek_by_id.sv — Test 8: peek_by_id
// =============================================================================

`include "../src/id_fifo.sv"

typedef struct {
  logic [15:0] value;
  logic [7:0]  tag;
} payload_t;

module tb_peek_by_id;

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

    $display("\n=== %m ===");

    // Test 8: peek_by_id
    fifo = new_fifo("t8_fifo");

    fifo.push(4'd6, make_payload(16'h0006, 8'h00));
    fifo.push(4'd7, make_payload(16'h0007, 8'h00));

    e = fifo.peek_by_id(4'd7);
    check("peek_by_id(7): id correct",   e.id == 4'd7);
    check("peek_by_id(7): data correct", e.data.value == 16'h0007);
    check("size unchanged after peek",   fifo.size() == 2);

    e = fifo.peek_by_id(4'd6);
    check("peek_by_id(6): id correct",   e.id == 4'd6);

    // --- Result summary (DO NOT MODIFY) ---
    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
