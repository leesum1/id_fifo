# Makefile for id_fifo — Verilator simulation

BUILD_DIR  := obj_dir
BUILD_DIR2 := obj_dir_snap

# --- id_fifo testbench ---
TOP1       := id_fifo_tb
SRC1       := id_fifo_tb.sv
BIN1       := $(BUILD_DIR)/V$(TOP1)

# --- sys_reg_snap testbench ---
TOP2       := sys_reg_snap_tb
SRC2       := sys_reg_snap_tb.sv
BIN2       := $(BUILD_DIR2)/V$(TOP2)

VFLAGS1    := --binary --timing -sv -Wall \
              --assert \
              --top-module $(TOP1) \
              -Mdir $(BUILD_DIR)

VFLAGS2    := --binary --timing -sv -Wall \
              --assert \
              --top-module $(TOP2) \
              -Mdir $(BUILD_DIR2)

.PHONY: all sim sim_snap lint lint_id_fifo lint_snap check clean

all: sim sim_snap

lint: lint_id_fifo lint_snap

check: lint

lint_id_fifo:
	verilator --lint-only --timing -sv -Wall $(SRC1)

lint_snap:
	verilator --lint-only --timing -sv -Wall $(SRC2)

sim: $(BIN1)
	@echo "===== Running id_fifo simulation ====="
	./$(BIN1)

sim_snap: $(BIN2)
	@echo "===== Running sys_reg_snap simulation ====="
	./$(BIN2)

$(BIN1): $(SRC1) id_fifo.sv
	verilator $(VFLAGS1) $(SRC1)

$(BIN2): $(SRC2) sys_reg_snap.sv
	verilator $(VFLAGS2) $(SRC2)

clean:
	rm -rf $(BUILD_DIR) $(BUILD_DIR2)
