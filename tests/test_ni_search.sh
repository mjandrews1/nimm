#!/usr/bin/env bash
# test_ni_search.sh — $NI_SEARCH intrinsic (FST Phase C).
# Builds a tiny ^BM25* index and checks the intrinsic returns ranked results.
set -euo pipefail
NIMM="${1:-./bin/nimm}"
PASS=0; FAIL=0

check() {
  local label="$1" actual="$2"
  if echo "$actual" | grep -q "$3"; then
    echo "  PASS: $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label"
    echo "    got: $actual"
    FAIL=$((FAIL+1))
  fi
}

echo "=== \$NI_SEARCH intrinsic ==="

OUT=$($NIMM -x 'S ^BM25META("MESH","N")=2,^BM25META("MESH","avgdl")="2.0",^BM25LEN("MESH","d1")=2,^BM25LEN("MESH","d2")=2,^BM25("hello","MESH","d1")=1,^BM25("hello","MESH","d2")=1,^BM25DF("hello","MESH")=2 W $NI_SEARCH("MESH","hello",10)' 2>&1)

check "\$NI_SEARCH returns d1" "$OUT" $'d1\t'
check "\$NI_SEARCH returns d2" "$OUT" $'d2\t'

# Non-matching term yields empty.
OUT=$($NIMM -x 'S ^BM25META("MESH","N")=2,^BM25META("MESH","avgdl")="2.0",^BM25LEN("MESH","d1")=2,^BM25("hello","MESH","d1")=1,^BM25DF("hello","MESH")=1 W $NI_SEARCH("MESH","absent",10)' 2>&1)
if [ -z "$OUT" ]; then
  echo "  PASS: \$NI_SEARCH empty for absent term"
  PASS=$((PASS+1))
else
  echo "  FAIL: expected empty, got '$OUT'"
  FAIL=$((FAIL+1))
fi

# $NI_EXPLAIN — per-term breakdown, total must match the score.
OUT=$($NIMM -x 'S ^BM25META("MESH","N")=2,^BM25META("MESH","avgdl")="2.0",^BM25LEN("MESH","d1")=2,^BM25LEN("MESH","d2")=2,^BM25("hello","MESH","d1")=1,^BM25("hello","MESH","d2")=1,^BM25DF("hello","MESH")=2 W $NI_EXPLAIN("MESH","d1","hello")' 2>&1)
check "\$NI_EXPLAIN shows per-term breakdown" "$OUT" "term=hello tf=1 df=2"
check "\$NI_EXPLAIN total matches" "$OUT" "total=0.182322"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
