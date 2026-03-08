// =============================================================================
// tb_miss_no_history.sv — Test 1: miss (no history)
// =============================================================================

`include "../src/sys_reg_snap.sv"

module tb_miss_no_history;

  localparam ID_WIDTH   = 4;
  localparam REG_WIDTH  = 16;
  localparam ADDR_WIDTH = 4;

  typedef logic [ID_WIDTH-1:0]   rid_t;
  typedef logic [ADDR_WIDTH-1:0] addr_t;
  typedef logic [REG_WIDTH-1:0]  data_t;

  int pass_cnt = 0;
  int fail_cnt = 0;

  function void check(string test_name, bit condition);
    if (condition) begin
      $display("  [PASS] %s", test_name);
      pass_cnt++;
    end else begin
      $display("  [FAIL] %s", test_name);
      fail_cnt++;
    end
  endfunction

  function automatic sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) new_snap(string inst_name);
    sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) s;
    s = new(inst_name);
    s.enable_log = 1;
    return s;
  endfunction

  initial begin
    data_t val;

    $display("\n=== Test 1: miss (no history) ===");

    begin
      sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) snap;
      snap = new_snap("t1_snap");
      check("miss on empty snap", snap.get_value_at(4'd3, 4'h1, val) == 0);
      check("val unchanged on miss", val === '0);  // use val to avoid UNUSEDSIGNAL
      check("snap is empty",      snap.empty());
    end

    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
