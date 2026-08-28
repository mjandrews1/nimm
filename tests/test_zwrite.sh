#!/bin/bash
# test_zwrite.sh — Verify #386: ZWRITE / ZKILL
# Usage: ./tests/test_zwrite.sh

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

echo "=== #386: ZWRITE / ZKILL ==="

DB=/tmp/zwrite_test.lmdb
rm -rf "$DB" "$DB-lock" 2>/dev/null

# Test 1: ZWRITE a global with subscripts
OUT=$($NIMM -d $DB -x 'SET ^G("a")=1,^G("a","b")=2,^G("c")=3 ZWRITE ^G' 2>&1)
check "ZWRITE global tree" '^G("a")="1"
^G("a","b")="2"
^G("c")="3"' "$OUT"

# Test 2: ZWRITE a subtree
OUT=$($NIMM -d $DB -x 'ZWRITE ^G("a")' 2>&1)
check "ZWRITE subtree" '^G("a")="1"
^G("a","b")="2"' "$OUT"

# Test 3: ZWRITE a local variable with subscripts
OUT=$($NIMM -d $DB -x 'SET Y(1)=10,Y(2)=20 ZWRITE Y' 2>&1)
check "ZWRITE local with subscripts" 'Y("1")="10"
Y("2")="20"' "$OUT"

# Test 4: ZWRITE a bare local variable
OUT=$($NIMM -d $DB -x 'SET X=5 ZWRITE X' 2>&1)
check "ZWRITE bare local" 'X="5"' "$OUT"

# Test 5: bare ZWRITE lists all local variables
OUT=$($NIMM -d $DB -x 'SET A=1,B=2 ZWRITE' 2>&1)
if echo "$OUT" | grep -q 'A="1"' && echo "$OUT" | grep -q 'B="2"'; then
  echo "  PASS: bare ZWRITE lists locals"
  PASS=$((PASS+1))
else
  echo "  FAIL: bare ZWRITE lists locals"
  echo "    actual: '$OUT'"
  FAIL=$((FAIL+1))
fi

# Test 6: ZKILL removes value but keeps descendants
OUT=$($NIMM -d $DB -x 'ZKILL ^G("a") W $D(^G("a"))," ",$G(^G("a","b"))' 2>&1)
check "ZKILL keeps descendants" "10 2" "$OUT"

# Test 7: ZKILL on a local keeps its subscripts
OUT=$($NIMM -d $DB -x 'SET Z(1)=10 ZKILL Z W $D(Z(1))' 2>&1)
check "ZKILL local keeps subscripts" "1" "$OUT"

rm -rf "$DB" "$DB-lock" 2>/dev/null

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
