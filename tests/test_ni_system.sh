#!/bin/bash
# test_ni_system.sh — Verify #375: $NI_SYSTEM system information function
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

check_nonempty() {
  local label="$1" actual="$2"
  if [ -n "$actual" ]; then
    echo "  PASS: $label ($actual)"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label (expected non-empty, got empty)"
    FAIL=$((FAIL+1))
  fi
}

check_int() {
  local label="$1" actual="$2"
  if [[ "$actual" =~ ^[0-9]+$ ]] && [ "$actual" -gt 0 ] 2>/dev/null; then
    echo "  PASS: $label ($actual)"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label (expected positive integer, got '$actual')"
    FAIL=$((FAIL+1))
  fi
}

echo "=== #375: \$NI_SYSTEM system information ==="

# Test 1: hostname
HOST=$($NIMM -x 'WRITE $NI_SYSTEM("hostname")' 2>&1)
check_nonempty "hostname" "$HOST"

# Test 2: pid is a positive integer
PID=$($NIMM -x 'WRITE $NI_SYSTEM("pid")' 2>&1)
check_int "pid" "$PID"

# Test 3: uid
UIDV=$($NIMM -x 'WRITE $NI_SYSTEM("uid")' 2>&1)
check_nonempty "uid" "$UIDV"

# Test 4: cwd
CWD=$($NIMM -x 'WRITE $NI_SYSTEM("cwd")' 2>&1)
check_nonempty "cwd" "$CWD"

# Test 5: arch
ARCH=$($NIMM -x 'WRITE $NI_SYSTEM("arch")' 2>&1)
check_nonempty "arch" "$ARCH"

# Test 6: os
OS=$($NIMM -x 'WRITE $NI_SYSTEM("os")' 2>&1)
check_nonempty "os" "$OS"

# Test 7: env:PATH is non-empty
ENV=$($NIMM -x 'WRITE $NI_SYSTEM("env:PATH")' 2>&1)
check_nonempty "env:PATH" "$ENV"

# Test 8: unknown subscript returns empty
UNK=$($NIMM -x 'WRITE $NI_SYSTEM("does_not_exist")' 2>&1)
check "unknown subscript empty" "" "$UNK"

# Test 9: works in expressions
LEN=$($NIMM -x 'WRITE $LENGTH($NI_SYSTEM("hostname"))' 2>&1)
if [[ "$LEN" =~ ^[0-9]+$ ]] && [ "$LEN" -gt 0 ] 2>/dev/null; then
  echo "  PASS: usable in expressions (len=$LEN)"
  PASS=$((PASS+1))
else
  echo "  FAIL: usable in expressions (got '$LEN')"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
