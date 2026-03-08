// =============================================================================
// tb_wrap_boundary_is_younger.sv — Test 12: wrap boundary 15->0 is_younger
// =============================================================================

`include "../src/id_fifo.sv"

typedef struct {
  logic [15:0] value;
  logic [7:0]  tag;
} payload_t;

module tb_wrap_boundary_is_younger;

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

    // Test 12: wrap boundary 15->0 is_younger
    check("0 is younger than 15 at wrap boundary",
          id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(4'd0, 4'd15));
    check("15 is NOT younger than 0 at wrap boundary",
         !id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(4'd15, 4'd0));

    // --- Result summary (DO NOT MODIFY) ---
    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
