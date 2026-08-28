#!/bin/bash
# test_zmisc.sh — Verify #374: Priority-1 $Z functions
# ($ZCHAR, $ZCHANGE, $ZSTRIPCOMMAND, $ZIO, $ZLEVEL, $ZREFERENCE)
# Usage: ./tests/test_zmisc.sh

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

echo "=== #374: Priority-1 \$Z functions ==="

# $ZCHAR — alias for $CHAR
check "\$ZCHAR alias" "Hi" "$($NIMM -x 'W $ZCHAR(72,105)' 2>&1)"

# $ZCHANGE — replace all occurrences
check "\$ZCHANGE replace" "hell0 w0rld" "$($NIMM -x 'W $ZCHANGE("hello world","o","0")' 2>&1)"
check "\$ZCHANGE empty old is identity" "abc" "$($NIMM -x 'W $ZCHANGE("abc","","x")' 2>&1)"

# $ZSTRIPCOMMAND — strip a leading command keyword
check "\$ZSTRIPCOMMAND SET" "X=1" "$($NIMM -x 'W $ZSTRIPCOMMAND("SET X=1")' 2>&1)"
check "\$ZSTRIPCOMMAND WRITE" "5" "$($NIMM -x 'W $ZSTRIPCOMMAND("WRITE 5")' 2>&1)"
check "\$ZSTRIPCOMMAND no keyword" "X=1" "$($NIMM -x 'W $ZSTRIPCOMMAND("X=1")' 2>&1)"

# $ZIO — current I/O device (principal is "0")
check "\$ZIO" "0" "$($NIMM -x 'W $ZIO' 2>&1)"

# $ZLEVEL — DO/XECUTE stack depth
cat > /tmp/zlvl.m << 'EOF'
ZLVL ;
 WRITE $ZLEVEL
 DO SUB
 QUIT
SUB ;
 WRITE $ZLEVEL
 QUIT
EOF
check "\$ZLEVEL reflects DO depth" "12" "$($NIMM -r /tmp/zlvl.m -e 'DO ^ZLVL' 2>&1)"

# $ZREFERENCE — current global reference
check "\$ZREFERENCE" "" "$($NIMM -x 'W $ZREFERENCE' 2>&1)"

# $ZVERSION (pre-existing special var)
check "\$ZVERSION non-empty" "nimm 0.1.8" "$($NIMM -x 'W $ZVERSION' 2>&1)"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
