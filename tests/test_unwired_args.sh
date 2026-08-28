#!/bin/bash
# test_unwired_args.sh — Verify #387: command arguments wired in or dropped
# Usage: ./tests/test_unwired_args.sh

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

echo "=== #387: unwired command arguments ==="

# ZQUIT val now sets the top-level quit value (exit code)
rc=0
$NIMM -x 'ZQUIT 7' >/dev/null 2>&1 || rc=$?
check "ZQUIT val sets exit code" "7" "$rc"

rc=0
$NIMM -x 'ZQUIT' >/dev/null 2>&1 || rc=$?
check "ZQUIT without val exits 0" "0" "$rc"

# DO args are bound by value; .param syntax is accepted (by value)
cat > /tmp/t387.m <<'EOF'
CALLEE(X) ;
 SET X=X+1
 QUIT
MAIN ;
 SET Y=5
 DO CALLEE(Y)
 WRITE Y
 DO CALLEE(.Y)
 WRITE Y
 QUIT
EOF
OUT=$($NIMM -r /tmp/t387.m -e 'DO MAIN' 2>&1)
check "DO args bound by value; .param accepted" "55" "$OUT"

# TSTART/TCOMMIT still work bare (no timeout/restart arg)
OUT=$($NIMM -x 'TSTART SET ^X=1 TCOMMIT WRITE $D(^X)' 2>&1)
check "TSTART/TCOMMIT still work" "1" "$OUT"

# OPEN/USE still work (no timeout/params)
echo "hi" > /tmp/t387.txt
OUT=$($NIMM -x 'OPEN 1:("/tmp/t387.txt":"READ") USE 1 READ l USE 0 WRITE l CLOSE 1' 2>&1)
check "OPEN/USE still work" "hi" "$OUT"

# ZANALYZE still works (no argument; analyzes current routine)
OUT=$($NIMM -r /tmp/t387.m -e 'ZANALYZE' 2>&1)
if [ -n "$OUT" ]; then
  echo "  PASS: ZANALYZE still reports"
  PASS=$((PASS+1))
else
  echo "  FAIL: ZANALYZE produced no output"
  FAIL=$((FAIL+1))
fi

rm -f /tmp/t387.m /tmp/t387.txt

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
