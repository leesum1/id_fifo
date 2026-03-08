// =============================================================================
// tb_allow_dup.sv — Test 9: allow_dup — push duplicate IDs
// =============================================================================

`include "../src/id_fifo.sv"

typedef struct {
  logic [15:0] value;
  logic [7:0]  tag;
} payload_t;

module tb_allow_dup;

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
    id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) dup_fifo;

    $display("\n=== %m ===");

    // Test 9: allow_dup — push duplicate IDs
    dup_fifo = new_fifo("dup_fifo", 1'b1);

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

    // --- Result summary (DO NOT MODIFY) ---
    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
