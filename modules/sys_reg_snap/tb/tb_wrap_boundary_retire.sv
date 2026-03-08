// =============================================================================
// tb_wrap_boundary_retire.sv — Test 10: wrap boundary 15->0 with retire
// =============================================================================

`include "../src/sys_reg_snap.sv"

module tb_wrap_boundary_retire;

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

    $display("\n=== Test 10: wrap boundary 15->0 with retire ===");

    begin
      sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) snap;
      snap = new_snap("t10_wrap_retire");

      // Cross-boundary records: 14,15,0,1 (program order)
      snap.record_update(4'd14, 4'h1, 16'h0E0E);
      snap.record_update(4'd15, 4'h1, 16'h0F0F);
      snap.record_update(4'd0,  4'h1, 16'h0000);
      snap.record_update(4'd1,  4'h1, 16'h0101);

      // query rid=13: younger are 14,15,0,1 -> oldest younger is 14
      check("wrap15->0: rid=13 gets pre of rid=14", snap.get_value_at(4'd13, 4'h1, val));
      check("wrap15->0: value=0x0E0E",              val == 16'h0E0E);

      // query rid=15: younger are 0,1 -> oldest younger is 0
      check("wrap15->0: rid=15 gets pre of rid=0", snap.get_value_at(4'd15, 4'h1, val));
      check("wrap15->0: value=0x0000",             val == 16'h0000);

      snaps = snap.get_snapshot_at(4'd15);
      check("wrap15->0: snapshot rid=15 has 1 reg", snaps.size() == 1);
      check("wrap15->0: snapshot value=0x0000",
            snaps.size() == 1 && snaps[0].reg_addr == 4'h1 && snaps[0].value == 16'h0000);

      // retire(15): keep only younger than 15 -> rid 0/1 remain
      snap.retire(4'd15);
      check("wrap15->0: size=2 after retire(15)", snap.size() == 2);
      check("wrap15->0: rid=15 still resolves via rid=0", snap.get_value_at(4'd15, 4'h1, val));
      check("wrap15->0: value still 0x0000",               val == 16'h0000);
    end

    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
