#!/bin/bash
# test_bytecode_control.sh — Verify #378: GOTO / DO-label / MERGE in the bytecode VM
# Usage: ./tests/test_bytecode_control.sh

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

# Compare AST vs bytecode output for a routine
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

echo "=== #378: bytecode GOTO / DO-label / MERGE ==="

# GOTO forward jump
cat > /tmp/bcgoto.m <<'EOF'
BCGOTO ;
 SET X=1
 GOTO LBL
 WRITE "unreachable"
 QUIT
LBL ;
 WRITE X
 QUIT
EOF
run_compare "GOTO forward" /tmp/bcgoto.m BCGOTO

# GOTO backward jump (loop via IF guard)
cat > /tmp/bcgoto2.m <<'EOF'
BCGOTO2 ;
 SET I=0
LOOP ;
 SET I=I+1
 IF I<3 GOTO LOOP
 WRITE I
 QUIT
EOF
run_compare "GOTO backward loop" /tmp/bcgoto2.m BCGOTO2

# DO-label within same routine
cat > /tmp/bcdo.m <<'EOF'
BCDO ;
 WRITE "main"
 DO SUB
 WRITE "back"
 QUIT
SUB ;
 WRITE "sub"
 QUIT
EOF
run_compare "DO-label (same routine)" /tmp/bcdo.m BCDO

# Nested DO-label calls
cat > /tmp/bcdo2.m <<'EOF'
BCDO2 ;
 DO ONE
 QUIT
ONE ;
 WRITE "one"
 DO TWO
 WRITE "one-again"
 QUIT
TWO ;
 WRITE "two"
 QUIT
EOF
run_compare "Nested DO-label" /tmp/bcdo2.m BCDO2

# DO-label cross-routine
cat > /tmp/bcdo3a.m <<'EOF'
BCDO3A ;
 WRITE "A"
 DO SUB^BCDO3B
 WRITE "A-again"
 QUIT
EOF
cat > /tmp/bcdo3b.m <<'EOF'
BCDO3B ;
 WRITE "B"
 QUIT
SUB ;
 WRITE "sub"
 QUIT
EOF
ast_out=$("$NIMM" -r /tmp/bcdo3a.m -r /tmp/bcdo3b.m -e 'DO ^BCDO3A' 2>&1)
bc_out=$("$NIMM" --bytecode -r /tmp/bcdo3a.m -r /tmp/bcdo3b.m -e 'DO ^BCDO3A' 2>&1)
if [ "$ast_out" = "$bc_out" ]; then
  echo "  PASS: DO-label cross-routine (AST=BC='$ast_out')"
  PASS=$((PASS+1))
else
  echo "  FAIL: DO-label cross-routine — AST='$ast_out' BC='$bc_out'"
  FAIL=$((FAIL+1))
fi

# MERGE root value copy
cat > /tmp/bcmerge.m <<'EOF'
BCMERGE ;
 SET ^S=5
 MERGE ^D=^S
 WRITE ^D
 QUIT
EOF
run_compare "MERGE root value" /tmp/bcmerge.m BCMERGE

# MERGE local variables
cat > /tmp/bcmerge2.m <<'EOF'
BCMERGE2 ;
 SET A=1,B=2
 MERGE C=A
 WRITE C
 QUIT
EOF
run_compare "MERGE local" /tmp/bcmerge2.m BCMERGE2

rm -f /tmp/bcgoto.m /tmp/bcgoto2.m /tmp/bcdo.m /tmp/bcdo2.m /tmp/bcdo3a.m /tmp/bcdo3b.m /tmp/bcmerge.m /tmp/bcmerge2.m

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
