#!/bin/bash
# test_bytecode_kill.sh — Verify #378 (subset): KILL + BREAK in the bytecode VM
# Usage: ./tests/test_bytecode_kill.sh

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

echo "=== #378: bytecode VM KILL + BREAK ==="

# KILL a variable, preserve another (bytecode VM via routine DO)
cat > /tmp/bckill1.m << 'EOF'
BCKILL1 ;
 SET A=1,B=2
 KILL A
 WRITE B
 QUIT
EOF
check "KILL var (bytecode)" "2" "$($NIMM --bytecode -r /tmp/bckill1.m -e 'DO ^BCKILL1' 2>&1)"

# KILL a variable, then reading it is empty (bytecode VM)
cat > /tmp/bckill2.m << 'EOF'
BCKILL2 ;
 SET A=1
 KILL A
 WRITE A
 QUIT
EOF
check "KILL var then read (bytecode)" "" "$($NIMM --bytecode -r /tmp/bckill2.m -e 'DO ^BCKILL2' 2>&1)"

# KILL without args (kill all locals) in bytecode VM
cat > /tmp/bckill3.m << 'EOF'
BCKILL3 ;
 SET A=1
 KILL
 WRITE A
 QUIT
EOF
check "KILL all locals (bytecode)" "" "$($NIMM --bytecode -r /tmp/bckill3.m -e 'DO ^BCKILL3' 2>&1)"

# BREAK halts the bytecode VM (no subsequent WRITE)
cat > /tmp/bcbreak.m << 'EOF'
BCBREAK ;
 WRITE "before"
 BREAK
 WRITE "after"
 QUIT
EOF
check "BREAK halts (bytecode)" "before" "$($NIMM --bytecode -r /tmp/bcbreak.m -e 'DO ^BCBREAK' 2>&1)"

# AST path unaffected (default mode)
check "KILL var (AST)" "2" "$($NIMM -r /tmp/bckill1.m -e 'DO ^BCKILL1' 2>&1)"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
