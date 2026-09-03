#!/usr/bin/env bash
# test_ni_bool.sh — $NI_BOOL intrinsic (#468): AND/OR/NOT, parens, phrases.
set -euo pipefail
NIMM="${1:-./bin/nimm}"
PASS=0; FAIL=0

check() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $label"; PASS=$((PASS+1))
  else
    echo "  FAIL: $label"; echo "    got:      [$actual]"; echo "    expected: [$expected]"
    FAIL=$((FAIL+1))
  fi
}

echo "=== \$NI_BOOL intrinsic ==="

SEED='S ^BM25("heart","MESH","d1")=1,^BM25("lung","MESH","d1")=1,^BM25("heart","MESH","d2")=1,^BM25("bone","MESH","d2")=1,^BM25("heart","MESH","d3")=1,^BM25LEN("MESH","d1")=10,^BM25LEN("MESH","d2")=10,^BM25LEN("MESH","d3")=10,^BM25DF("heart","MESH")=3,^BM25DF("lung","MESH")=1,^BM25DF("bone","MESH")=1'

OUT=$($NIMM -x "$SEED W \$NI_BOOL(\"MESH\",\"heart\")" 2>&1)
check "heart posting" "$OUT" $'d1\nd2\nd3'

OUT=$($NIMM -x "$SEED W \$NI_BOOL(\"MESH\",\"heart AND lung\")" 2>&1)
check "AND" "$OUT" $'d1'

OUT=$($NIMM -x "$SEED W \$NI_BOOL(\"MESH\",\"heart OR bone\")" 2>&1)
check "OR" "$OUT" $'d1\nd2\nd3'

OUT=$($NIMM -x "$SEED W \$NI_BOOL(\"MESH\",\"heart AND NOT lung\")" 2>&1)
check "AND NOT" "$OUT" $'d2\nd3'

OUT=$($NIMM -x "$SEED W \$NI_BOOL(\"MESH\",\"(heart OR bone) AND NOT lung\")" 2>&1)
check "parens + NOT" "$OUT" $'d2\nd3'

# Phrase: needs ^BMPOS. p1 adjacent (7,8), p2 gap (1,9).
PSEED='S ^BM25("myasthenia","MESH","p1")=1,^BM25("gravis","MESH","p1")=1,^BMPOS("MESH","p1","myasthenia")="7",^BMPOS("MESH","p1","gravis")="8",^BM25("myasthenia","MESH","p2")=1,^BM25("gravis","MESH","p2")=1,^BMPOS("MESH","p2","myasthenia")="1",^BMPOS("MESH","p2","gravis")="9",^BM25LEN("MESH","p1")=10,^BM25LEN("MESH","p2")=10,^BM25DF("myasthenia","MESH")=2,^BM25DF("gravis","MESH")=2'

OUT=$($NIMM -x "$PSEED W \$NI_BOOL(\"MESH\",\"myasthenia AND gravis\")" 2>&1)
check "AND finds both" "$OUT" $'p1\np2'

OUT=$($NIMM -x "$PSEED W \$NI_BOOL(\"MESH\",\"\"\"myasthenia gravis\"\"\")" 2>&1)
check "phrase adjacent only" "$OUT" $'p1'

# topK
OUT=$($NIMM -x "$SEED W \$NI_BOOL(\"MESH\",\"heart\",\"2\")" 2>&1)
check "topK=2" "$OUT" $'d1\nd2'

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
