#!/bin/bash
# test_pemdas.sh — Verify #373: optional PEMDAS mode via --pemdas
# Usage: ./tests/test_pemdas.sh

set -euo pipefail
NIMM="${1:-./bin/nimm}"
PASS=0; FAIL=0

check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label (expected '$expected', got '$actual')"
    FAIL=$((FAIL+1))
  fi
}

echo "=== #373: PEMDAS mode ==="

# Default (M standard): strict left-to-right
check "default 2+3*4" "20" "$($NIMM -x 'W 2+3*4' 2>&1)"
check "default 10-2*3" "24" "$($NIMM -x 'W 10-2*3' 2>&1)"
check "default 1+2+3" "6" "$($NIMM -x 'W 1+2+3' 2>&1)"

# --pemdas: standard math precedence
check "pemdas 2+3*4" "14" "$($NIMM --pemdas -x 'W 2+3*4' 2>&1)"
check "pemdas 10-2*3" "4" "$($NIMM --pemdas -x 'W 10-2*3' 2>&1)"
check "pemdas 1+2+3" "6" "$($NIMM --pemdas -x 'W 1+2+3' 2>&1)"
check "pemdas 2*3+4" "10" "$($NIMM --pemdas -x 'W 2*3+4' 2>&1)"
check "pemdas 2**3*2" "16" "$($NIMM --pemdas -x 'W 2**3*2' 2>&1)"
check "pemdas 10/2+3" "8" "$($NIMM --pemdas -x 'W 10/2+3' 2>&1)"

# --pemdas with variables (not constant-folded)
check "pemdas A+B*C" "14" "$($NIMM --pemdas -x 'S A=2,B=3,C=4 W A+B*C' 2>&1)"

# --pemdas with parentheses
check "pemdas (2+3)*4" "20" "$($NIMM --pemdas -x 'W (2+3)*4' 2>&1)"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
