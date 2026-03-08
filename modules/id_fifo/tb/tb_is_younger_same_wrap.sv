// =============================================================================
// tb_is_younger_same_wrap.sv — Test 1: is_younger with same wrap bit
// =============================================================================

`include "../src/id_fifo.sv"

typedef struct {
  logic [15:0] value;
  logic [7:0]  tag;
} payload_t;

module tb_is_younger_same_wrap;

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

  initial begin
    $display("\n=== %m ===");

    // Test 1: is_younger — same wrap bit
    check("3 is younger than 2 (same wrap)",  id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(4'd3, 4'd2));
    check("2 is NOT younger than 3",         !id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(4'd2, 4'd3));
    check("5 is NOT younger than 5 (equal)", !id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(4'd5, 4'd5));

    // --- Result summary (DO NOT MODIFY) ---
    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
