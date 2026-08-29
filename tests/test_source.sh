#!/bin/bash
# test_source.sh — Verify #389 Phase C: routine & source introspection
# ZPRINT whole routine / labels, ZROUTINES, ZDUMP bytecode disassembly
# Usage: ./tests/test_source.sh

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

check_contains() {
  local label="$1" needle="$2" actual="$3"
  if echo "$actual" | grep -q "$needle"; then
    echo "  PASS: $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label (expected '$needle' in output)"
    echo "    got: $actual"
    FAIL=$((FAIL+1))
  fi
}

echo "=== #389 Phase C: routine & source introspection ==="

cat > /tmp/src1.m <<'EOF'
HELLO ;
 WRITE "hi",!
 DO SUB
 QUIT
SUB ;
 WRITE "sub"
 QUIT
EOF

# ZPRINT ^ROUTINE prints the whole routine (raw source, indentation preserved)
OUT=$($NIMM -r /tmp/src1.m -x 'ZPRINT ^SRC1' 2>&1)
check "ZPRINT ^ROUTINE" 'HELLO ;
 WRITE "hi",!
 DO SUB
 QUIT
SUB ;
 WRITE "sub"
 QUIT' "$OUT"

# ZPRINT bare prints the current routine
OUT=$($NIMM -r /tmp/src1.m -x 'ZPRINT' 2>&1)
check_contains "ZPRINT bare (current routine)" 'HELLO ;' "$OUT"

# ZPRINT label prints from the label line to the end of the routine
OUT=$($NIMM -r /tmp/src1.m -x 'ZPRINT SUB' 2>&1)
check "ZPRINT label" 'SUB ;
 WRITE "sub"
 QUIT' "$OUT"

# ZROUTINES lists loaded routines with label/line counts
OUT=$($NIMM -r /tmp/src1.m -x 'ZROUTINES' 2>&1)
check "ZROUTINES lists routines" 'Routines:
  SRC1 (2 labels, 7 lines)' "$OUT"

# ZROUTINES routine lists only real labels (no command keywords)
OUT=$($NIMM -r /tmp/src1.m -x 'ZROUTINES SRC1' 2>&1)
check "ZROUTINES labels (no command keywords)" 'SRC1 labels:
  HELLO (line 0)
  SUB (line 4)' "$OUT"

# ZDUMP disassembles bytecode
OUT=$($NIMM -r /tmp/src1.m -x 'ZDUMP SRC1' 2>&1)
check_contains "ZDUMP shows opcodes" 'opPushConst "hi"' "$OUT"
check_contains "ZDUMP shows source line" 'WRITE "hi",!' "$OUT"
check_contains "ZDUMP shows opCallLabel" 'opCallLabel' "$OUT"

# Routine execution still works after the parseLabels fix
OUT=$($NIMM -r /tmp/src1.m -x 'DO HELLO' 2>&1)
check "routine still executes" 'hi
sub' "$OUT"

rm -f /tmp/src1.m

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
