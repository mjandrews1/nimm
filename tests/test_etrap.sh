#!/bin/bash
# test_etrap.sh — H6: $ETRAP fires and cannot recurse unboundedly.
# Usage: ./tests/test_etrap.sh

set -euo pipefail
NIMM="${1:-./bin/nimm}"
PASS=0; FAIL=0

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

echo "=== H6: \$ETRAP safety ==="

# A self-trapping $ETRAP (trap code errors, re-triggering the trap) must
# terminate with the recursion-limit message, not hang or crash.
cat > /tmp/etrap_self.m <<'EOF'
MAIN ;
 SET $ETRAP="DO TRAP"
 set y=1
 QUIT
TRAP ;
 set z=1
 QUIT
EOF
OUT=$($NIMM -m strict -r /tmp/etrap_self.m -x 'DO MAIN' 2>&1 || true)
check_contains "self-trapping \$ETRAP terminates" 'recursion limit exceeded' "$OUT"

# A non-trapping $ETRAP still runs (verified via a persisted global side effect).
DB=/tmp/etrap_ok_$$.lmdb
rm -f "$DB" "$DB-lock"
cat > /tmp/etrap_ok.m <<'EOF'
MAIN ;
 SET $ETRAP="SET ^TRAPDONE=1"
 set y=1
 QUIT
EOF
$NIMM -m strict -d "$DB" -r /tmp/etrap_ok.m -x 'DO MAIN' >/dev/null 2>&1 || true
OUT=$($NIMM -d "$DB" -x 'WRITE ^TRAPDONE' 2>&1)
rm -f "$DB" "$DB-lock"
check_contains "non-trapping \$ETRAP executes" '1' "$OUT"

rm -f /tmp/etrap_self.m /tmp/etrap_ok.m

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
