#!/bin/bash
# test_crash_recovery.sh — H3: crash-recovery + stale-lock detection.
# Usage: ./tests/test_crash_recovery.sh

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

echo "=== H3: crash recovery + stale locks ==="

DB=/tmp/crash_$$.lmdb
rm -f "$DB" "$DB-lock"

# 1. Mid-transaction crash: uncommitted write must not persist; DB stays clean.
cat > /tmp/crash.m <<'EOF'
MAIN ;
 TSTART
 SET ^G(1)="x"
 HANG 5
 TCOMMIT
 QUIT
EOF
"$NIMM" -d "$DB" -r /tmp/crash.m -x 'DO MAIN' &
PID=$!
sleep 1
kill -9 "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

OUT=$("$NIMM" -d "$DB" -x 'WRITE $DATA(^G(1))' 2>&1)
check "uncommitted write rolled back" "0" "$OUT"
OUT=$("$NIMM" -d "$DB" -x 'ZVERIFY' 2>&1)
check_contains "ZVERIFY clean after crash" 'status=ok' "$OUT"

# 2. Stale lock: a process holds a LOCK and dies; ZVERIFY detects it.
cat > /tmp/lock.m <<'EOF'
MAIN ;
 LOCK +^CRASHLOCK
 HANG 5
 QUIT
EOF
"$NIMM" -d "$DB" -r /tmp/lock.m -x 'DO MAIN' &
PID=$!
sleep 1
kill -9 "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

OUT=$("$NIMM" -d "$DB" -x 'ZVERIFY' 2>&1)
check_contains "stale lock detected" 'stale-lock' "$OUT"

# Repair clears the stale lock.
OUT=$("$NIMM" -d "$DB" -x 'ZVERIFY "repair"' 2>&1)
check_contains "repair clears stale lock" 'repaired=1' "$OUT"
OUT=$("$NIMM" -d "$DB" -x 'ZVERIFY' 2>&1)
check_contains "stale lock gone after repair" 'stale=0' "$OUT"

rm -f "$DB" "$DB-lock" /tmp/crash.m /tmp/lock.m

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
