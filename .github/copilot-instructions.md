# Copilot Instructions

## Build & Test

This project uses **Verilator** for simulation and linting.

```bash
make all        # Build and run both testbenches
make sim        # id_fifo testbench only
make sim_snap   # sys_reg_snap testbench only
make lint       # Lint id_fifo_tb.sv only
make lint_snap  # Lint sys_reg_snap_tb.sv only
make clean      # Remove build artifacts
```

There is no single-test runner; each testbench runs all its tests sequentially in one `initial` block.

## Architecture

### `id_fifo.sv`
Parameterized SV class (`T`, `ID_WIDTH`). Dynamic storage is a queue (`entries[$]`), index 0 = oldest. The MSB of each ID is a "wrap bit" used by the static `is_younger()` for wrap-around-safe comparisons.

### `sys_reg_snap.sv`
SV class (`ID_WIDTH`, `REG_WIDTH`, `ADDR_WIDTH`) that tracks in-flight SYS_REG writes and answers "what value would instruction RID X have seen?" It maintains a flat `records[$]` queue of `{rid, reg_addr, value}` and inlines its own `is_younger()` (identical logic to `id_fifo`). Does **not** depend on `id_fifo` at runtime.

- **`record_update(rid, reg_addr, value)`** — call when an MSR instruction executes
- **`get_value_at(query_rid, reg_addr, value) → bit`** — returns 1 + oldest-visible value; 0 = no history, use external wire
- **`get_snapshot_at(query_rid) → snap_entry_t[$]`** — all registers with visible history at that RID
- **`retire(retire_rid)`** — purge records with RID ≤ retire_rid (committed instructions)

### Testbenches
- `id_fifo_tb.sv` — `include`s `id_fifo.sv` directly
- `sys_reg_snap_tb.sv` — `include`s `sys_reg_snap.sv` directly; `id_fifo.sv` not included

## Key Conventions

- **Wrap-around ID comparison**: `is_younger(a, b)` splits each ID into a wrap bit (MSB) and a value (remaining bits). Same wrap bit → larger value is younger; different wrap bit → smaller value is younger (it has wrapped). Both classes implement this identically.
- **Testbench pattern**: Tests use a `check(name, condition)` helper that increments `pass_cnt`/`fail_cnt` and prints `[PASS]`/`[FAIL]`.
- **Optional runtime checks**: Both classes have `enable_log` and `enable_assert` flags. `id_fifo` additionally has `allow_dup`.
- **Inclusion model**: Testbenches use `` `include `` — there are no packages or separate compilation units.
- **Verilator limitation**: Do not use `id_fifo<T>` where `T` is a struct defined inside another class — Verilator fails to generate correct C++ for nested parameterized struct types. `sys_reg_snap` avoids this by managing its own queue directly.
