// =============================================================================
// tb_get_snapshot_at.sv — Test 5: get_snapshot_at
// =============================================================================

`include "../src/sys_reg_snap.sv"

module tb_get_snapshot_at;

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
    sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH))::snap_queue_t snaps;

    $display("\n=== Test 5: get_snapshot_at ===");

    begin
      sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) snap;
      snap = new_snap("t5_snap");

      // Records: REG1@rid=2(pre=0x0014), REG1@rid=4(pre=0x000A), REG2@rid=3(pre=0x0020)
      snap.record_update(4'd2, 4'h1, 16'h0014);
      snap.record_update(4'd4, 4'h1, 16'h000A);
      snap.record_update(4'd3, 4'h2, 16'h0020);

      // Snapshot at rid=1: younger MSRs are rid=2(REG1), rid=4(REG1), rid=3(REG2)
      //   REG1: oldest younger = rid=2 → 0x0014
      //   REG2: oldest younger = rid=3 → 0x0020
      snaps = snap.get_snapshot_at(4'd1);
      check("snapshot at rid=1: 2 regs", snaps.size() == 2);
      begin
        bit found_r1;
        bit found_r2;
        found_r1 = 0; found_r2 = 0;
        foreach (snaps[i]) begin
          if (snaps[i].reg_addr == 4'h1 && snaps[i].value == 16'h0014) found_r1 = 1;
          if (snaps[i].reg_addr == 4'h2 && snaps[i].value == 16'h0020) found_r2 = 1;
        end
        check("snapshot rid=1: REG1=0x0014", found_r1);
        check("snapshot rid=1: REG2=0x0020", found_r2);
      end

      // Snapshot at rid=3: younger MSRs are rid=4(REG1) only (rid=2,3 not younger)
      //   REG1: oldest younger = rid=4 → 0x000A
      //   REG2: no younger → omitted
      snaps = snap.get_snapshot_at(4'd3);
      check("snapshot at rid=3: 1 reg", snaps.size() == 1);
      check("snapshot rid=3: REG1=0x000A",
            snaps.size() == 1 && snaps[0].reg_addr == 4'h1 && snaps[0].value == 16'h000A);

      // Snapshot at rid=5: no younger MSRs → empty
      snaps = snap.get_snapshot_at(4'd5);
      check("snapshot at rid=5: 0 regs", snaps.size() == 0);
    end

    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
