#!/bin/bash
# test_mode_gates.sh — Verify #385: -m mode gates (strict/rsm/nimm)
# Usage: ./tests/test_mode_gates.sh

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

check_fails() {
  local label="$1" actual="$2"
  if [ -n "$actual" ]; then
    echo "  PASS: $label (error: $actual)"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label (expected an error, got none)"
    FAIL=$((FAIL+1))
  fi
}

echo "=== #385: -m mode gates ==="

# Strict mode rejects lowercase identifiers
ERR=$($NIMM -m strict -x 'set x=5 write x' 2>&1 || true)
check_fails "strict rejects lowercase" "$ERR"

# Strict mode rejects nimm extensions ($NI_*)
OUT=$($NIMM -m strict -x 'WRITE $NI_UUID' 2>&1)
check "strict gates \$NI_UUID" "" "$OUT"

# Strict mode still accepts uppercase + standard functions
OUT=$($NIMM -m strict -x 'SET X=5 WRITE X' 2>&1)
check "strict accepts uppercase" "5" "$OUT"
OUT=$($NIMM -m strict -x 'WRITE $LENGTH("hello")' 2>&1)
check "strict accepts standard functions" "5" "$OUT"

# RSM mode allows lowercase but gates extensions
OUT=$($NIMM -m rsm -x 'set x=5 write x' 2>&1)
check "rsm allows lowercase" "5" "$OUT"
OUT=$($NIMM -m rsm -x 'WRITE $NI_UUID' 2>&1)
check "rsm gates \$NI_UUID" "" "$OUT"

# nimm (default) allows lowercase + extensions
OUT=$($NIMM -x 'set x=5 write x' 2>&1)
check "nimm allows lowercase" "5" "$OUT"
OUT=$($NIMM -x 'WRITE $LENGTH($NI_UUID)' 2>&1)
if [[ "$OUT" == "36" ]]; then
  echo "  PASS: nimm allows \$NI_UUID (length 36)"
  PASS=$((PASS+1))
else
  echo "  FAIL: nimm allows \$NI_UUID (got '$OUT')"
  FAIL=$((FAIL+1))
fi

# Explicit -m nimm behaves like the default
OUT=$($NIMM -m nimm -x 'set x=5 write x' 2>&1)
check "-m nimm allows lowercase" "5" "$OUT"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
