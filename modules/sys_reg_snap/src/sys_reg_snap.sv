// =============================================================================
// sys_reg_snap.sv — SYS_REG historical snapshot tracker
// =============================================================================
//
// Assumptions:
//   1. MSR instructions execute IN ORDER (program order).
//   2. MSR updates the register wire immediately upon execution.
//   3. Each record stores the pre-write value (wire value BEFORE the MSR
//      writes).  The new value is NOT tracked — it is observable on the wire.
//
// Key insight:
//   MSR(rid=X).pre_value == register value after all MSRs with rid < X ran.
//   Therefore, for query_rid, the correct value is the pre_value of the
//   OLDEST MSR record that is strictly younger than query_rid.
//   If no such record exists, the current wire value is already correct.
//
// Parameters:
//   ID_WIDTH   — RID bit-width; MSB is the wrap-around bit (matches id_fifo)
//   REG_WIDTH  — SYS_REG data width in bits
//   ADDR_WIDTH — SYS_REG address width in bits
//
// Usage:
//   sys_reg_snap #(.ID_WIDTH(6), .REG_WIDTH(64), .ADDR_WIDTH(8)) snap = new("snap");
//   snap.enable_log    = 1;
//   snap.enable_assert = 1;
//
//   // When an MSR instruction executes (BEFORE it writes to the wire):
//   snap.record_update(rid, reg_addr, current_wire);
//
//   // When an older instruction commits and needs the SYS_REG value:
//   if (snap.get_value_at(query_rid, reg_addr, value))
//     use(value);           // hit — pre_value of the youngest eligible MSR
//   else
//     use(current_wire);    // no in-flight MSR is younger than query_rid
//
//   // Get all registers with relevant history at query_rid:
//   entries = snap.get_snapshot_at(query_rid);
//
//   // When instructions up to and including retire_rid commit:
//   snap.retire(retire_rid);
//
// =============================================================================

class sys_reg_snap #(int ID_WIDTH = 8, int REG_WIDTH = 64, int ADDR_WIDTH = 8);

  // --------------------------------------------------------------------------
  // Types
  // --------------------------------------------------------------------------
  typedef logic [ID_WIDTH-1:0]   rid_t;
  typedef logic [ADDR_WIDTH-1:0] addr_t;
  typedef logic [REG_WIDTH-1:0]  data_t;

  typedef struct {
    rid_t  rid;
    addr_t reg_addr;
    data_t pre_value; // register value BEFORE this MSR writes
  } record_t;

  typedef struct {
    addr_t reg_addr;
    data_t value;
  } snap_entry_t;

  typedef snap_entry_t snap_queue_t[$];

  // --------------------------------------------------------------------------
  // Internal storage
  // --------------------------------------------------------------------------
  record_t records[$];

  // --------------------------------------------------------------------------
  // Configuration
  // --------------------------------------------------------------------------
  bit    enable_log    = 0;
  bit    enable_assert = 0;
  string name          = "sys_reg_snap";

  // --------------------------------------------------------------------------
  // Statistics counters (dump-visible only)
  // --------------------------------------------------------------------------
  int stat_record_cnt    = 0;
  int stat_retire_cnt    = 0;
  int stat_query_hit_cnt = 0;
  int stat_query_miss_cnt = 0;
  int stat_peak_size     = 0;
  int stat_snapshot_cnt  = 0;

  // --------------------------------------------------------------------------
  // Constructor
  // --------------------------------------------------------------------------
  function new(string inst_name = "sys_reg_snap");
    this.name = inst_name;
    records   = {};
  endfunction

  // ==========================================================================
  // is_younger — wrap-around aware RID comparison (mirrors id_fifo logic)
  // Returns 1 if `a` is strictly younger (newer) than `b`.
  // ==========================================================================
  static function bit is_younger(rid_t a, rid_t b);
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

  // ==========================================================================
  // record_update — capture the pre-write value when an MSR executes
  //
  // Call this BEFORE the MSR updates the register wire, passing the current
  // wire value as pre_value.
  //
  // Constraint: same (rid, reg_addr) pair must not appear more than once.
  // ==========================================================================
  function void record_update(rid_t rid, addr_t reg_addr, data_t pre_value);
    record_t r;

    foreach (records[i]) begin
      RECORD_DUP_CHECK: assert (!(records[i].rid == rid && records[i].reg_addr == reg_addr)) else
        $fatal(1, "[%s] record_update — duplicate (rid=0x%0h, reg=0x%0h) at index %0d",
               name, rid, reg_addr, i);
    end

    r.rid       = rid;
    r.reg_addr  = reg_addr;
    r.pre_value = pre_value;
    records.push_back(r);

    // Update stat_record_cnt
    stat_record_cnt++;

    // Update stat_peak_size
    if (records.size() > stat_peak_size)
      stat_peak_size = records.size();

    if (enable_log)
      $display("[%s] record_update: rid=0x%0h  reg=0x%0h  pre=0x%0h  (size=%0d)",
               name, rid, reg_addr, pre_value, records.size());
  endfunction

  // ==========================================================================
  // get_value_at — return the correct value of reg_addr at query_rid
  //
  // Since MSRs execute in order, MSR(rid=X).pre_value equals the register
  // value after all MSRs with rid < X have run.  Therefore, for query_rid
  // the correct answer is the pre_value of the OLDEST MSR record that is
  // strictly younger than query_rid.
  //
  // Returns 1 and sets value on hit.
  // Returns 0 (miss) if no MSR younger than query_rid exists for this reg;
  // in that case the current wire value is already correct.
  // ==========================================================================
  function bit get_value_at(rid_t query_rid, addr_t reg_addr, output data_t value);
    bit   found    = 0;
    rid_t best_rid;

    foreach (records[i]) begin
      if (records[i].reg_addr != reg_addr)        continue;
      if (!is_younger(records[i].rid, query_rid)) continue; // only younger MSRs

      // Keep the oldest among the younger-than-query records
      if (!found || is_younger(best_rid, records[i].rid)) begin
        found    = 1;
        best_rid = records[i].rid;
        value    = records[i].pre_value;
        break; // optimization: records are in program order, so the first match is the oldest
      end
    end

    if (enable_log) begin
      if (found)
        $display("[%s] get_value_at: query_rid=0x%0h  reg=0x%0h  pre=0x%0h  (hit, msr_rid=0x%0h)",
                 name, query_rid, reg_addr, value, best_rid);
      else
        $display("[%s] get_value_at: query_rid=0x%0h  reg=0x%0h  miss (use wire)",
                 name, query_rid, reg_addr);
    end

    if (enable_assert && found) begin
      bit hit_has_source = 0;
      foreach (records[j]) begin
        if (records[j].rid == best_rid && records[j].reg_addr == reg_addr) begin
          hit_has_source = 1;
          break;
        end
      end
      GET_VALUE_HIT_SOURCE_CHECK: assert (hit_has_source) else
        $error("[%s] get_value_at — internal error: hit record not found in history (query_rid=0x%0h reg=0x%0h best_rid=0x%0h)",
               name, query_rid, reg_addr, best_rid);
    end

    // Update stat counters
    if (found)
      stat_query_hit_cnt++;
    else
      stat_query_miss_cnt++;

    return found;
  endfunction

  // ==========================================================================
  // get_snapshot_at — return all registers with relevant history at query_rid
  //
  // For each register that has at least one MSR younger than query_rid,
  // returns the pre_value of the oldest such MSR (same rule as get_value_at).
  // Registers with no younger MSR records are omitted.
  //
  // Optimization: records are stored in program order (oldest first).  The
  // first qualifying record for each register is the oldest younger MSR.
  // The result queue itself serves as the "seen" tracker — no associative
  // arrays needed.
  // ==========================================================================
  function snap_queue_t get_snapshot_at(rid_t query_rid);
    snap_queue_t result;

    foreach (records[i]) begin
      addr_t a   = records[i].reg_addr;
      bit    seen = 0;

      if (!is_younger(records[i].rid, query_rid)) continue;

      foreach (result[j]) begin
        if (result[j].reg_addr == a) begin seen = 1; break; end
      end
      if (seen) continue;

      begin
        snap_entry_t e;
        e.reg_addr = a;
        e.value    = records[i].pre_value;
        result.push_back(e);
      end
    end

    if (enable_log)
      $display("[%s] get_snapshot_at: query_rid=0x%0h  regs_found=%0d",
               name, query_rid, result.size());

    // Update stat counter
    stat_snapshot_cnt++;

    return result;
  endfunction

  // ==========================================================================
  // retire — remove records no longer needed
  //
  // Once instructions up to retire_rid have committed, any MSR record that
  // is older than or equal to retire_rid can never be the "oldest younger"
  // candidate for any future query (since future queries come from younger
  // instructions still in flight).  Those records are freed.
  // ==========================================================================
  function void retire(rid_t retire_rid);
    record_t keep[$];
    int retired_count = 0;

    foreach (records[i]) begin
      if (is_younger(records[i].rid, retire_rid))
        keep.push_back(records[i]);
      else begin
        retired_count++;
        if (enable_log)
          $display("[%s] retire: removing rid=0x%0h  reg=0x%0h",
                   name, records[i].rid, records[i].reg_addr);
      end
    end

    records = keep;

    // Update stat counter
    stat_retire_cnt += retired_count;

    if (enable_log)
      $display("[%s] retire: retire_rid=0x%0h  remaining=%0d", name, retire_rid, records.size());
  endfunction

  // ==========================================================================
  // Helpers
  // ==========================================================================
  function int size();
    return records.size();
  endfunction

  function bit empty();
    return (records.size() == 0);
  endfunction

  function void dump();
    $display("[%s] --- dump (%0d records) ---", name, records.size());
    foreach (records[i])
      $display("[%s]   [%0d] rid=0x%0h  reg=0x%0h  pre=0x%0h",
               name, i, records[i].rid, records[i].reg_addr, records[i].pre_value);
    $display("[%s] --- statistics ---", name);
    $display("[%s]   stat_record_cnt=%0d", name, stat_record_cnt);
    $display("[%s]   stat_retire_cnt=%0d", name, stat_retire_cnt);
    $display("[%s]   stat_query_hit_cnt=%0d", name, stat_query_hit_cnt);
    $display("[%s]   stat_query_miss_cnt=%0d", name, stat_query_miss_cnt);
    $display("[%s]   stat_peak_size=%0d", name, stat_peak_size);
    $display("[%s]   stat_snapshot_cnt=%0d", name, stat_snapshot_cnt);
    $display("[%s] --- end dump ---", name);
  endfunction

endclass
