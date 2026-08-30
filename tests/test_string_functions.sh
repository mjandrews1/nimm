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

# $GET (naked variable reference — mirrors functions_more.dfy)
check "\$GET default" 'd' 'K ^G W $GET(^G,"d")'
check "\$GET value" 'hi' 'K ^G S ^G="hi" W $GET(^G,"d")'

# $CASE (first matching value; :default is the trailing arg)
check "\$CASE match" '2' 'W $CASE("b","a":"1","b":"2",:"z")'
check "\$CASE default" 'z' 'W $CASE("c","a":"1","b":"2",:"z")'
check "\$CASE no match" '' 'W $CASE("c","a":"1","b":"2")'

# $GET string-name (parser/eval fix: eStr now names the variable)
check "\$GET string name" 'd' 'K ^G W $GET("^G","d")'

# $SELECT (first truthy condition)
check "\$SELECT first truthy" 'yes' 'W $SELECT(0:"no",1:"yes")'
check "\$SELECT none truthy" '' 'W $SELECT(0:"no")'

# $QLENGTH (subscript count)
check "\$QLENGTH" '3' 'W $QL("X(a,b,c)")'

# $REVERSE (character reversal)
check "\$REVERSE" 'cba' 'W $REVERSE("abc")'
check "\$REVERSE empty" '' 'W $REVERSE("")'

# $PIECE (delimiter split)
check "\$PIECE 1" 'a' 'W $P("a^b^c","^",1)'
check "\$PIECE 2" 'b' 'W $P("a^b^c","^",2)'
check "\$PIECE 3" 'c' 'W $P("a^b^c","^",3)'
check "\$PIECE beyond" '' 'W $P("a^b^c","^",4)'
check "\$PIECE no delim" 'abc' 'W $P("abc","^",1)'

echo "  $PASS checks passed"
echo "String function tests passed!"
