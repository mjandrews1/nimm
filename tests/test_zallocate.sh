#!/bin/bash
# test_zallocate.sh — Verify #379: ZALLOCATE/ZDEALLOCATE functionality
# Tests current no-op behavior and expected future behavior
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

# Test 1: ZALLOCATE doesn't crash (currently no-op)
cat > /tmp/zalloc1.m << 'EOF'
ZALLOC1 ;
ZALLOCATE ^LOCK1
WRITE "OK"
ZDEALLOCATE ^LOCK1
QUIT
EOF
OUT=$($NIMM -r /tmp/zalloc1.m -x 'DO ^ZALLOC1' 2>&1)
check "ZALLOCATE doesn't crash" "OK" "$OUT"

# Test 2: ZALLOCATE with timeout doesn't crash
cat > /tmp/zalloc2.m << 'EOF'
ZALLOC2 ;
ZALLOCATE ^LOCK2:5
WRITE "OK"
ZDEALLOCATE ^LOCK2
QUIT
EOF
OUT=$($NIMM -r /tmp/zalloc2.m -x 'DO ^ZALLOC2' 2>&1)
check "ZALLOCATE with timeout" "OK" "$OUT"

# Test 3: Multiple ZALLOCATE doesn't crash
cat > /tmp/zalloc3.m << 'EOF'
ZALLOC3 ;
ZALLOCATE ^LOCKA,^LOCKB,^LOCKC
WRITE "OK"
ZDEALLOCATE ^LOCKA,^LOCKB,^LOCKC
QUIT
EOF
OUT=$($NIMM -r /tmp/zalloc3.m -x 'DO ^ZALLOC3' 2>&1)
check "Multiple ZALLOCATE" "OK" "$OUT"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
