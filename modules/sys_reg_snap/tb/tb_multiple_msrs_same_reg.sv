// =============================================================================
// tb_multiple_msrs_same_reg.sv — Test 3: multiple MSRs to same register
// =============================================================================

`include "../src/sys_reg_snap.sv"

module tb_multiple_msrs_same_reg;

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

    $display("\n=== Test 3: multiple MSRs to same register ===");

    begin
      sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) snap;
      snap = new_snap("t3_snap");

      snap.record_update(4'd2, 4'h1, 16'h0014);
      snap.record_update(4'd4, 4'h1, 16'h000A);

      // rid=1 should get oldest younger MSR → rid=2 (pre=0x0014)
      check("rid=1 gets oldest younger rid=2", snap.get_value_at(4'd1, 4'h1, val));
      check("value is 0x0014",                 val == 16'h0014);

      // rid=3: younger MSRs are rid=4 only (rid=2 is older) → pre of rid=4 = 0x000A
      check("rid=3 gets oldest younger rid=4", snap.get_value_at(4'd3, 4'h1, val));
      check("value is 0x000A",                 val == 16'h000A);

      // rid=5: no younger MSR → miss
      check("rid=5 miss",                      snap.get_value_at(4'd5, 4'h1, val) == 0);
    end

    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
