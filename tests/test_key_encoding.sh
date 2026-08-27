#!/bin/bash
# test_key_encoding.sh — Verify #356: LMDB key encoding with M-collation
# Tests that numeric subscripts sort correctly per M standard
# Usage: ./tests/test_key_encoding.sh

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

echo "=== #356: LMDB key encoding + M-collation ==="

# Clean up any previous test databases
rm -rf /tmp/keyenc_test/ 2>/dev/null || true

# Test 1: $ORDER with numeric subscripts (the core bug)
cat > /tmp/keyenc1.m << 'EOF'
KEYENC1 ;
SET ^X("1")="a"
SET ^X("10")="b"
SET ^X("2")="c"
SET ^X("20")="d"
SET ^X("3")="e"
SET R=""
SET K=""
FOR  SET K=$ORDER(^X(K)) QUIT:K=""  SET R=R_K_","
WRITE R
QUIT
EOF
OUT=$($NIMM -d /tmp/keyenc_test.lmdb -r /tmp/keyenc1.m -x 'DO ^KEYENC1' 2>&1)
# M collation: numeric before string, numeric by value
# Expected order: 1, 2, 3, 10, 20
check "Numeric subscript order" "1,2,3,10,20," "$OUT"

# Test 2: $ORDER with mixed types
cat > /tmp/keyenc2.m << 'EOF'
KEYENC2 ;
SET ^Y("abc")="x"
SET ^Y("1")="y"
SET ^Y("def")="z"
SET ^Y("2")="w"
SET R=""
SET K=""
FOR  SET K=$ORDER(^Y(K)) QUIT:K=""  SET R=R_K_","
WRITE R
QUIT
EOF
OUT=$($NIMM -d /tmp/keyenc_test2.lmdb -r /tmp/keyenc2.m -x 'DO ^KEYENC2' 2>&1)
# M collation: numbers before strings, then strings alphabetically
# Expected: 1, 2, abc, def
check "Mixed type order" "1,2,abc,def," "$OUT"

# Test 3: Empty key sorts first
cat > /tmp/keyenc3.m << 'EOF'
KEYENC3 ;
SET ^Z("hello")="a"
SET ^Z("world")="b"
SET ^Z("")="c"
SET R=""
SET K=""
FOR  SET K=$ORDER(^Z(K)) QUIT:K=""  SET R=R_K_","
WRITE R
QUIT
EOF
OUT=$($NIMM -d /tmp/keyenc_test3.lmdb -r /tmp/keyenc3.m -x 'DO ^KEYENC3' 2>&1)
# Empty key should sort first
check "Empty key sorts first" ",hello,world," "$OUT"

# Test 4: $ORDER backward
cat > /tmp/keyenc4.m << 'EOF'
KEYENC4 ;
SET ^W("1")="a"
SET ^W("10")="b"
SET ^W("2")="c"
SET R=""
SET K=""
FOR  SET K=$ORDER(^W(K),-1) QUIT:K=""  SET R=R_K_","
WRITE R
QUIT
EOF
OUT=$($NIMM -d /tmp/keyenc_test4.lmdb -r /tmp/keyenc4.m -x 'DO ^KEYENC4' 2>&1)
# Reverse M collation: strings desc, then numbers desc
check "Backward order" "2,10,1," "$OUT"

# Test 5: Numeric subscripts in nested globals
cat > /tmp/keyenc5.m << 'EOF'
KEYENC5 ;
SET ^N(1,10)="a"
SET ^N(1,2)="b"
SET ^N(2,1)="c"
SET R=""
SET K=""
FOR  SET K=$ORDER(^N(K)) QUIT:K=""  DO
. SET J=""
. FOR  SET J=$ORDER(^N(K,J)) QUIT:J=""  SET R=R_K_":"_J_","
WRITE R
QUIT
EOF
OUT=$($NIMM -d /tmp/keyenc_test5.lmdb -r /tmp/keyenc5.m -x 'DO ^KEYENC5' 2>&1)
# Nested numeric: 1:2, 1:10, 2:1 (numeric by value)
check "Nested numeric subscripts" "1:2,1:10,2:1," "$OUT"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
