#!/usr/bin/env bash
# =============================================================================
# check_tb.sh — Verify testbench files conform to the project template
# =============================================================================
#
# Usage:
#   ./scripts/check_tb.sh [file.sv ...]
#   ./scripts/check_tb.sh                    # checks all tb files under modules/
#
# Exit code: 0 = all pass, 1 = at least one violation
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

errors=0
checked=0

check_file() {
  local f="$1"
  local base
  base="$(basename "$f" .sv)"
  local issues=()

  # 1. Module name must match filename
  if ! grep -qP "^module\s+${base}\b" "$f"; then
    issues+=("module name does not match filename '${base}'")
  fi

  # 2. Must have pass_cnt and fail_cnt
  if ! grep -qP '\bint\s+pass_cnt\s*=' "$f"; then
    issues+=("missing 'int pass_cnt = 0;'")
  fi
  if ! grep -qP '\bint\s+fail_cnt\s*=' "$f"; then
    issues+=("missing 'int fail_cnt = 0;'")
  fi

  # 3. Must have check() function
  if ! grep -qP 'function\s+void\s+check\s*\(' "$f"; then
    issues+=("missing check() function")
  fi

  # 4. Must have [TB_RESULT] output
  if ! grep -qP '\[TB_RESULT\]' "$f"; then
    issues+=("missing [TB_RESULT] output line")
  fi

  # 5. Must call $finish
  if ! grep -qP '\$finish' "$f"; then
    issues+=("missing \$finish call")
  fi

  # 6. Must have exactly one initial block
  local initial_count
  initial_count=$(grep -cP '^\s*initial\b' "$f" || true)
  if [ "$initial_count" -eq 0 ]; then
    issues+=("missing initial block")
  elif [ "$initial_count" -gt 1 ]; then
    issues+=("multiple initial blocks found (expected 1)")
  fi

  # 7. Must have `include for DUT
  if ! grep -qP '`include\s+"' "$f"; then
    issues+=("missing \`include directive for DUT")
  fi

  # 8. Must have endmodule
  if ! grep -qP '^\s*endmodule' "$f"; then
    issues+=("missing endmodule")
  fi

  checked=$((checked + 1))

  if [ ${#issues[@]} -eq 0 ]; then
    printf "  ${GREEN}✓${NC} %s\n" "$f"
  else
    errors=$((errors + 1))
    printf "  ${RED}✗${NC} %s\n" "$f"
    for issue in "${issues[@]}"; do
      printf "    ${YELLOW}→ %s${NC}\n" "$issue"
    done
  fi
}

# Collect files
files=()
if [ $# -gt 0 ]; then
  files=("$@")
else
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find modules -path '*/tb/tb_*.sv' -print0 2>/dev/null | sort -z)
fi

if [ ${#files[@]} -eq 0 ]; then
  echo "No testbench files found."
  exit 1
fi

echo ""
echo "Checking testbench conformance..."
echo "─────────────────────────────────"

for f in "${files[@]}"; do
  check_file "$f"
done

echo "─────────────────────────────────"
printf "Checked: %d   Passed: %d   Failed: %d\n" "$checked" "$((checked - errors))" "$errors"
echo ""

if [ "$errors" -gt 0 ]; then
  printf "${RED}CONFORMANCE CHECK FAILED${NC}\n\n"
  exit 1
else
  printf "${GREEN}ALL FILES CONFORM TO TEMPLATE${NC}\n\n"
  exit 0
fi
