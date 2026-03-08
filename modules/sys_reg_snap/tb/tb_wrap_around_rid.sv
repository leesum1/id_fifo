// =============================================================================
// tb_wrap_around_rid.sv — Test 7: wrap-around RID
// =============================================================================

`include "../src/sys_reg_snap.sv"

module tb_wrap_around_rid;

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

    $display("\n=== Test 7: wrap-around RID ===");

    begin
      sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) ws;
      ws = new_snap("wrap_snap");

      // ID_WIDTH=4: wrap at 0b1xxx.  Sequence: ...6,7,8(wrapped),9,...
      // is_younger(8,7)=true (8 wrapped, 7 not; val_8=0 < val_7=7)
      ws.record_update(4'd6, 4'h0, 16'hFF00); // REG0 pre before rid=6 writes
      ws.record_update(4'd8, 4'h0, 16'hFF06); // REG0 pre before rid=8 writes
      ws.record_update(4'd9, 4'h1, 16'hEE00); // REG1 pre before rid=9 writes

      // query rid=5: younger MSRs for REG0 are rid=6,8
      //   oldest among younger = rid=6 → pre=0xFF00
      check("wrap: rid=5 gets rid=6 pre=0xFF00", ws.get_value_at(4'd5, 4'h0, val));
      check("wrap: val=0xFF00",                  val == 16'hFF00);

      // query rid=7: younger MSRs for REG0 are rid=8 only (rid=6 not younger than 7)
      //   oldest = rid=8 → pre=0xFF06
      check("wrap: rid=7 gets rid=8 pre=0xFF06", ws.get_value_at(4'd7, 4'h0, val));
      check("wrap: val=0xFF06",                  val == 16'hFF06);

      // query rid=8: rid=8 NOT younger than itself → no younger MSR for REG0 → miss
      check("wrap: rid=8 miss REG0",             ws.get_value_at(4'd8, 4'h0, val) == 0);

      // query rid=7 for REG1: rid=9 is younger (wrapped) → pre=0xEE00
      check("wrap: rid=7 gets REG1 pre=0xEE00", ws.get_value_at(4'd7, 4'h1, val));
      check("wrap: REG1 val=0xEE00",             val == 16'hEE00);

      // snapshot at rid=7: REG0(rid=8)=0xFF06, REG1(rid=9)=0xEE00
      snaps = ws.get_snapshot_at(4'd7);
      check("wrap: snapshot at rid=7: 2 regs", snaps.size() == 2);
    end

    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
