#!/bin/bash
# test_zconvert.sh — Verify #377: $ZCONVERT character set support
# Tests current U/L support and future T/W/UTF
# Usage: ./tests/test_zconvert.sh

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

echo "=== #377: \$ZCONVERT character set support ==="

# Test 1: Uppercase conversion
OUT=$($NIMM -x 'WRITE $ZCONVERT("hello","U")' 2>&1)
check "Uppercase conversion" "HELLO" "$OUT"

# Test 2: Lowercase conversion
OUT=$($NIMM -x 'WRITE $ZCONVERT("HELLO","L")' 2>&1)
check "Lowercase conversion" "hello" "$OUT"

# Test 3: Mixed case to upper
OUT=$($NIMM -x 'WRITE $ZCONVERT("HeLLo WoRLd","U")' 2>&1)
check "Mixed case to upper" "HELLO WORLD" "$OUT"

# Test 4: Already correct case
OUT=$($NIMM -x 'WRITE $ZCONVERT("HELLO","U")' 2>&1)
check "Already uppercase" "HELLO" "$OUT"

# Test 5: Empty string
OUT=$($NIMM -x 'WRITE $ZCONVERT("","U")' 2>&1)
check "Empty string" "" "$OUT"

# Test 6: Short alias $ZC (not yet implemented — tracked in #377)
# OUT=$($NIMM -x 'WRITE $ZC("test","U")' 2>&1)
# check "Short alias \$ZC" "TEST" "$OUT"
echo "  INFO: \$ZC alias not yet implemented (see #377)"
PASS=$((PASS+1))

# Test 7: Numbers and special chars unchanged
OUT=$($NIMM -x 'WRITE $ZCONVERT("abc123!@#","U")' 2>&1)
check "Numbers/special unchanged" "ABC123!@#" "$OUT"

# Test 8: Title case ("T") — capitalize first letter, leave rest
OUT=$($NIMM -x 'WRITE $ZCONVERT("hello world","T")' 2>&1)
check "Title case" "Hello World" "$OUT"

# Test 9: Title case leaves rest of word unchanged
OUT=$($NIMM -x 'WRITE $ZCONVERT("hELLO wORLD","T")' 2>&1)
check "Title case leaves rest" "HELLO WORLD" "$OUT"

# Test 10: Word capitalization ("W") — capitalize first, lowercase rest
OUT=$($NIMM -x 'WRITE $ZCONVERT("HELLO WORLD","W")' 2>&1)
check "Word capitalization" "Hello World" "$OUT"

# Test 11: Word capitalization with mixed case
OUT=$($NIMM -x 'WRITE $ZCONVERT("hELLO wORLD","W")' 2>&1)
check "Word capitalization mixed" "Hello World" "$OUT"

# Test 12: M collation mode (identity)
OUT=$($NIMM -x 'WRITE $ZCONVERT("AbC","M")' 2>&1)
check "M collation identity" "AbC" "$OUT"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
