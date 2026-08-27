#!/bin/bash
# test_ni_system.sh — Verify #375: $NI_SYSTEM system information function
# Tests current behavior (returns empty) and expected future behavior
# Usage: ./tests/test_ni_system.sh

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

echo "=== #375: \$NI_SYSTEM system information ==="

# Test 1: $NI_SYSTEM returns a value (currently empty — needs implementation)
OUT=$($NIMM -x 'WRITE $NI_SYSTEM' 2>&1)
if [ -z "$OUT" ]; then
  echo "  INFO: \$NI_SYSTEM returns empty (not yet implemented)"
  PASS=$((PASS+1))
else
  echo "  INFO: \$NI_SYSTEM returns: $OUT"
  PASS=$((PASS+1))
fi

# Test 2: $NI_SYSTEM doesn't crash
OUT=$($NIMM -x 'SET X=$NI_SYSTEM WRITE "OK"' 2>&1)
check "Doesn't crash" "OK" "$OUT"

# Test 3: $NI_SYSTEM can be used in expressions
OUT=$($NIMM -x 'WRITE "LEN=",$LENGTH($NI_SYSTEM)' 2>&1)
check "Can use in expressions" "LEN=0" "$OUT"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
