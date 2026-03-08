#!/usr/bin/env bash
# =============================================================================
# run_tests.sh — Build & run testbenches, summarize results
# =============================================================================
#
# Usage:
#   ./scripts/run_tests.sh [module ...]
#   ./scripts/run_tests.sh                   # run all modules
#   ./scripts/run_tests.sh id_fifo           # run id_fifo tests only
#
# =============================================================================
set -uo pipefail

PROJ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${PROJ_ROOT}/build"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

total_pass=0
total_fail=0
total_error=0
results=()

run_tb() {
  local module="$1"
  local tb_file="$2"
  local tb_base
  tb_base="$(basename "$tb_file" .sv)"
  local build_dir="${BUILD_ROOT}/${module}/${tb_base}"
  local bin="${build_dir}/V${tb_base}"

  local src_dir="${PROJ_ROOT}/modules/${module}/src"

  # Build
  mkdir -p "$build_dir"
  if ! verilator --binary --timing -sv -Wall --assert \
       --top-module "$tb_base" \
       -Mdir "$build_dir" \
       -I"$src_dir" \
       "$tb_file" 2>"${build_dir}/build.log"; then
    printf "  ${RED}BUILD FAIL${NC}  %s/%s\n" "$module" "$tb_base"
    results+=("BUILD_FAIL|${module}|${tb_base}|0|0")
    total_error=$((total_error + 1))
    return
  fi

  # Run
  local output
  if ! output=$("$bin" 2>&1); then
    # Verilator returns non-zero on $finish, check if TB_RESULT is present
    if ! echo "$output" | grep -q '\[TB_RESULT\]'; then
      printf "  ${RED}RUN FAIL${NC}    %s/%s\n" "$module" "$tb_base"
      results+=("RUN_FAIL|${module}|${tb_base}|0|0")
      total_error=$((total_error + 1))
      return
    fi
  fi

  # Parse result
  local result_line
  result_line=$(echo "$output" | grep '\[TB_RESULT\]' | tail -1)

  if echo "$result_line" | grep -q '\[TB_RESULT\] PASS'; then
    local p f
    p=$(echo "$result_line" | awk '{print $(NF-1)}')
    f=$(echo "$result_line" | awk '{print $NF}')
    printf "  ${GREEN}PASS${NC}        %s/%s  (%s checks)\n" "$module" "$tb_base" "$p"
    results+=("PASS|${module}|${tb_base}|${p}|${f}")
    total_pass=$((total_pass + 1))
  elif echo "$result_line" | grep -q '\[TB_RESULT\] FAIL'; then
    local p f
    p=$(echo "$result_line" | awk '{print $(NF-1)}')
    f=$(echo "$result_line" | awk '{print $NF}')
    printf "  ${RED}FAIL${NC}        %s/%s  (%s passed, %s failed)\n" "$module" "$tb_base" "$p" "$f"
    results+=("FAIL|${module}|${tb_base}|${p}|${f}")
    total_fail=$((total_fail + 1))
  else
    printf "  ${YELLOW}UNKNOWN${NC}     %s/%s\n" "$module" "$tb_base"
    results+=("UNKNOWN|${module}|${tb_base}|0|0")
    total_error=$((total_error + 1))
  fi
}

# Determine modules to test
modules=()
if [ $# -gt 0 ]; then
  modules=("$@")
else
  for d in "${PROJ_ROOT}"/modules/*/; do
    [ -d "${d}tb" ] && modules+=("$(basename "$d")")
  done
fi

if [ ${#modules[@]} -eq 0 ]; then
  echo "No modules found."
  exit 1
fi

echo ""
printf "${BOLD}Running Tests${NC}\n"
echo "════════════════════════════════════════════════════"

for module in "${modules[@]}"; do
  local_tb_dir="${PROJ_ROOT}/modules/${module}/tb"
  if [ ! -d "$local_tb_dir" ]; then
    printf "  ${YELLOW}SKIP${NC}        %s (no tb/ directory)\n" "$module"
    continue
  fi

  printf "\n${CYAN}[%s]${NC}\n" "$module"

  for tb_file in "${local_tb_dir}"/tb_*.sv; do
    [ -f "$tb_file" ] || continue
    run_tb "$module" "$tb_file"
  done
done

echo ""
echo "════════════════════════════════════════════════════"
printf "${BOLD}Summary${NC}\n"
echo "────────────────────────────────────────────────────"

total=$((total_pass + total_fail + total_error))
printf "  Total:  %d\n" "$total"
printf "  ${GREEN}Passed: %d${NC}\n" "$total_pass"

if [ "$total_fail" -gt 0 ]; then
  printf "  ${RED}Failed: %d${NC}\n" "$total_fail"
fi
if [ "$total_error" -gt 0 ]; then
  printf "  ${YELLOW}Errors: %d${NC}\n" "$total_error"
fi

echo "────────────────────────────────────────────────────"

if [ "$total_fail" -eq 0 ] && [ "$total_error" -eq 0 ]; then
  printf "${GREEN}${BOLD}ALL TESTS PASSED${NC}\n"
  echo ""
  exit 0
else
  printf "${RED}${BOLD}SOME TESTS FAILED${NC}\n"
  echo ""
  # List failures
  for r in "${results[@]}"; do
    IFS='|' read -r status mod tb p f <<< "$r"
    if [ "$status" != "PASS" ]; then
      printf "  ${RED}%s${NC}  %s/%s\n" "$status" "$mod" "$tb"
    fi
  done
  echo ""
  exit 1
fi
