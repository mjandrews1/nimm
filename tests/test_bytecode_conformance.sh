#!/usr/bin/env bash
# test_bytecode_conformance.sh — Test bytecode VM against conformance suite
# Compares bytecode output with AST output for key test cases
set -euo pipefail

NIMM="${1:-./bin/nimm}"
PASS=0
FAIL=0

run_compare() {
  local desc="$1" code="$2"
  local ast_out bc_out
  ast_out=$("$NIMM" -x "$code" 2>&1)
  bc_out=$("$NIMM" --bytecode -x "$code" 2>&1)
  if [ "$ast_out" = "$bc_out" ]; then
    echo "  ✓ $desc"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $desc — AST='$ast_out' BC='$bc_out'"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Bytecode Conformance Tests ==="

# Arithmetic
run_compare "1+2" 'W 1+2'
run_compare "3*4" 'W 3*4'
run_compare "10-3" 'W 10-3'
run_compare "7/2" 'W 7/2'
run_compare "2**3" 'W 2**3'
run_compare "7#3" 'W 7#3'

# Variables
run_compare "SET+GET" 'SET X=42 W X'
run_compare "Global SET+GET" 'SET ^G=99 W ^G'

# String operations
run_compare "Concat" 'W "hello"_"world"'
run_compare "Length" 'W $L("hello")'

# Control flow
run_compare "IF true" 'IF 1 W "yes"'
run_compare "IF false" 'IF 0 W "no"'

# FOR loop
run_compare "FOR 1:1:3" 'FOR I=1:1:3 W I'

# Transactions
run_compare "TSTART/TCOMMIT" 'KILL ^Tx TSTART SET ^Tx=1 TCOMMIT W ^Tx'
run_compare "TSTART/TROLLBACK" 'KILL ^Tx SET ^Tx=99 TSTART SET ^Tx=1 TROLLBACK W ^Tx'

# Functions
run_compare "\$LENGTH" 'W $L("abc")'
run_compare "\$EXTRACT" 'W $E("hello",2,4)'
run_compare "\$PIECE" 'W $P("a^b^c","^",2)'

# Subscripts (compile ≡ AST: opPushGlobalSub / opSetGlobalSub)
run_compare "Subscript SET+GET" 'S ^G("a","b")=7 W ^G("a","b")'
run_compare "Nested subscript" 'S ^H("x")=^H("x")+1 W ^H("x")'

# Nested arithmetic (compile ≡ AST: opBinop chains)
run_compare "Nested (1+2)*3" 'W (1+2)*3'
run_compare "Nested 1+(2*3)" 'W 1+(2*3)'

# Postconditionals (compile ≡ AST: opJumpIf* control flow)
run_compare "Postconditional WRITE" 'S X=5 W:X>3 "big"'
run_compare "Postconditional SET" 'S X=0 S:X=0 X=9 W X'

# Multiple statements in one line (statement sequencing)
run_compare "Statement sequence" 'S A=1 S B=2 W A+B'

# Unary operators (eNeg/ePos regression: stack-order bug in #431)
run_compare "Unary minus" 'S X=3 W -X'
run_compare "Unary minus expr" 'W -(2+3)'
run_compare "Unary plus coercion" 'S X="2E3" W +X'
run_compare "Unary plus canonical" 'S X="01.50" W +X'

# IF/ELSE (else-body skip regression: was running else even when true)
run_compare "IF/ELSE true" 'IF 1 W "yes" ELSE W "no"'
run_compare "IF/ELSE false" 'IF 0 W "yes" ELSE W "no"'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
