// =============================================================================
// id_fifo.sv — Parameterized ID-indexed FIFO with wrap-around ID comparison
// =============================================================================
//
// Parameters:
//   T        — payload data type (supports any struct / class / built-in type)
//   ID_WIDTH — total bit-width of the ID field; the MSB is the wrap-around bit
//
// Usage:
//   id_fifo #(.T(my_struct_t), .ID_WIDTH(6)) fifo = new("my_fifo");
//   fifo.enable_log       = 1;   // optional verbose logging
//   fifo.enable_assert    = 1;   // optional assertion checks
//   fifo.allow_dup        = 1;   // allow duplicate IDs (delete_by_id removes all)
//   fifo.push(id, data);
//   entry = fifo.peek_oldest();
//   fifo.flush_younger(some_id);
//   fifo.delete_by_id(some_id);
// =============================================================================

class id_fifo #(type T = logic [7:0], int ID_WIDTH = 8);

  // --------------------------------------------------------------------------
  // Types
  // --------------------------------------------------------------------------
  typedef logic [ID_WIDTH-1:0] id_t;

  typedef struct {
    id_t id;
    T    data;
  } entry_t;

  typedef entry_t entry_queue_t[$];

  // --------------------------------------------------------------------------
  // Internal storage (queue, index 0 = oldest)
  // --------------------------------------------------------------------------
  entry_t entries[$];

  // --------------------------------------------------------------------------
  // Configuration
  // --------------------------------------------------------------------------
  bit enable_log       = 0;
  bit enable_assert    = 0;
  bit allow_dup        = 0;
  string name          = "id_fifo";

  // --------------------------------------------------------------------------
  // Statistics (exposed through dump() output)
  // --------------------------------------------------------------------------
  int stat_push_cnt    = 0;    // total push operations
  int stat_delete_cnt  = 0;    // total delete_by_id operations
  int stat_flush_cnt   = 0;    // total flush operations (both flush_younger variants)
  int stat_peak_size   = 0;    // maximum queue size reached
  int stat_wrap_cnt    = 0;    // wrap bit transitions detected during push

  // --------------------------------------------------------------------------
  // Constructor
  // --------------------------------------------------------------------------
  function new(string inst_name = "id_fifo");
    this.name = inst_name;
    entries = {};
  endfunction

  // ==========================================================================
  // ID comparison — wrap-around aware
  // ==========================================================================
  // The MSB (bit ID_WIDTH-1) is the "wrap bit".
  // Two IDs are compared on their lower (ID_WIDTH-1) bits:
  //   - Same wrap bit  → larger lower bits = younger (newer)
  //   - Diff wrap bit  → smaller lower bits = younger (it has wrapped)
  // Returns 1 if `a` is strictly younger (newer) than `b`.
  // ==========================================================================
  static function bit is_younger(id_t a, id_t b);
    bit wrap_a = a[ID_WIDTH-1];
    bit wrap_b = b[ID_WIDTH-1];
    logic [ID_WIDTH-2:0] val_a = a[ID_WIDTH-2:0];
    logic [ID_WIDTH-2:0] val_b = b[ID_WIDTH-2:0];

    if (a == b) return 0; // equal → not younger

    if (wrap_a == wrap_b)
      return (val_a > val_b);
    else
      return (val_a < val_b);
  endfunction

  // Returns 1 if `a` is strictly older than `b`.
  static function bit is_older(id_t a, id_t b);
    return is_younger(b, a);
  endfunction

  // ==========================================================================
  // push — append (id, data) to the FIFO tail
  // ==========================================================================
  function void push(id_t id, T data);
    entry_t e;
    bit prev_wrap_bit;
    bit curr_wrap_bit;

    e.id   = id;
    e.data = data;

    // Track wrap bit transition
    if (entries.size() > 0) begin
      prev_wrap_bit = entries[$].id[ID_WIDTH-1];
      curr_wrap_bit = id[ID_WIDTH-1];
      if (prev_wrap_bit != curr_wrap_bit)
        stat_wrap_cnt++;
    end

    entries.push_back(e);
    stat_push_cnt++;

    // Track peak size
    if (entries.size() > stat_peak_size)
      stat_peak_size = entries.size();

    if (enable_log)
      $display("[%s] push: id=0x%0h  (size=%0d)", name, id, entries.size());
  endfunction

  // ==========================================================================
  // flush_younger — remove every entry whose ID is strictly younger than `id`
  // ==========================================================================
  function void flush_younger(id_t id);
    entry_t keep[$];

    if (enable_assert) begin
      FLUSH_EMPTY_CHECK: assert (entries.size() > 0) else
        $warning("[%s] flush_younger — called on empty FIFO", name);
    end

    foreach (entries[i]) begin
      if (!is_younger(entries[i].id, id)) begin
        keep.push_back(entries[i]);
      end else begin
        if (enable_log)
          $display("[%s] flush_younger: removing id=0x%0h (younger than 0x%0h)",
                   name, entries[i].id, id);
      end
    end

    if (keep.size() < entries.size())
      stat_flush_cnt++;

    entries = keep;

    if (enable_log)
      $display("[%s] flush_younger: ref_id=0x%0h  remaining=%0d", name, id, entries.size());
  endfunction

  // ==========================================================================
  // flush_younger_or_eq — remove every entry whose ID is younger than or
  //                        equal to `id`
  // ==========================================================================
  function void flush_younger_or_eq(id_t id);
    entry_t keep[$];

    if (enable_assert) begin
      FLUSH_EQ_EMPTY_CHECK: assert (entries.size() > 0) else
        $warning("[%s] flush_younger_or_eq — called on empty FIFO", name);
    end

    foreach (entries[i]) begin
      if (!is_younger(entries[i].id, id) && entries[i].id != id) begin
        keep.push_back(entries[i]);
      end else begin
        if (enable_log)
          $display("[%s] flush_younger_or_eq: removing id=0x%0h (younger than or eq 0x%0h)",
                   name, entries[i].id, id);
      end
    end

    if (keep.size() < entries.size())
      stat_flush_cnt++;

    entries = keep;

    if (enable_log)
      $display("[%s] flush_younger_or_eq: ref_id=0x%0h  remaining=%0d", name, id, entries.size());
  endfunction

  // ==========================================================================
  // delete_by_id — remove entries whose ID matches exactly
  //   allow_dup=0 → remove first match only
  //   allow_dup=1 → remove ALL matches
  // ==========================================================================
  function void delete_by_id(id_t id);
    if (allow_dup) begin
      entry_t keep[$];
      int removed = 0;

      foreach (entries[i]) begin
        if (entries[i].id == id)
          removed++;
        else
          keep.push_back(entries[i]);
      end

      if (enable_assert) begin
        DELETE_DUP_FOUND_CHECK: assert (removed > 0) else
          $error("[%s] delete_by_id — id 0x%0h not found", name, id);
      end

      if (removed == 0) return;

      stat_delete_cnt++;
      entries = keep;

      if (enable_log)
        $display("[%s] delete_by_id: id=0x%0h  removed=%0d  (size=%0d)",
                 name, id, removed, entries.size());
    end else begin
      int found_idx = -1;

      foreach (entries[i]) begin
        if (entries[i].id == id) begin
          found_idx = i;
          break;
        end
      end

      if (enable_assert) begin
        DELETE_FOUND_CHECK: assert (found_idx >= 0) else
          $error("[%s] delete_by_id — id 0x%0h not found", name, id);
      end

      if (found_idx < 0) return;

      stat_delete_cnt++;
      entries.delete(found_idx);

      if (enable_log)
        $display("[%s] delete_by_id: id=0x%0h  (size=%0d)", name, id, entries.size());
    end
  endfunction

  // ==========================================================================
  // peek_oldest — return the oldest entry (first pushed, index 0)
  // ==========================================================================
  function entry_t peek_oldest();
    if (enable_assert) begin
      PEEK_EMPTY_CHECK: assert (entries.size() > 0) else
        $fatal(1, "[%s] peek_oldest — FIFO is empty", name);
    end

    if (enable_log)
      $display("[%s] peek_oldest: id=0x%0h  (size=%0d)", name, entries[0].id, entries.size());

    return entries[0];
  endfunction

  // ==========================================================================
  // peek_by_id — return the oldest entry whose ID matches exactly (no removal)
  // ==========================================================================
  function entry_t peek_by_id(id_t id);
    foreach (entries[i]) begin
      if (entries[i].id == id) begin
        if (enable_log)
          $display("[%s] peek_by_id: id=0x%0h  (index=%0d)", name, id, i);
        return entries[i];
      end
    end

    if (enable_assert) begin
      PEEK_BY_ID_FOUND_CHECK: assert (0) else
        $fatal(1, "[%s] peek_by_id — id 0x%0h not found", name, id);
    end

    return entries[0]; // unreachable; satisfies return type
  endfunction

  // ==========================================================================
  // peek_all_by_id — return all entries whose ID matches exactly (no removal)
  //   Useful when allow_dup=1; returns entries in insertion order.
  // ==========================================================================
  function entry_queue_t peek_all_by_id(id_t id);
    entry_queue_t result;

    foreach (entries[i]) begin
      if (entries[i].id == id)
        result.push_back(entries[i]);
    end

    if (enable_assert) begin
      PEEK_ALL_BY_ID_FOUND_CHECK: assert (result.size() > 0) else
        $fatal(1, "[%s] peek_all_by_id — id 0x%0h not found", name, id);
    end

    if (enable_log)
      $display("[%s] peek_all_by_id: id=0x%0h  found=%0d", name, id, result.size());

    return result;
  endfunction

  // ==========================================================================
  // Helpers
  // ==========================================================================
  function int size();
    return entries.size();
  endfunction

  function bit empty();
    return (entries.size() == 0);
  endfunction

  // ==========================================================================
  // sort — reorder entries by ID age (oldest first, youngest last)
  // ==========================================================================
  function void sort();
    int i;

    // Stable insertion sort with wrap-aware age comparison.
    // Invariant: entries[0:i-1] is sorted from oldest -> youngest.
    for (i = 1; i < entries.size(); i++) begin
      entry_t insert_entry;
      int scan;

      insert_entry = entries[i];
      scan = i - 1;

      // Shift younger entries right until the insertion point is found.
      while (scan >= 0 && is_older(insert_entry.id, entries[scan].id)) begin
        entries[scan + 1] = entries[scan];
        scan--;
      end

      entries[scan + 1] = insert_entry;
    end

    if (enable_log)
      $display("[%s] sort: reordered by age (oldest->youngest), size=%0d",
               name, entries.size());
  endfunction

  // Print all entries (debug utility)
  function void dump();
    $display("[%s] --- dump (%0d entries) ---", name, entries.size());
    foreach (entries[i])
      $display("[%s]   [%0d] id=0x%0h", name, i, entries[i].id);
    $display("[%s] --- statistics ---", name);
    $display("[%s]   stat_push_cnt=%0d", name, stat_push_cnt);
    $display("[%s]   stat_delete_cnt=%0d", name, stat_delete_cnt);
    $display("[%s]   stat_flush_cnt=%0d", name, stat_flush_cnt);
    $display("[%s]   stat_peak_size=%0d", name, stat_peak_size);
    $display("[%s]   stat_wrap_cnt=%0d", name, stat_wrap_cnt);
    $display("[%s] --- end dump ---", name);
  endfunction

endclass
