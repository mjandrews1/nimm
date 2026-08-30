#!/bin/bash
# test_string_functions.sh — string-function property test
# (mirrors formal/string_functions.dfy).
#
# Usage: bash tests/test_string_functions.sh [nimm-binary]
set -euo pipefail

NIMM="${1:-./bin/nimm}"
PASS=0

check() {
    local desc="$1" expected="$2" code="$3"
    local out
    out=$("$NIMM" -x "$code" 2>&1)
    if [ "$out" = "$expected" ]; then
        echo "  ✓ $desc"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $desc — expected '$expected', got '$out'"
        exit 1
    fi
}

echo "String function property test (mirrors formal/string_functions.dfy)..."

# $LENGTH
check "\$LENGTH" '5' 'W $L("hello")'

# $EXTRACT (bounds clamping)
check "\$EXTRACT" 'ell' 'W $E("hello",2,4)'
check "\$EXTRACT first char" 'h' 'W $E("hello",1,1)'
check "\$EXTRACT clamp first" 'hel' 'W $E("hello",0,3)'
check "\$EXTRACT clamp last" 'hello' 'W $E("hello",1,99)'
check "\$EXTRACT empty range" '' 'W $E("hello",4,2)'
check "\$EXTRACT past end" '' 'W $E("hello",6,7)'

# $FIND (1-based end of match, 0 if absent)
check "\$FIND" '5' 'W $F("hello","ell")'
check "\$FIND single" '3' 'W $F("abc","b")'
check "\$FIND absent" '0' 'W $F("hello","xyz")'

# $TRANSLATE (character substitution)
check "\$TRANSLATE" 'xbc' 'W $TR("abc","a","x")'
check "\$TRANSLATE pair" 'xyc' 'W $TR("abc","ab","xy")'
check "\$TRANSLATE repeated" 'heLLo' 'W $TR("hello","l","L")'

echo "  $PASS checks passed"
echo "String function tests passed!"
