# =============================================================================
# Makefile — Verilator testbench build system
# =============================================================================
#
# To add a new module:
#   1. Create modules/<name>/src/ and modules/<name>/tb/
#   2. Add <name> to MODULES below
#   3. That's it — all tb_*.sv files are auto-discovered
#
# Targets:
#   make test                    — run ALL module tests
#   make test-<module>           — run tests for one module
#   make lint                    — lint ALL modules
#   make lint-<module>           — lint one module
#   make check-tb                — verify tb files conform to template
#   make clean                   — remove build artifacts
# =============================================================================

# ── Module registry (add new modules here) ──────────────────────────────────
MODULES := id_fifo sys_reg_snap

# ── Directories ─────────────────────────────────────────────────────────────
BUILD_ROOT := build

# ── Verilator flags ─────────────────────────────────────────────────────────
VFLAGS := --binary --timing -sv -Wall --assert

# ── Phony targets ───────────────────────────────────────────────────────────
.PHONY: all test lint check-tb clean help \
        $(addprefix test-,$(MODULES)) \
        $(addprefix lint-,$(MODULES))

all: test

help:
	@echo "Usage:"
	@echo "  make test              Run all tests"
	@echo "  make test-<module>     Run tests for a module ($(MODULES))"
	@echo "  make lint              Lint all modules"
	@echo "  make lint-<module>     Lint a module"
	@echo "  make check-tb          Check tb files against template"
	@echo "  make clean             Remove build artifacts"

# ── Test targets ────────────────────────────────────────────────────────────
test:
	@./scripts/run_tests.sh

define MODULE_RULES
test-$(1):
	@./scripts/run_tests.sh $(1)

lint-$(1):
	@echo "===== Linting $(1) ====="
	@for f in modules/$(1)/tb/tb_*.sv; do \
		[ -f "$$$$f" ] || continue; \
		tb_base=$$$$(basename "$$$$f" .sv); \
		echo "  lint $$$$tb_base"; \
		verilator --lint-only --timing -sv -Wall \
			--top-module "$$$$tb_base" \
			-Imodules/$(1)/src \
			"$$$$f"; \
	done
	@echo ""
endef

$(foreach m,$(MODULES),$(eval $(call MODULE_RULES,$(m))))

lint: $(addprefix lint-,$(MODULES))

# ── Conformance check ──────────────────────────────────────────────────────
check-tb:
	@./scripts/check_tb.sh

# ── Clean ───────────────────────────────────────────────────────────────────
clean:
	rm -rf $(BUILD_ROOT)
