// =============================================================================
// tb_is_younger_wrap_around.sv — Test 2: is_younger with different wrap bit
// =============================================================================

`include "../src/id_fifo.sv"

typedef struct {
  logic [15:0] value;
  logic [7:0]  tag;
} payload_t;

module tb_is_younger_wrap_around;

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

    // Test 2: is_younger — different wrap bit (wrap-around)
    // ID 4'b1_001 (9) vs 4'b0_110 (6): wrap bits differ, val 1 < 6 → 9 is younger
    check("9 (wrap=1,val=1) is younger than 6 (wrap=0,val=6)",
          id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(4'd9, 4'd6));
    // ID 4'b0_110 (6) vs 4'b1_001 (9): wrap bits differ, val 6 > 1 → 6 is NOT younger
    check("6 is NOT younger than 9",
         !id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(4'd6, 4'd9));
    // ID 4'b1_000 (8) vs 4'b0_111 (7): wrap bits differ, val 0 < 7 → 8 is younger
    check("8 (just wrapped) is younger than 7",
          id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(4'd8, 4'd7));

    // --- Result summary (DO NOT MODIFY) ---
    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
