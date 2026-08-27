#!/bin/bash
# test_for_zeof.sh — Verify #357: FOR loop + QUIT:$ZEOF terminates correctly
# Usage: ./tests/test_for_zeof.sh

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

echo "=== #357: FOR loop + QUIT:\$ZEOF ==="

# Create test file
echo -e "line1\nline2\nline3" > /tmp/test_for_zeof.txt

# Test 1: Individual reads work (baseline)
OUT=$($NIMM -x 'OPEN 1:("/tmp/test_for_zeof.txt":"READ") USE 1 READ l1 USE 0 WRITE l1 USE 1 READ l2 USE 0 WRITE l2 USE 1 READ l3 USE 0 WRITE l3 USE 1 READ l4 USE 0 WRITE "ZEOF=",$ZEOF CLOSE 1 USE 0' 2>&1)
check "Individual READ + ZEOF" "line1line2line3ZEOF=1" "$OUT"

# Test 2: FOR loop with QUIT:$ZEOF (the bug — should not hang)
cat > /tmp/forzeof_a.m << 'EOF'
FORZEOF_A ;
OPEN 1:("/tmp/test_for_zeof.txt":"READ") USE 1
FOR  READ line USE 0 QUIT:$ZEOF  WRITE line,! USE 1
CLOSE 1 USE 0
QUIT
EOF
OUT=$($NIMM -r /tmp/forzeof_a.m -x 'DO ^FORZEOF_A' 2>&1)
EXPECTED="line1
line2
line3"
check "FOR loop + QUIT:\$ZEOF (file routine)" "$EXPECTED" "$OUT"

# Test 3: Empty file (EOF immediately)
echo -n "" > /tmp/test_for_zeof_empty.txt
cat > /tmp/forzeof_b.m << 'EOF'
FORZEOF_B ;
OPEN 1:("/tmp/test_for_zeof_empty.txt":"READ") USE 1
FOR  READ line USE 0 QUIT:$ZEOF  WRITE line,! USE 1
CLOSE 1 USE 0
QUIT
EOF
OUT=$($NIMM -r /tmp/forzeof_b.m -x 'DO ^FORZEOF_B' 2>&1)
check "Empty file FOR+ZEOF" "" "$OUT"

# Test 4: Single line file
echo "only" > /tmp/test_for_zeof_one.txt
cat > /tmp/forzeof_c.m << 'EOF'
FORZEOF_C ;
OPEN 1:("/tmp/test_for_zeof_one.txt":"READ") USE 1
FOR  READ line USE 0 QUIT:$ZEOF  WRITE line,! USE 1
CLOSE 1 USE 0
QUIT
EOF
OUT=$($NIMM -r /tmp/forzeof_c.m -x 'DO ^FORZEOF_C' 2>&1)
check "Single line FOR+ZEOF" "only" "$OUT"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
