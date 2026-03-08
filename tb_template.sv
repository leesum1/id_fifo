// =============================================================================
// tb_template.sv — Standard testbench template
// =============================================================================
//
// RULES:
//   1. One testbench file = one test (one logical scenario).
//   2. Module name MUST match filename (without .sv extension).
//   3. The file MUST `include the DUT source with a relative path.
//   4. The file MUST define the check() function exactly as shown below.
//   5. The file MUST print a [TB_RESULT] line before $finish:
//        [TB_RESULT] PASS <module_name> <pass_cnt> <fail_cnt>
//        [TB_RESULT] FAIL <module_name> <pass_cnt> <fail_cnt>
//   6. The file MUST call $finish at the end of the initial block.
//   7. The module MUST contain exactly one initial block with all test logic.
//
// USAGE:
//   Copy this template and replace:
//     - <MODULE_NAME>   → your testbench module name (must match filename)
//     - <DUT_INCLUDE>   → relative path to DUT source file
//     - <TEST_BODY>     → your test logic using check() calls
//
// =============================================================================

// --- DUT include ---
// `include "<DUT_INCLUDE>"

// module <MODULE_NAME>;
//
//   int pass_cnt = 0;
//   int fail_cnt = 0;
//
//   function void check(string name, bit condition);
//     if (condition) begin
//       $display("  [PASS] %s", name);
//       pass_cnt++;
//     end else begin
//       $display("  [FAIL] %s", name);
//       fail_cnt++;
//     end
//   endfunction
//
//   initial begin
//     $display("\n=== %m ===");
//
//     // <TEST_BODY>
//
//     // --- Result summary (DO NOT MODIFY) ---
//     if (fail_cnt == 0)
//       $display("[TB_RESULT] PASS %m %0d %0d", pass_cnt, fail_cnt);
//     else
//       $display("[TB_RESULT] FAIL %m %0d %0d", pass_cnt, fail_cnt);
//     $finish;
//   end
//
// endmodule
