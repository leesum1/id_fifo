// =============================================================================
// tb_add_msr_example.sv — Test 2: motivating example — ADD + MSR
// =============================================================================

`include "../src/sys_reg_snap.sv"

module tb_add_msr_example;

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

    $display("\n=== Test 2: motivating example — ADD + MSR ===");

    begin
      sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) snap;
      snap = new_snap("t2_snap");

      // REG1 wire = 0x0014 (20).  MSR(rid=2) is about to write 10.
      // Record pre_value before MSR executes.
      snap.record_update(4'd2, 4'h1, 16'h0014);

      // ADD(rid=1): rid=2 IS younger than rid=1 → hit, pre=0x14
      check("ADD(rid=1) hits, gets pre-MSR value", snap.get_value_at(4'd1, 4'h1, val));
      check("value is 0x0014 (20)",                val == 16'h0014);

      // rid=3 (after MSR): rid=2 is NOT younger than rid=3 → miss
      check("rid=3 miss (use wire=10)", snap.get_value_at(4'd3, 4'h1, val) == 0);

      // rid=2 itself: rid=2 NOT younger than rid=2 → miss
      check("rid=2 miss (exact)",       snap.get_value_at(4'd2, 4'h1, val) == 0);
    end

    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
