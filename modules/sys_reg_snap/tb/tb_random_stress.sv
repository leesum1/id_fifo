// =============================================================================
// tb_random_stress.sv — Seeded random stress test with golden model validation
// =============================================================================
// Tests sys_reg_snap with 200+ randomized operations:
// - Fixed default seed for reproducibility (DEFAULT_SEED=99)
// - Monotonic RID allocation (respects half-space wrap constraint)
// - Randomized operation types (record_update, retire, get_value_at, get_snapshot_at)
// - Randomized register addresses and values
// - Maintains (rid, reg_addr) uniqueness constraint
// - In-TB golden model validates all query results
// =============================================================================

`include "../src/sys_reg_snap.sv"

module tb_random_stress;

  localparam ID_WIDTH   = 4;
  localparam REG_WIDTH  = 16;
  localparam ADDR_WIDTH = 4;
  localparam int TOTAL_IDS   = (1 << ID_WIDTH);
  localparam int TOTAL_ADDRS = (1 << ADDR_WIDTH);
  localparam longint unsigned HALF_SPACE = (64'd1 << (ID_WIDTH-1));
  localparam int DEFAULT_SEED = 99;
  localparam int NUM_OPS = 250;

  typedef logic [ID_WIDTH-1:0]   rid_t;
  typedef logic [ADDR_WIDTH-1:0] addr_t;
  typedef logic [REG_WIDTH-1:0]  reg_t;
  typedef longint unsigned       abs_rid_t;

  typedef enum {OP_RECORD, OP_RETIRE, OP_QUERY, OP_SNAPSHOT} op_t;

  // Golden model entry
  typedef struct packed {
    abs_rid_t abs_rid;
    rid_t  rid;
    addr_t addr;
    reg_t  value;
  } golden_record_t;

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

  // Helper: is_younger (must match DUT logic)
  function automatic bit is_younger(rid_t a, rid_t b);
    bit wrap_a = a[ID_WIDTH-1];
    bit wrap_b = b[ID_WIDTH-1];
    logic [ID_WIDTH-2:0] val_a = a[ID_WIDTH-2:0];
    logic [ID_WIDTH-2:0] val_b = b[ID_WIDTH-2:0];
    if (a == b) return 0;
    if (wrap_a == wrap_b)
      return (val_a > val_b);
    else
      return (val_a < val_b);
  endfunction

  // Helper: golden retire - remove records <= retire_rid
  function automatic void golden_retire(ref golden_record_t q[$], rid_t retire_rid);
    automatic golden_record_t survivors[$];
    foreach (q[i]) begin
      if (is_younger(q[i].rid, retire_rid)) begin
        survivors.push_back(q[i]);
      end
    end
    q = survivors;
  endfunction

  // Helper: find oldest younger record for (query_rid, addr)
  function automatic bit golden_find_value(golden_record_t q[$], rid_t query_rid, addr_t query_addr, output reg_t value);
    // Find oldest record where: addr matches AND rid is younger than query_rid
    automatic int oldest_idx = -1;
    foreach (q[i]) begin
      if (q[i].addr == query_addr && is_younger(q[i].rid, query_rid)) begin
        if (oldest_idx == -1 || !is_younger(q[i].rid, q[oldest_idx].rid)) begin
          oldest_idx = i;
        end
      end
    end
    if (oldest_idx >= 0) begin
      value = q[oldest_idx].value;
      return 1;
    end
    return 0;
  endfunction

  // Helper: build golden snapshot for query_rid
  function automatic void golden_get_snapshot(golden_record_t q[$], rid_t query_rid, output golden_record_t snap_q[$]);
    // For each unique address, find the oldest younger record
    automatic bit addr_seen[TOTAL_ADDRS];
    automatic int i;
    
    snap_q.delete();
    for (i = 0; i < TOTAL_ADDRS; i++) addr_seen[i] = 0;
    
    foreach (q[idx]) begin
      if (is_younger(q[idx].rid, query_rid) && !addr_seen[q[idx].addr]) begin
        // This is the first (oldest) younger record for this address
        automatic int oldest_idx = idx;
        // Check if there's an even older younger record for this address
        for (i = 0; i < q.size(); i++) begin
          if (q[i].addr == q[idx].addr && 
              is_younger(q[i].rid, query_rid) && 
              !is_younger(q[i].rid, q[oldest_idx].rid)) begin
            oldest_idx = i;
          end
        end
        snap_q.push_back(q[oldest_idx]);
        addr_seen[q[idx].addr] = 1;
      end
    end
  endfunction

  initial begin
    sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) snap;
    golden_record_t golden_q[$];
    bit used_pairs[TOTAL_IDS][TOTAL_ADDRS];
    abs_rid_t next_abs_rid;
    rid_t next_rid;
    op_t op;
    int record_cnt, retire_cnt, query_cnt;
    
    $display("\n=== %m ===");
    $display("SEED=%0d", DEFAULT_SEED);
    /* verilator lint_off WIDTH */
    void'($urandom(DEFAULT_SEED));
    /* verilator lint_on WIDTH */

    snap = new("random_stress");
    snap.enable_log = 0;
    next_abs_rid = 0;
    // Truncated RID is always derived from absolute RID low bits.
    next_rid = rid_t'(next_abs_rid);
    record_cnt = 0;
    retire_cnt = 0;
    query_cnt = 0;

    // Initialize used_pairs
    for (int r = 0; r < TOTAL_IDS; r++)
      for (int a = 0; a < TOTAL_ADDRS; a++)
        used_pairs[r][a] = 0;

    // Execute random operations
    /* verilator lint_off IMPLICITSTATIC */
    for (int i = 0; i < NUM_OPS; i++) begin
      op = op_t'($urandom_range(0, 3));

      // Explicitly enforce the half-space monotonic RID constraint.
      // Block OP_RECORD when the live RID span reaches HALF_SPACE.
      if (op == OP_RECORD) begin
        automatic bit allow_record;
        allow_record = (golden_q.size() == 0) || ((next_abs_rid - golden_q[0].abs_rid) < HALF_SPACE);
        if (!allow_record) begin
          op = op_t'($urandom_range(1, 3));
        end
      end

      case (op)
        OP_RECORD: begin
          // Use monotonic RID
          rid_t rid;
          addr_t addr;
          int attempts;
          reg_t val;
          
          rid = next_rid;
           
          // Find unused (rid, addr) pair
          addr = addr_t'($urandom_range(0, TOTAL_ADDRS-1));
          attempts = 0;
          while (used_pairs[rid][addr] && attempts < 20) begin
            addr = addr_t'($urandom_range(0, TOTAL_ADDRS-1));
            attempts++;
          end
          
          if (!used_pairs[rid][addr]) begin
            /* verilator lint_off WIDTH */
            val = $urandom;
            /* verilator lint_on WIDTH */
            
            snap.record_update(rid, addr, val);
            golden_q.push_back('{abs_rid: next_abs_rid, rid: rid, addr: addr, value: val});
            used_pairs[rid][addr] = 1;
            record_cnt++;
            
            // Increment absolute RID (monotonic)
            next_abs_rid++;
            next_rid = rid_t'(next_abs_rid);
          end
        end

        OP_RETIRE: begin
          rid_t retire_rid;
          int r, a;
          
          if (golden_q.size() > 0) begin
            retire_rid = rid_t'($urandom_range(0, TOTAL_IDS-1));
            
            snap.retire(retire_rid);
            golden_retire(golden_q, retire_rid);
            
            // Clear used_pairs for retired RIDs
            for (r = 0; r < TOTAL_IDS; r++) begin
              if (!is_younger(rid_t'(r), retire_rid)) begin
                for (a = 0; a < TOTAL_ADDRS; a++)
                  used_pairs[r][a] = 0;
              end
            end
            
            retire_cnt++;
          end
        end

        OP_QUERY: begin
          rid_t query_rid;
          addr_t query_addr;
          reg_t dut_val, golden_val;
          bit dut_found, golden_found;
          
          if (golden_q.size() > 0) begin
            query_rid = rid_t'($urandom_range(0, TOTAL_IDS-1));
            query_addr = addr_t'($urandom_range(0, TOTAL_ADDRS-1));
            
            dut_found = snap.get_value_at(query_rid, query_addr, dut_val);
            golden_found = golden_find_value(golden_q, query_rid, query_addr, golden_val);
            
            check($sformatf("op%0d: query rid=%0d addr=%0d found=%b", i, query_rid, query_addr, dut_found),
                  dut_found == golden_found);
            
            if (dut_found && golden_found) begin
              check($sformatf("op%0d: query rid=%0d addr=%0d val=0x%04x", i, query_rid, query_addr, dut_val),
                    dut_val == golden_val);
            end
            
            query_cnt++;
          end
        end

        OP_SNAPSHOT: begin
          rid_t snap_rid;
          sys_reg_snap #(.ID_WIDTH(ID_WIDTH), .REG_WIDTH(REG_WIDTH), .ADDR_WIDTH(ADDR_WIDTH))::snap_entry_t dut_snaps[$];
          golden_record_t golden_snaps[$];
          int j;
          
          if (golden_q.size() > 0) begin
            snap_rid = rid_t'($urandom_range(0, TOTAL_IDS-1));
            
            dut_snaps = snap.get_snapshot_at(snap_rid);
            golden_get_snapshot(golden_q, snap_rid, golden_snaps);
            
            check($sformatf("op%0d: snapshot rid=%0d size=%0d", i, snap_rid, dut_snaps.size()),
                  dut_snaps.size() == golden_snaps.size());
            
            // Verify each entry in golden snapshot appears in DUT snapshot
            foreach (golden_snaps[g]) begin
              automatic bit found_match = 0;
              for (j = 0; j < dut_snaps.size(); j++) begin
                if (dut_snaps[j].reg_addr == golden_snaps[g].addr &&
                    dut_snaps[j].value == golden_snaps[g].value) begin
                  found_match = 1;
                  break;
                end
              end
              check($sformatf("op%0d: snapshot rid=%0d addr=%0d val=0x%04x", 
                    i, snap_rid, golden_snaps[g].addr, golden_snaps[g].value),
                    found_match);
            end
            
            query_cnt++;
          end
        end
      endcase

      // Validate size after each operation
      check($sformatf("op%0d: size matches (DUT=%0d golden=%0d)", i, snap.size(), golden_q.size()),
            snap.size() == golden_q.size());
    end
    /* verilator lint_on IMPLICITSTATIC */

    // Summary
    $display("\nOperation summary:");
    $display("  Records: %0d", record_cnt);
    $display("  Retires: %0d", retire_cnt);
    $display("  Queries: %0d", query_cnt);
    $display("  Total:   %0d", NUM_OPS);

    // Final check
    check("final: DUT size matches golden", snap.size() == golden_q.size());

    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
