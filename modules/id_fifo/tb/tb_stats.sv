// =============================================================================
// tb_stats.sv — Test: id_fifo operation counters (stat_push_cnt, stat_delete_cnt,
//                     stat_flush_cnt, stat_peak_size, stat_wrap_cnt)
// =============================================================================

`include "../src/id_fifo.sv"

typedef struct {
  logic [15:0] value;
  logic [7:0]  tag;
} payload_t;

module tb_stats;

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
    id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) f;

    $display("\n=== %m ===");

    // Test: Push operations increment stat_push_cnt
    f = new_fifo("test_push");
    f.push(4'd0, make_payload(16'h0000, 8'h00));
    f.push(4'd1, make_payload(16'h0001, 8'h00));
    f.push(4'd2, make_payload(16'h0002, 8'h00));
    check("push operations: stat_push_cnt == 3", f.stat_push_cnt == 3);

    // Test: Delete operations increment stat_delete_cnt
    f.delete_by_id(4'd1);
    check("after delete: stat_delete_cnt == 1", f.stat_delete_cnt == 1);

    // Test: Flush_younger operations increment stat_flush_cnt
    // Push higher IDs that will be younger than flush reference
    f = new_fifo("test_flush_younger");
    f.push(4'd0, make_payload(16'h0000, 8'h00));
    f.push(4'd2, make_payload(16'h0002, 8'h00));  // 2 is younger (larger val, same wrap bit)
    f.flush_younger(4'd1);  // Remove entries younger than 1: removes 2, keeps 0
    check("after flush_younger: stat_flush_cnt == 1", f.stat_flush_cnt == 1);

    // Test: Peak size tracking
    f = new_fifo("test_peak");
    f.push(4'd0, make_payload(16'h0000, 8'h00));
    check("peak_size after 1 push: stat_peak_size == 1", f.stat_peak_size == 1);
    f.push(4'd1, make_payload(16'h0001, 8'h00));
    check("peak_size after 2 pushes: stat_peak_size == 2", f.stat_peak_size == 2);
    f.push(4'd2, make_payload(16'h0002, 8'h00));
    check("peak_size after 3 pushes: stat_peak_size == 3", f.stat_peak_size == 3);
    f.delete_by_id(4'd2);
    f.delete_by_id(4'd1);
    f.delete_by_id(4'd0);
    f.push(4'd3, make_payload(16'h0003, 8'h00));
    check("peak_size after delete+push: stat_peak_size == 3 (not 1)", f.stat_peak_size == 3);

    // Test: Wrap bit transitions increment stat_wrap_cnt
    // ID_WIDTH=4: IDs 0-7 are wrap_bit=0, IDs 8-15 are wrap_bit=1
    f = new_fifo("test_wrap");
    f.push(4'd7,  make_payload(16'h0007, 8'h00));  // wrap_bit=0, val=7
    f.push(4'd8,  make_payload(16'h0008, 8'h00));  // wrap_bit=1, val=0 — WRAP transition
    check("after wrap transition: stat_wrap_cnt == 1", f.stat_wrap_cnt == 1);
    f.push(4'd9,  make_payload(16'h0009, 8'h00));  // wrap_bit=1, val=1 — no wrap transition
    check("no wrap transition: stat_wrap_cnt == 1 (unchanged)", f.stat_wrap_cnt == 1);

    // Test: flush_younger_or_eq increments stat_flush_cnt
    f = new_fifo("test_flush_or_eq");
    f.push(4'd0, make_payload(16'h0000, 8'h00));
    f.push(4'd1, make_payload(16'h0001, 8'h00));
    f.push(4'd2, make_payload(16'h0002, 8'h00));
    f.flush_younger_or_eq(4'd1);
    check("flush_younger_or_eq increments stat_flush_cnt", f.stat_flush_cnt == 1);

    // Test: dump() output includes all 5 stat labels
    f = new_fifo("test_dump");
    f.push(4'd0, make_payload(16'h0000, 8'h00));
    f.dump();
    // dump() called above should show stats; visual verification in test output

    // --- Result summary (DO NOT MODIFY) ---
    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
