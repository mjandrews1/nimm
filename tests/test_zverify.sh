#!/bin/bash
# test_zverify.sh — Test ZVERIFY integrity check/repair (#366)
# Usage: ./tests/test_zverify.sh

set -e

NIMM="./nimm"
DB="/tmp/test_zverify_$$.lmdb"

cleanup() {
    if [ -n "${BG_PID:-}" ]; then
        { kill -9 "$BG_PID" 2>/dev/null; wait "$BG_PID" 2>/dev/null || true; }
    fi
    rm -f "$DB" "$DB-lock"
}
trap cleanup EXIT

echo "=== ZVERIFY Test Suite ==="
echo

# --- Test 1: Clean database reports ok ---
echo "Test 1: Clean database reports ok"
$NIMM -d "$DB" -x 'SET ^A(1)="x" SET ^A(2)="y" SET ^B("k")="v" ZVERIFY' > /tmp/zv_out_$$.txt
if grep -q "ZVERIFY total=3" /tmp/zv_out_$$.txt && \
   grep -q "ZVERIFY global A=2" /tmp/zv_out_$$.txt && \
   grep -q "ZVERIFY malformed=0" /tmp/zv_out_$$.txt && \
   grep -q "ZVERIFY stale=0" /tmp/zv_out_$$.txt && \
   grep -q "ZVERIFY status=ok" /tmp/zv_out_$$.txt; then
    echo "  PASS: counts/malformed/stale/status all correct"
else
    echo "  FAIL:"; cat /tmp/zv_out_$$.txt | sed 's/^/    /'; exit 1
fi

# --- Test 2: Live lock NOT flagged as stale ---
echo "Test 2: Live lock not flagged stale"
BG_PID=""
$NIMM -d "$DB" -x 'LOCK +^live HANG 30' &
BG_PID=$!
sleep 1
$NIMM -d "$DB" -x 'ZVERIFY' > /tmp/zv_out_$$.txt
STALE=$(grep "ZVERIFY stale=" /tmp/zv_out_$$.txt | cut -d= -f2)
if [ "$STALE" = "0" ]; then
    echo "  PASS: live lock not reported"
else
    echo "  FAIL: expected stale=0, got $STALE"; exit 1
fi

# --- Test 3: Dead-PID lock IS detected ---
echo "Test 3: Dead-PID lock detected"
$NIMM -d "$DB" -x 'LOCK +^dead HANG 30' &
DEAD_PID=$!
sleep 1
{ kill -9 "$DEAD_PID" 2>/dev/null; wait "$DEAD_PID" 2>/dev/null || true; }
sleep 0.3
$NIMM -d "$DB" -x 'ZVERIFY' > /tmp/zv_out_$$.txt
STALE=$(grep "ZVERIFY stale=" /tmp/zv_out_$$.txt | cut -d= -f2)
if [ "$STALE" = "1" ] && grep -q "ZVERIFY stale-lock dead" /tmp/zv_out_$$.txt && \
   grep -q "ZVERIFY status=issues" /tmp/zv_out_$$.txt && \
   ! grep -q "stale-lock live" /tmp/zv_out_$$.txt; then
    echo "  PASS: exactly 1 stale lock ('dead'), 'live' untouched"
else
    echo "  FAIL:"; cat /tmp/zv_out_$$.txt | sed 's/^/    /'; exit 1
fi

# --- Test 4: Repair removes stale locks only ---
echo "Test 4: Repair removes stale locks"
$NIMM -d "$DB" -x 'ZVERIFY "repair"' > /tmp/zv_out_$$.txt
REP=$(grep "ZVERIFY repaired=" /tmp/zv_out_$$.txt | cut -d= -f2)
STATUS=$(grep "ZVERIFY status=" /tmp/zv_out_$$.txt | cut -d= -f2)
if [ "$REP" = "1" ] && [ "$STATUS" = "ok" ]; then
    echo "  PASS: repaired=1, status=ok"
else
    echo "  FAIL:"; cat /tmp/zv_out_$$.txt | sed 's/^/    /'; exit 1
fi
# live lock from test 2 must still exist after repair
LIVE=$($NIMM -d "$DB" -x 'WRITE $DATA(^%LOCK("live"))' | tail -1)
if [ "$LIVE" = "1" ]; then
    echo "  PASS: live lock preserved"
else
    echo "  FAIL: live lock was deleted! got '$LIVE'"; exit 1
fi

# --- Test 5: Post-repair state clean ---
echo "Test 5: Post-repair verification clean"
$NIMM -d "$DB" -x 'ZVERIFY' > /tmp/zv_out_$$.txt
STALE=$(grep "ZVERIFY stale=" /tmp/zv_out_$$.txt | cut -d= -f2)
STATUS=$(grep "ZVERIFY status=" /tmp/zv_out_$$.txt | cut -d= -f2)
if [ "$STALE" = "0" ] && [ "$STATUS" = "ok" ]; then
    echo "  PASS: stale=0 status=ok"
else
    echo "  FAIL: stale=$STALE status=$STATUS"; exit 1
fi

# --- Test 6: In-memory mode skips gracefully ---
echo "Test 6: In-memory mode skips gracefully"
OUT=$($NIMM -x 'ZVERIFY' 2>&1)
if echo "$OUT" | grep -q "status=skip"; then
    echo "  PASS: skip reported"
else
    echo "  FAIL: got '$OUT'"; exit 1
fi

rm -f /tmp/zv_out_$$.txt
echo
echo "=== All ZVERIFY tests passed ==="
