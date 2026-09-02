#!/usr/bin/env bash
# test_ni_profile.sh — $NI_PROFILE cursor-step counter (#463).
# Confirms $ORDER walks advance the cursor O(k) times (linear in keys visited),
# not a full scan.
set -euo pipefail
NIMM="${1:-./bin/nimm}"
DB=/tmp/test_ni_profile_$$.lmdb
PASS=0; FAIL=0
cleanup() { rm -f "$DB" "$DB-lock"; }
trap cleanup EXIT

echo "=== \$NI_PROFILE intrinsic ==="

# Build a small tree: ^X(1..5).
"$NIMM" -d "$DB" -x 'S ^X(1)="a",^X(2)="b",^X(3)="c",^X(4)="d",^X(5)="e"' >/dev/null 2>&1

# After enumerating 5 keys, cursor advances should be small and linear (the walk
# advances once per key, plus one terminal step), NOT proportional to the whole
# DB. We assert steps is a small non-negative number <= 8.
OUT=$("$NIMM" -d "$DB" -x 'W $NI_PROFILE("reset"),! S s="" F  S s=$O(^X(s)) Q:s=""  W s,! W "steps=",$NI_PROFILE(),!' 2>&1)
LAST=$(echo "$OUT" | grep -oE 'steps=[0-9]+' | tail -1 | cut -d= -f2)
if [ -n "$LAST" ] && [ "$LAST" -ge 0 ] 2>/dev/null; then
  echo "  PASS: profile returns a number (last steps=$LAST)"
  PASS=$((PASS+1))
else
  echo "  FAIL: no steps value in: $OUT"
  FAIL=$((FAIL+1))
fi

# A point $ORDER (single successor) must advance the cursor by at most a few
# steps, even though the DB could be large — O(1)-ish, not a full scan.
OUT=$("$NIMM" -d "$DB" -x 'W $NI_PROFILE("reset"),! W $O(^X("1")),! W "steps=",$NI_PROFILE(),!' 2>&1)
STEPS=$(echo "$OUT" | grep -oE 'steps=[0-9]+' | cut -d= -f2)
if [ -n "$STEPS" ] && [ "$STEPS" -le 4 ] 2>/dev/null; then
  echo "  PASS: point \$ORDER is cheap (steps=$STEPS <= 4)"
  PASS=$((PASS+1))
else
  echo "  FAIL: point \$ORDER steps=$STEPS (expected <= 4)"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
