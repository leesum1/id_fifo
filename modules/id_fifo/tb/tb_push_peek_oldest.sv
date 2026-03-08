// =============================================================================
// tb_push_peek_oldest.sv — Test 3: push & peek_oldest
// =============================================================================

`include "../src/id_fifo.sv"

typedef struct {
  logic [15:0] value;
  logic [7:0]  tag;
} payload_t;

module tb_push_peek_oldest;

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

    // Test 3: push & peek_oldest
    fifo = new_fifo("t3_fifo");

    fifo.push(4'd2, make_payload(16'hAAAA, 8'h01));
    fifo.push(4'd5, make_payload(16'hBBBB, 8'h02));
    fifo.push(4'd3, make_payload(16'hCCCC, 8'h03));
    check("size is 3", fifo.size() == 3);
    check("not empty",  !fifo.empty());

    e = fifo.peek_oldest();
    check("peek_oldest returns id=2", e.id == 4'd2);
    check("peek_oldest data correct",  e.data.value == 16'hAAAA);

    // --- Result summary (DO NOT MODIFY) ---
    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
