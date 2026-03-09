// =============================================================================
// tb_random_stress.sv — Test: Randomized stress test with golden model
// =============================================================================
// Executes 200+ random operations with monotonic ID allocation to validate:
//   - Push with random payloads
//   - Delete_by_id with random existing IDs
//   - Flush_younger and flush_younger_or_eq with random boundaries
//   - Peek_by_id for random existing IDs
// Uses fixed seed for reproducibility. Maintains golden model to verify
// queue state after every operation.
// =============================================================================

`include "../src/id_fifo.sv"

typedef struct packed {
  logic [15:0] value;
  logic [7:0]  tag;
} payload_t;

module tb_random_stress;

  localparam ID_WIDTH = 4;
  localparam int DEFAULT_SEED = 42;
  localparam int NUM_OPERATIONS = 250;
  localparam int unsigned HALF_SPACE = (1 << (ID_WIDTH-1));
  
  typedef logic [ID_WIDTH-1:0] id_t;
  typedef enum {OP_PUSH, OP_DELETE, OP_FLUSH_Y, OP_FLUSH_YE, OP_PEEK} op_t;
  
  typedef struct packed {
    int unsigned abs_id;
    id_t id;
    payload_t payload;
  } golden_entry_t;

  int pass_cnt = 0;
  int fail_cnt = 0;

  function void check(string name, bit condition);
    if (condition) begin
      $display("  [PASS] %s", name);
      pass_cnt++;
    end else begin
      $display("  [FAIL] %s", name);
      fail_cnt++;
    end
  endfunction

  function payload_t make_payload(logic [15:0] v, logic [7:0] t);
    payload_t p;
    p.value = v;
    p.tag   = t;
    return p;
  endfunction

  function automatic id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) new_fifo(string inst_name, bit allow_dup = 0);
    id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) f;
    f = new(inst_name);
    f.enable_log = 1;
    f.allow_dup  = allow_dup;
    return f;
  endfunction

  // Golden model helper: find entry index by ID
  function automatic int golden_find_index(golden_entry_t q[$], id_t target_id);
    for (int i = 0; i < q.size(); i++) begin
      if (q[i].id == target_id) return i;
    end
    return -1;
  endfunction

  // Golden model helper: remove younger entries
  function automatic void golden_flush_younger(ref golden_entry_t q[$], id_t boundary_id);
    int i = 0;
    while (i < q.size()) begin
      if (id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(q[i].id, boundary_id)) begin
        q.delete(i);
      end else begin
        i++;
      end
    end
  endfunction

  // Golden model helper: remove younger-or-equal entries
  function automatic void golden_flush_younger_or_eq(ref golden_entry_t q[$], id_t boundary_id);
    int i = 0;
    while (i < q.size()) begin
      if (id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::is_younger(q[i].id, boundary_id) || q[i].id == boundary_id) begin
        q.delete(i);
      end else begin
        i++;
      end
    end
  endfunction

  initial begin
    id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH))::entry_t e;
    id_fifo #(.T(payload_t), .ID_WIDTH(ID_WIDTH)) fifo;
    golden_entry_t golden_q[$];
    id_t next_id;
    int unsigned next_abs_id;
    op_t op;
    id_t target_id;
    int idx;
    int op_counts[5];  // Track operation distribution
    payload_t temp_payload;

    $display("\n=== %m ===");
    $display("SEED=%0d", DEFAULT_SEED);
    
    // Initialize random seed
    /* verilator lint_off WIDTH */
    void'($urandom(DEFAULT_SEED));
    /* verilator lint_on WIDTH */

    fifo = new_fifo("random_stress_fifo");
    next_abs_id = 0;
    next_id = id_t'(next_abs_id);
    
    // Initialize operation counters
    for (int i = 0; i < 5; i++) op_counts[i] = 0;

    // Execute random operations
    for (int i = 0; i < NUM_OPERATIONS; i++) begin
      // Choose random operation
      op = op_t'($urandom_range(0, 4));
      
      // If queue is empty, only push is valid
      if (golden_q.size() == 0 && op != OP_PUSH) begin
        op = OP_PUSH;
      end

      // Enforce half-space monotonic ID constraint using absolute ID span:
      // Block push whenever (next_abs_id - oldest_abs_id) would reach HALF_SPACE.
      if (op == OP_PUSH && golden_q.size() > 0) begin
        int unsigned oldest_abs_id;
        int unsigned span;
        oldest_abs_id = golden_q[0].abs_id;
        span = next_abs_id - oldest_abs_id;
        if (span >= HALF_SPACE) begin
          op = op_t'($urandom_range(1, 4));  // Choose delete/flush/peek instead
        end
      end

      op_counts[op]++;

      case (op)
        OP_PUSH: begin
          // Push to DUT with random payload
          /* verilator lint_off WIDTH */
          temp_payload = make_payload($urandom, $urandom);
          /* verilator lint_on WIDTH */
          fifo.push(next_id, temp_payload);
          
          // Push to golden model (we only need to track ID for validation)
          temp_payload = make_payload(0, 0);
          golden_q.push_back('{abs_id: next_abs_id, id: next_id, payload: temp_payload});
          
          // Increment absolute ID; truncated ID is derived from lower bits.
          next_abs_id++;
          next_id = id_t'(next_abs_id);
        end

        OP_DELETE: begin
          // Choose random existing ID
          if (golden_q.size() > 0) begin
            idx = $urandom_range(0, golden_q.size() - 1);
            target_id = golden_q[idx].id;
            
            // Delete from DUT
            fifo.delete_by_id(target_id);
            
            // Delete from golden model
            golden_q.delete(idx);
          end
        end

        OP_FLUSH_Y: begin
          // Choose random boundary ID from existing entries
          if (golden_q.size() > 0) begin
            idx = $urandom_range(0, golden_q.size() - 1);
            target_id = golden_q[idx].id;
            
            // Flush from DUT
            fifo.flush_younger(target_id);
            
            // Flush from golden model
            golden_flush_younger(golden_q, target_id);
          end
        end

        OP_FLUSH_YE: begin
          // Choose random boundary ID from existing entries
          if (golden_q.size() > 0) begin
            idx = $urandom_range(0, golden_q.size() - 1);
            target_id = golden_q[idx].id;
            
            // Flush from DUT
            fifo.flush_younger_or_eq(target_id);
            
            // Flush from golden model
            golden_flush_younger_or_eq(golden_q, target_id);
          end
        end

        OP_PEEK: begin
          // Peek random existing ID and verify it exists
          if (golden_q.size() > 0) begin
            idx = $urandom_range(0, golden_q.size() - 1);
            target_id = golden_q[idx].id;
            
            // Peek from DUT
            e = fifo.peek_by_id(target_id);
            
            // Verify ID matches (payload is random, we just verify entry exists)
            check($sformatf("op%0d: peek_by_id(%0d) returns correct ID", i, target_id),
                  e.id == target_id);
          end
        end
      endcase

      // Verify size matches after every operation
      check($sformatf("op%0d: size matches (DUT=%0d, golden=%0d)", i, fifo.size(), golden_q.size()),
            fifo.size() == golden_q.size());
      
      // Spot-check oldest entry if queue is non-empty
      if (golden_q.size() > 0) begin
        e = fifo.peek_oldest();
        check($sformatf("op%0d: oldest ID matches (DUT=%0d, golden=%0d)", i, e.id, golden_q[0].id),
              e.id == golden_q[0].id);
      end
    end

    // Print operation distribution
    $display("\n[Operation Distribution]");
    $display("  PUSH:          %0d (%.1f%%)", op_counts[0], 100.0 * op_counts[0] / NUM_OPERATIONS);
    $display("  DELETE:        %0d (%.1f%%)", op_counts[1], 100.0 * op_counts[1] / NUM_OPERATIONS);
    $display("  FLUSH_YOUNGER: %0d (%.1f%%)", op_counts[2], 100.0 * op_counts[2] / NUM_OPERATIONS);
    $display("  FLUSH_YE:      %0d (%.1f%%)", op_counts[3], 100.0 * op_counts[3] / NUM_OPERATIONS);
    $display("  PEEK:          %0d (%.1f%%)", op_counts[4], 100.0 * op_counts[4] / NUM_OPERATIONS);
    $display("  Total checks:  %0d", pass_cnt + fail_cnt);

    // --- Result summary (DO NOT MODIFY) ---
    if (fail_cnt == 0)
      $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
    else
      $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
    $finish;
  end

endmodule
