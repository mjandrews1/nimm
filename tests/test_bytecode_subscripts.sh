#!/bin/bash
# test_bytecode_subscripts.sh — Verify #394: bytecode subscripted vars + postconditionals
# Compares AST vs bytecode output for the previously-broken cases.
# Usage: ./tests/test_bytecode_subscripts.sh

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

echo "=== #394: bytecode subscripted variables + postconditionals ==="

# Subscripted global SET/GET, multi-subscript, variable subscript, local
cat > /tmp/bcsub.m <<'EOF'
BCSUB ;
 SET ^S("a")=1
 WRITE ^S("a"),"|"
 SET ^M(1,2)="v"
 WRITE ^M(1,2),"|"
 SET I=2
 SET ^S(I)="w"
 WRITE ^S(I),"|"
 SET A("x")=5
 WRITE A("x"),"|"
 QUIT
EOF
run_compare "subscripted SET/GET" /tmp/bcsub.m BCSUB

# Postconditional WRITE (skip when false, emit when true)
cat > /tmp/bcpost.m <<'EOF'
BCPOST ;
 SET X=0
 WRITE:X>0 "yes",!
 SET X=1
 WRITE:X>0 "yes",!
 QUIT
EOF
run_compare "postconditional WRITE" /tmp/bcpost.m BCPOST

# Postconditional GOTO loop
cat > /tmp/bcloop.m <<'EOF'
BCLOOP ;
 SET I=0
LOOP ;
 SET I=I+1
 GOTO:I<3 LOOP
 WRITE I
 QUIT
EOF
run_compare "postconditional GOTO loop" /tmp/bcloop.m BCLOOP

# WRITE with newline + multiple values (ordering)
cat > /tmp/bcwrite.m <<'EOF'
BCWRITE ;
 SET A=1,B=2
 WRITE A,":",B,!
 QUIT
EOF
run_compare "WRITE multi-value + newline" /tmp/bcwrite.m BCWRITE

rm -f /tmp/bcsub.m /tmp/bcpost.m /tmp/bcloop.m /tmp/bcwrite.m

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
