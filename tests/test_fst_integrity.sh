#!/bin/bash
# test_fst_integrity.sh — F2: FST index integrity (detect corruption, not empty results).
# Usage: ./tests/test_fst_integrity.sh

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

echo "=== F2: FST index integrity ==="

DB=/tmp/fstint_$$.lmdb
rm -f "$DB" "$DB-lock"

# Build a small FST-shaped index (MeSH/BM25/keyword globals).
"$NIMM" -d "$DB" -x 'SET ^FST(1)="x",^BM25TF("k",1)=1,^IDXKEYWORD("w",1)=1' >/dev/null 2>&1

# ZVERIFY reports the globals and a clean status.
OUT=$("$NIMM" -d "$DB" -x 'ZVERIFY' 2>&1)
check_contains "ZVERIFY sees FST globals" 'global FST=1' "$OUT"
check_contains "ZVERIFY sees BM25TF" 'global BM25TF=1' "$OUT"
check_contains "ZVERIFY clean" 'status=ok' "$OUT"

# Corrupt the index (truncate the mdb file); reads must FAIL loudly, not return empty.
truncate -s 10 "$DB"
OUT=$("$NIMM" -d "$DB" -x 'WRITE $DATA(^FST(1))' 2>&1 || true)
check_contains "corrupt index detected (error, not empty)" 'env_open failed' "$OUT"

rm -f "$DB" "$DB-lock"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
