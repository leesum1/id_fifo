// =============================================================================
// tb_multiple_registers.sv — Test 4: multiple registers
// =============================================================================

`include "../src/sys_reg_snap.sv"

module tb_multiple_registers;

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

    $display("\n=== Test 4: multiple registers ===");

    begin
      sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) snap;
      snap = new_snap("t4_snap");

      // REG2 wire = 0x0020.  MSR(rid=3) writes REG2.
      snap.record_update(4'd3, 4'h2, 16'h0020);

      // rid=1 for REG2: rid=3 younger → pre=0x0020
      check("rid=1 hits REG2",        snap.get_value_at(4'd1, 4'h2, val));
      check("REG2 pre=0x0020",        val == 16'h0020);

      // rid=5 for REG2: rid=3 not younger → miss
      check("rid=5 misses REG2",      snap.get_value_at(4'd5, 4'h2, val) == 0);
    end

    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
