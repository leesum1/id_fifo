// =============================================================================
// tb_same_rid_diff_regs.sv — Test 8: same RID, different registers (legal)
// =============================================================================

`include "../src/sys_reg_snap.sv"

module tb_same_rid_diff_regs;

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
    sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH))::snap_queue_t snaps;

    $display("\n=== Test 8: same RID, different registers (legal) ===");

    begin
      sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) mr;
      mr = new_snap("multi_reg_snap");

      // One MSR instruction writing two registers at rid=3 (legal)
      mr.record_update(4'd3, 4'h0, 16'h1000);
      mr.record_update(4'd3, 4'h1, 16'h2000);

      check("mr: rid=1 hits REG0 (younger rid=3)", mr.get_value_at(4'd1, 4'h0, val));
      check("mr: REG0 pre=0x1000",                 val == 16'h1000);
      check("mr: rid=1 hits REG1 (younger rid=3)", mr.get_value_at(4'd1, 4'h1, val));
      check("mr: REG1 pre=0x2000",                 val == 16'h2000);

      // rid=3 itself: no younger MSR → miss
      check("mr: rid=3 miss REG0",  mr.get_value_at(4'd3, 4'h0, val) == 0);

      snaps = mr.get_snapshot_at(4'd1);
      check("mr: snapshot at rid=1 has 2 regs", snaps.size() == 2);
    end

    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
