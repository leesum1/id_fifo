# Copilot Instructions

## Project Structure

```
modules/
  <module>/
    src/<module>.sv     # Source files
    tb/tb_<test>.sv     # One test per file (follows tb_template.sv)
scripts/
  run_tests.sh          # Build & run tests, show summary
  check_tb.sh           # Verify tb files conform to template
tb_template.sv          # Canonical testbench template
Makefile                # Extensible per-module targets
```

### Adding a New Module

1. Create `modules/<name>/src/` and `modules/<name>/tb/`
2. Append `<name>` to the `MODULES` list in `Makefile`
3. Write testbenches following `tb_template.sv`

## Build & Test

This project uses **Verilator** for simulation and linting.

```bash
make test               # Run ALL tests across all modules
make test-id_fifo       # Run tests for id_fifo only
make test-sys_reg_snap  # Run tests for sys_reg_snap only
make lint               # Lint ALL modules
make lint-id_fifo       # Lint id_fifo only
make lint-sys_reg_snap  # Lint sys_reg_snap only
make check-tb           # Verify all tb files conform to template
make clean              # Remove build artifacts
```

Each testbench file contains exactly **one test**. The test runner (`scripts/run_tests.sh`) builds and runs each tb file individually and parses `[TB_RESULT]` output lines for the summary.

## Architecture

### `id_fifo.sv`
Parameterized SV class (`T`, `ID_WIDTH`). Dynamic storage is a queue (`entries[$]`), index 0 = oldest. The MSB of each ID is a "wrap bit" used by the static `is_younger()` for wrap-around-safe comparisons.

### `sys_reg_snap.sv`
SV class (`ID_WIDTH`, `REG_WIDTH`, `ADDR_WIDTH`) that tracks in-flight SYS_REG writes and answers "what value would instruction RID X have seen?" It maintains a flat `records[$]` queue of `{rid, reg_addr, value}` and inlines its own `is_younger()` (identical logic to `id_fifo`). Does **not** depend on `id_fifo` at runtime.

- **`record_update(rid, reg_addr, value)`** -- call when an MSR instruction executes
- **`get_value_at(query_rid, reg_addr, value) -> bit`** -- returns 1 + oldest-visible value; 0 = no history, use external wire
- **`get_snapshot_at(query_rid) -> snap_entry_t[$]`** -- all registers with visible history at that RID
- **`retire(retire_rid)`** -- purge records with RID <= retire_rid (committed instructions)

## Key Conventions

- **Wrap-around ID comparison**: `is_younger(a, b)` splits each ID into a wrap bit (MSB) and a value (remaining bits). Same wrap bit -> larger value is younger; different wrap bit -> smaller value is younger (it has wrapped). Both classes implement this identically.
- **Testbench template**: All tb files must follow `tb_template.sv`. Use `make check-tb` to verify conformance. Key rules:
  - Module name must match filename (e.g., `tb_foo.sv` -> `module tb_foo;`)
  - Declare `int pass_cnt = 0;` and `int fail_cnt = 0;`
  - Define `function void check(string test_name, bit condition);`
  - Output `[TB_RESULT] PASS|FAIL %m <pass_cnt> <fail_cnt>` before `$finish`
  - Use `` `include "../src/<dut>.sv" `` to include the DUT
  - Single `initial` block per file
- **Optional runtime checks**: Both classes have `enable_log` and `enable_assert` flags. `id_fifo` additionally has `allow_dup`.
- **Inclusion model**: Testbenches use `` `include `` -- there are no packages or separate compilation units.
- **Verilator limitation**: Do not use `id_fifo<T>` where `T` is a struct defined inside another class -- Verilator fails to generate correct C++ for nested parameterized struct types. `sys_reg_snap` avoids this by managing its own queue directly.
