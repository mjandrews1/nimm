#!/bin/bash
# test_zallocate.sh — Verify #379: ZALLOCATE/ZDEALLOCATE functionality
# Usage: ./tests/test_zallocate.sh

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

echo "=== #379: ZALLOCATE/ZDEALLOCATE ==="

DB=/tmp/zalloc_test.lmdb
rm -rf "$DB" "$DB-lock" 2>/dev/null

# Test 1: ZALLOCATE sets lock variable to 1
cat > /tmp/zalloc1.m << 'EOF'
ZALLOC1 ;
ZALLOCATE ^LOCK1
WRITE $G(^LOCK1)
QUIT
EOF
OUT=$($NIMM -d $DB -r /tmp/zalloc1.m -e 'DO ^ZALLOC1' 2>&1)
check "ZALLOCATE sets to 1" "1" "$OUT"

# Test 2: ZDEALLOCATE sets lock variable to 0
cat > /tmp/zalloc2.m << 'EOF'
ZALLOC2 ;
ZALLOCATE ^LOCK2
ZDEALLOCATE ^LOCK2
WRITE $G(^LOCK2)
QUIT
EOF
OUT=$($NIMM -d $DB -r /tmp/zalloc2.m -e 'DO ^ZALLOC2' 2>&1)
check "ZDEALLOCATE sets to 0" "0" "$OUT"

# Test 3: Timeout parameter is accepted and ignored
cat > /tmp/zalloc3.m << 'EOF'
ZALLOC3 ;
ZALLOCATE ^LOCK3:5
WRITE $G(^LOCK3)
QUIT
EOF
OUT=$($NIMM -d $DB -r /tmp/zalloc3.m -e 'DO ^ZALLOC3' 2>&1)
check "Timeout ignored, still locks" "1" "$OUT"

# Test 4: Multiple locks
cat > /tmp/zalloc4.m << 'EOF'
ZALLOC4 ;
ZALLOCATE ^LOCKA,^LOCKB
WRITE $G(^LOCKA),$G(^LOCKB)
QUIT
EOF
OUT=$($NIMM -d $DB -r /tmp/zalloc4.m -e 'DO ^ZALLOC4' 2>&1)
check "Multiple ZALLOCATE" "11" "$OUT"

# Test 5: Subscripted lock
cat > /tmp/zalloc5.m << 'EOF'
ZALLOC5 ;
ZALLOCATE ^LOCK5(1,2)
WRITE $G(^LOCK5(1,2))
ZDEALLOCATE ^LOCK5(1,2)
WRITE $G(^LOCK5(1,2))
QUIT
EOF
OUT=$($NIMM -d $DB -r /tmp/zalloc5.m -e 'DO ^ZALLOC5' 2>&1)
check "Subscripted lock/unlock" "10" "$OUT"

rm -rf "$DB" "$DB-lock" 2>/dev/null

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
