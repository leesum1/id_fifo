// =============================================================================
// tb_retire.sv — Test 6: retire
// =============================================================================

`include "../src/sys_reg_snap.sv"

module tb_retire;

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

    $display("\n=== Test 6: retire ===");

    begin
      sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) snap;
      snap = new_snap("t6_snap");

      snap.record_update(4'd2, 4'h1, 16'h0014);
      snap.record_update(4'd4, 4'h1, 16'h000A);
      snap.record_update(4'd3, 4'h2, 16'h0020);

      // retire(rid=3): removes rid=2(REG1), rid=3(REG2); keeps rid=4(REG1)
      snap.retire(4'd3);
      check("size=1 after retire(3)", snap.size() == 1);

      // rid=1 for REG1: only rid=4 remains; it is younger → pre=0x000A
      check("rid=1 now gets rid=4 pre", snap.get_value_at(4'd1, 4'h1, val));
      check("value=0x000A",             val == 16'h000A);

      // REG2 fully retired → miss
      check("REG2 miss after retire",   snap.get_value_at(4'd1, 4'h2, val) == 0);

      // rid=5 for REG1: rid=4 not younger → miss
      check("rid=5 miss REG1 after retire", snap.get_value_at(4'd5, 4'h1, val) == 0);
    end

    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
