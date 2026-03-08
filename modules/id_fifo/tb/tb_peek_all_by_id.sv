// =============================================================================
// tb_peek_all_by_id.sv — Test 10: peek_all_by_id with allow_dup
// =============================================================================

`include "../src/id_fifo.sv"

typedef struct {
  logic [15:0] value;
  logic [7:0]  tag;
} payload_t;

module tb_peek_all_by_id;

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
    id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) dup_fifo;
    id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::entry_queue_t all;

    $display("\n=== %m ===");

    // Test 10: peek_all_by_id with allow_dup
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

    // --- Result summary (DO NOT MODIFY) ---
    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
