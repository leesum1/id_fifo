// =============================================================================
// tb_flush_younger.sv — Test 5: flush_younger
// =============================================================================

`include "../src/id_fifo.sv"

typedef struct {
  logic [15:0] value;
  logic [7:0]  tag;
} payload_t;

module tb_flush_younger;

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

    // Test 5: flush_younger
    fifo = new_fifo("t5_fifo");

    // Current: [id=5, id=3].  5 is younger than 3 → flush_younger(3) removes id=5
    fifo.push(4'd5, make_payload(16'hBBBB, 8'h02));
    fifo.push(4'd3, make_payload(16'hCCCC, 8'h03));

    fifo.flush_younger(4'd3);
    check("size is 1 after flush_younger(3)", fifo.size() == 1);
    e = fifo.peek_oldest();
    check("remaining entry is id=3", e.id == 4'd3);

    // --- Result summary (DO NOT MODIFY) ---
    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
