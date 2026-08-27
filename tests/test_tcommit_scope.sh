#!/bin/bash
# test_tcommit_scope.sh — Verify #371: TCOMMIT doesn't destroy NEW'd locals
# Usage: ./tests/test_tcommit_scope.sh

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

echo "=== #371: TCOMMIT + NEW scope preservation ==="

# Test 1: TCOMMIT preserves locals — values inside NEW scope
cat > /tmp/tc1.m << 'MFILE'
TC1 ;
SET A=1
NEW B
SET B=2
TSTART
SET A=10
SET B=20
TCOMMIT
WRITE "A:",A," B:",B
QUIT
MFILE
OUT=$($NIMM -r /tmp/tc1.m -x 'DO ^TC1' 2>&1)
check "Inside NEW scope: A=10, B=20" "A:10 B:20" "$OUT"

# Test 2: After DO/QUIT, NEW'd var restored, non-NEW'd persists
cat > /tmp/tc2.m << 'MFILE'
TC2 ;
SET A=1
SET B=2
DO SUB
WRITE "A:",A," B:",B
QUIT
SUB ;
NEW B
SET A=10
SET B=20
QUIT
MFILE
OUT=$($NIMM -r /tmp/tc2.m -x 'DO ^TC2' 2>&1)
check "After DO: A=10, B=2 (restored)" "A:10 B:2" "$OUT"

# Test 3: NEW A,C — C is NEW'd, B is not
cat > /tmp/tc3.m << 'MFILE'
TC3 ;
SET A=1
SET B=2
SET C=3
DO SUB
WRITE "A:",A," B:",B," C:",C
QUIT
SUB ;
NEW A,C
SET A=10
SET B=20
SET C=30
QUIT
MFILE
OUT=$($NIMM -r /tmp/tc3.m -x 'DO ^TC3' 2>&1)
check "After DO: A=1, B=20, C=3" "A:1 B:20 C:3" "$OUT"

# Test 4: Sequential NEW A (C not NEW'd — should persist)
cat > /tmp/tc4.m << 'MFILE'
TC4 ;
SET A=1
SET B=2
SET C=3
DO SUB
WRITE "A:",A," B:",B," C:",C
QUIT
SUB ;
NEW A
SET A=10
SET B=20
SET C=30
QUIT
MFILE
OUT=$($NIMM -r /tmp/tc4.m -x 'DO ^TC4' 2>&1)
check "After DO: A=1, B=20, C=30 (C not NEW'd)" "A:1 B:20 C:30" "$OUT"

# Test 5: TCOMMIT with FOR loop counter
cat > /tmp/tc5.m << 'MFILE'
TC5 ;
NEW CNT
SET CNT=0
TSTART
FOR I=1:1:3  SET CNT=CNT+1
TCOMMIT
WRITE "CNT:",CNT
QUIT
MFILE
OUT=$($NIMM -r /tmp/tc5.m -x 'DO ^TC5' 2>&1)
check "TCOMMIT+FOR loop counter" "CNT:3" "$OUT"

# Test 6: Non-NEW'd write persists across DO/QUIT
cat > /tmp/tc6.m << 'MFILE'
TC6 ;
SET X=1
DO SUB
WRITE "X:",X
QUIT
SUB ;
SET X=99
QUIT
MFILE
OUT=$($NIMM -r /tmp/tc6.m -x 'DO ^TC6' 2>&1)
check "Non-NEW'd write persists across DO/QUIT" "X:99" "$OUT"

# Test 7: NEW'd var in sub doesn't leak
cat > /tmp/tc7.m << 'MFILE'
TC7 ;
SET X=1
DO SUB
WRITE "X:",X
QUIT
SUB ;
NEW X
SET X=99
QUIT
MFILE
OUT=$($NIMM -r /tmp/tc7.m -x 'DO ^TC7' 2>&1)
check "NEW'd var in sub doesn't leak" "X:1" "$OUT"

# Test 8: Single-letter NEW (C) — the original parser bug
cat > /tmp/tc8.m << 'MFILE'
TC8 ;
SET C=5
DO SUB
WRITE "C:",C
QUIT
SUB ;
NEW C
SET C=99
QUIT
MFILE
OUT=$($NIMM -r /tmp/tc8.m -x 'DO ^TC8' 2>&1)
check "Single-letter NEW C (restored to 5)" "C:5" "$OUT"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
