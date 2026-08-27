#!/bin/bash
# test_bareword_error.sh — Verify #369: Unknown bareword raises error
# Usage: ./tests/test_bareword_error.sh

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

echo "=== #369: Unknown bareword raises error ==="

# Unknown bareword in -e should fail with error
OUT=$($NIMM -e 'FOOBAR' 2>&1 || true)
echo "$OUT" | grep -q "Unknown command"
check "Unknown bareword → error message" "1" "1"

# Exit code should be non-zero
$NIMM -e 'FOOBAR' 2>/dev/null && RC=0 || RC=$?
check "Unknown bareword → non-zero exit" "1" "$((RC != 0 ? 1 : 0))"

# Known commands should still work
OUT=$($NIMM -e 'WRITE "hello"' 2>&1)
check "Known command WRITE works" "hello" "$OUT"

OUT=$($NIMM -e 'SET X=42 WRITE X' 2>&1)
check "Known command SET works" "42" "$OUT"

# Single-letter commands should work
OUT=$($NIMM -e 'S X=1 W X' 2>&1)
check "Single-letter S/W work" "1" "$OUT"

# Unknown single-letter should fail
OUT=$($NIMM -e 'Z' 2>&1 || true)
echo "$OUT" | grep -q "Unknown command"
check "Unknown single-letter → error" "1" "1"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
