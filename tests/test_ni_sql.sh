#!/usr/bin/env bash
# test_ni_sql.sh — $NI_SQL intrinsic (#462, M1).
# Builds a tiny ^BM25 / ^LINK store and checks SELECT point/range/order/limit
# plus the error gates through the binary.
set -euo pipefail
NIMM="${1:-./bin/nimm}"
PASS=0; FAIL=0

check() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label"
    echo "    got:      $actual"
    echo "    expected: $expected"
    FAIL=$((FAIL+1))
  fi
}

echo "=== \$NI_SQL intrinsic ==="

# Shared seed: a couple of ^BM25 rows + a ^LINK traversal.
SEED='S ^BM25("hello","MESH","d1")=1,^BM25("hello","MESH","d2")=3,^BM25("hello","MESH","d10")=2,^LINK("MESH","D000001","PUBMED","100")="mesh_term",^LINK("MESH","D000001","PUBMED","200")="mesh_term"'

OUT=$($NIMM -x "$SEED W \$NI_SQL(\"SELECT doc_id FROM bm25 WHERE term='hello' AND src='MESH' ORDER BY doc_id\")" 2>&1)
check "scan in M collation order" "$OUT" $'d1\nd10\nd2'

OUT=$($NIMM -x "$SEED W \$NI_SQL(\"SELECT tf FROM bm25 WHERE term='hello' AND src='MESH' AND doc_id='d2'\")" 2>&1)
check "point lookup" "$OUT" "3"

OUT=$($NIMM -x "$SEED W \$NI_SQL(\"SELECT doc_id FROM bm25 WHERE term='hello' AND src='MESH' LIMIT 2\")" 2>&1)
check "limit prefix" "$OUT" $'d1\nd10'

OUT=$($NIMM -x "$SEED W \$NI_SQL(\"SELECT to_id FROM link WHERE from_type='MESH' AND from_id='D000001' AND to_type='PUBMED' ORDER BY to_id\")" 2>&1)
check "link traversal" "$OUT" $'100\n200'

OUT=$($NIMM -x "$SEED W \$NI_SQL(\"SELECT doc_id FROM nope\")" 2>&1)
check "unknown table error" "$OUT" "NI_SQL error: unknown table: nope"

OUT=$($NIMM -x "$SEED W \$NI_SQL(\"SELECT doc_id FROM bm25 WHERE term='hello' AND src='MESH' ORDER BY doc_id DESC\")" 2>&1)
check "desc deferred error" "$OUT" "NI_SQL error: ORDER BY DESC not in M1 (materialize+sort is M3)"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
