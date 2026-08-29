#!/bin/bash
# test_bytecode_fallback.sh — Verify #402: bytecode AST fallback (no silent-wrong)
# XECUTE, $PIECE/$EXTRACT SET, LOCK, indirection, pattern, $ functions
# Usage: ./tests/test_bytecode_fallback.sh

set -euo pipefail
NIMM="${1:-./bin/nimm}"
PASS=0; FAIL=0

run_compare() {
  local desc="$1" file="$2" entry="$3"
  local ast_out bc_out
  ast_out=$("$NIMM" -r "$file" -e "DO ^$entry" 2>&1)
  bc_out=$("$NIMM" --bytecode -r "$file" -e "DO ^$entry" 2>&1)
  if [ "$ast_out" = "$bc_out" ]; then
    echo "  PASS: $desc (AST=BC='$ast_out')"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc — AST='$ast_out' BC='$bc_out'"
    FAIL=$((FAIL+1))
  fi
}

echo "=== #402: bytecode AST fallback (no silent-wrong) ==="

# $ intrinsic functions ($LENGTH/$PIECE/$DATA) fall back to AST
cat > /tmp/bcfn.m <<'EOF'
BCFN ;
 WRITE $LENGTH("abc"),"|"
 WRITE $PIECE("a,b,c",",",2),"|"
 WRITE $DATA(^G),"|"
 QUIT
EOF
run_compare "\$ functions" /tmp/bcfn.m BCFN

# XECUTE, SET $PIECE, LOCK, indirection, pattern match
cat > /tmp/bcfall.m <<'EOF'
BCFALL ;
 XECUTE "SET Y=5"
 WRITE Y,"|"
 SET A="a,b,c"
 SET $PIECE(A,",",2)="x"
 WRITE A,"|"
 LOCK +^LL
 WRITE $DATA(^$LOCK("LL")),"|"
 SET X="Y"
 SET Y=7
 WRITE @X,"|"
 WRITE "abc"?2A,"|"
 QUIT
EOF
run_compare "XECUTE/\$PIECE/LOCK/@/pattern" /tmp/bcfall.m BCFALL

rm -f /tmp/bcfn.m /tmp/bcfall.m

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
