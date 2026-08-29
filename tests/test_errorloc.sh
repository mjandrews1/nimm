#!/bin/bash
# test_errorloc.sh — Verify #389 Phase E: $ZPOS + self-describing errors with source position
# Usage: ./tests/test_errorloc.sh

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
    echo "  FAIL: $label (expected '$needle' in output)"
    echo "    got: $actual"
    FAIL=$((FAIL+1))
  fi
}

echo "=== #389 Phase E: \$ZPOS + error source positions ==="

# $ZPOS returns routine:line (1-based) in a routine
printf 'MAIN\n W $ZPOS,!\n D SUB\n Q\nSUB\n W $ZPOS,!\n Q\n' > /tmp/errloc1.m
OUT=$($NIMM -r /tmp/errloc1.m -x 'DO MAIN' 2>&1)
check "\$ZPOS returns routine:line" 'ERRLOC1:2
ERRLOC1:6' "$OUT"

# $ZPOS is empty at top level (no routine)
OUT=$($NIMM -x 'WRITE $ZPOS' 2>&1)
check "\$ZPOS empty at top level" "" "$OUT"

# Parse error inside a routine carries routine:line + source snippet
printf 'MAIN\n SET X=1\n set Y=2\n QUIT\n' > /tmp/errloc2.m
OUT=$($NIMM -m strict -r /tmp/errloc2.m -x 'DO MAIN' 2>&1 || true)
check_contains "error carries position" 'at ERRLOC2:3' "$OUT"
check_contains "error carries snippet" 'set Y=2' "$OUT"

# Error position survives a nested DO (points at the failing line's routine)
printf 'MAIN\n D SUB\n Q\nSUB\n SET Z=1\n set W=2\n QUIT\n' > /tmp/errloc3.m
OUT=$($NIMM -m strict -r /tmp/errloc3.m -x 'DO MAIN' 2>&1 || true)
check_contains "nested DO error position" 'ERRLOC3:6' "$OUT"

rm -f /tmp/errloc1.m /tmp/errloc2.m /tmp/errloc3.m

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
