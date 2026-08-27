#!/bin/bash
# test_do_args.sh — Verify #370: DO label^routine passes arguments
# Usage: ./tests/test_do_args.sh

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

echo "=== #370: DO args binding ==="

# Create test routine
cat > /tmp/args_test.m << 'MFILE'
ENTRY ; no-arg entry
WRITE "no-arg"
QUIT

WITHARG(X) ; single-arg entry
WRITE "arg:",X
QUIT

WITH2(A,B) ; two-arg entry
WRITE "a:",A," b:",B
QUIT

FUNC(X) ; extrinsic function
QUIT "func:"_X
MFILE

# Test 1: No-arg DO
OUT=$($NIMM -r /tmp/args_test.m -x 'DO ENTRY^args_test' 2>&1)
check "DO ENTRY (no args)" "no-arg" "$OUT"

# Test 2: Single-arg DO
OUT=$($NIMM -r /tmp/args_test.m -x 'DO WITHARG^args_test("P1")' 2>&1)
check "DO WITHARG (1 arg)" "arg:P1" "$OUT"

# Test 3: Two-arg DO
OUT=$($NIMM -r /tmp/args_test.m -x 'DO WITH2^args_test("X1","Y2")' 2>&1)
check "DO WITH2 (2 args)" "a:X1 b:Y2" "$OUT"

# Test 4: Same-routine DO with args
cat > /tmp/sameroutine.m << 'MFILE'
MAIN ; 
DO HELLO("world")
QUIT
HELLO(MSG) ;
WRITE "hello:",MSG
QUIT
MFILE
OUT=$($NIMM -r /tmp/sameroutine.m -x 'DO ^sameroutine' 2>&1)
check "Same-routine DO with args" "hello:world" "$OUT"

# Test 5: DO with variable args
OUT=$($NIMM -r /tmp/args_test.m -x 'SET V="val1" DO WITHARG^args_test(V)' 2>&1)
check "DO with variable arg" "arg:val1" "$OUT"

# Test 6: DO without explicit args (old behavior)
OUT=$($NIMM -r /tmp/args_test.m -x 'DO ENTRY^args_test' 2>&1)
check "DO without args still works" "no-arg" "$OUT"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
