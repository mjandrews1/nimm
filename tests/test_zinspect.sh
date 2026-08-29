#!/bin/bash
# test_zinspect.sh — Verify #389 Phase A: ZINSPECT + globals.listLocals
# Usage: ./tests/test_zinspect.sh

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

check_contains() {
  local label="$1" needle="$2" actual="$3"
  if echo "$actual" | grep -q "$needle"; then
    echo "  PASS: $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label (expected '$needle' in output, got '$actual')"
    FAIL=$((FAIL+1))
  fi
}

echo "=== #389 Phase A: ZINSPECT ==="

# ZINSPECT a single local variable
OUT=$($NIMM -x 'SET X=42 ZINSPECT X' 2>&1)
check "ZINSPECT local" 'X="42"' "$OUT"

# ZINSPECT bare lists all locals in the current scope
OUT=$($NIMM -x 'SET A=1,B=2 ZINSPECT' 2>&1)
check "ZINSPECT bare lists locals" 'A="1"
B="2"' "$OUT"

# ZINSPECT a subscripted local node
OUT=$($NIMM -x 'SET Y(1)=10,Y(2)=20 ZINSPECT Y(1)' 2>&1)
check "ZINSPECT subscripted" 'Y("1")="10"' "$OUT"

# ZINSPECT a global with a value
OUT=$($NIMM -x 'SET ^G("k")="v" ZINSPECT ^G("k")' 2>&1)
check "ZINSPECT global node" '^G("k")="v"' "$OUT"

# ZINSPECT an undefined variable shows UNDEFINED
OUT=$($NIMM -x 'ZINSPECT NOTDEF' 2>&1)
check "ZINSPECT undefined" 'NOTDEF=UNDEFINED' "$OUT"

# ZWRITE bare still works after listLocals refactor
OUT=$($NIMM -x 'SET A=1,B=2 ZWRITE' 2>&1)
check "ZWRITE bare (regression)" 'A="1"
B="2"' "$OUT"

# ZWRITE with subscripted local (regression)
OUT=$($NIMM -x 'SET Y(1)=10,Y(2)=20 ZWRITE Y' 2>&1)
check "ZWRITE subscripted (regression)" 'Y("1")="10"
Y("2")="20"' "$OUT"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
