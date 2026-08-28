#!/bin/bash
# test_scripting.sh — Verify #368: dogfood scripting affordances
# ($ZFILE, $ZARG argv, reliable exit codes, $ZSYSTEM error surfacing)
# Usage: ./tests/test_scripting.sh

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

echo "=== #368: scripting affordances ==="

# --- $ZFILE: existence + size ---
OUT=$($NIMM -x 'W $ZFILE("/etc/hosts","exists")," ",$ZFILE("/nonexistent","exists")' 2>&1)
check "\$ZFILE exists" "1 0" "$OUT"

OUT=$($NIMM -x 'W $ZFILE("/nonexistent")' 2>&1)
check "\$ZFILE size of missing file is empty" "" "$OUT"

SIZE=$($NIMM -x 'W $ZFILE("/etc/hosts")' 2>&1)
if [[ "$SIZE" =~ ^[0-9]+$ ]] && [ "$SIZE" -gt 0 ] 2>/dev/null; then
  echo "  PASS: \$ZFILE returns file size ($SIZE)"
  PASS=$((PASS+1))
else
  echo "  FAIL: \$ZFILE returns file size (got '$SIZE')"
  FAIL=$((FAIL+1))
fi

# --- $ZARG: argv access ---
OUT=$($NIMM -x 'W $ZARG(1)," ",$ZARG(2)," ",$ZARG(3)' alpha beta 2>&1)
check "\$ZARG argv" "alpha beta " "$OUT"

# --- exit codes: QUIT value -> process exit status ---
RC=0
$NIMM -x 'QUIT 7' >/dev/null 2>&1 || RC=$?
check "QUIT 7 -> exit 7" "7" "$RC"

RC=0
$NIMM -x 'W "ok" QUIT 0' >/dev/null 2>&1 || RC=$?
check "QUIT 0 -> exit 0" "0" "$RC"

# --- $ZSYSTEM / ZSYSTEM error surfacing ---
OUT=$($NIMM -x 'ZSYSTEM "true" W $TEST ZSYSTEM "false" W $TEST' 2>&1)
check "ZSYSTEM sets \$TEST" "10" "$OUT"

OUT=$($NIMM -x 'W $ZSYSTEM("echo hello")," ",$ZSTATUS' 2>&1)
check "\$ZSYSTEM exit code + \$ZSTATUS output" "0 hello" "$OUT"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
