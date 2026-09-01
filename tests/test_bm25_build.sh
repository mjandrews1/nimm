#!/bin/bash
# Test #359: BM25 index building + scoring
set -e

DB=/tmp/bm25_test.lmdb
NIMM=./bin/nimm
BUILD_BM25=./bin/build_bm25
PASSED=0
FAILED=0

cleanup() {
  rm -rf "$DB" "$DB-lock" 2>/dev/null
}
trap cleanup EXIT

pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; echo "    expected: $2"; echo "    actual: $3"; FAILED=$((FAILED+1)); }

echo "=== #359: BM25 Index Building + Scoring ==="

cleanup

# Load sample MeSH descriptors
echo "--- Loading sample MeSH data ---"
$NIMM -d $DB -x '
SET ^MESH("D000001","name")="Hypertension"
SET ^MESH("D000001","scopeNote")="Persistently high arterial blood pressure"
SET ^MESH("D000002","name")="Diabetes Mellitus, Type 2"
SET ^MESH("D000002","scopeNote")="A type of diabetes mellitus characterized by insulin resistance"
SET ^MESH("D000003","name")="Hypertension, Renal"
SET ^MESH("D000003","scopeNote")="High blood pressure caused by kidney disease"
SET ^MESH("D000004","name")="Diabetes Mellitus, Type 1"
SET ^MESH("D000004","scopeNote")="A type of diabetes mellitus characterized by autoimmune destruction"
SET ^MESH("D000005","name")="Heart Failure"
SET ^MESH("D000005","scopeNote")="Inability of the heart to pump blood effectively"
' 2>&1 > /dev/null

# Verify data loaded
FIRST=$($NIMM -d $DB -x 's ui=$O(^MESH("")) w ui' 2>&1)
if [ "$FIRST" = "D000001" ]; then
  pass "Load MeSH records (first key=D000001)"
else
  fail "Load MeSH records" "D000001" "$FIRST"
fi

# Build BM25 index for MeSH
echo "--- Building BM25 index ---"
BUILD_OUTPUT=$($BUILD_BM25 "$DB" MESH '^MESH' 'name^scopeNote' 2>&1)
echo "  $BUILD_OUTPUT"

# Verify index built
N=$($NIMM -d $DB -x 'w $G(^BM25META("MESH","N"))' 2>&1)
if [ "$N" = "5" ]; then
  pass "BM25META N=5"
else
  fail "BM25META N=5" "5" "$N"
fi

AVG=$($NIMM -d $DB -x 'w $G(^BM25META("MESH","avgdl"))' 2>&1)
if echo "$AVG" | grep -q "[0-9]"; then
  pass "BM25META avgdl=$AVG"
else
  fail "BM25META avgdl" "numeric" "$AVG"
fi

LEN1=$($NIMM -d $DB -x 'w $G(^BM25LEN("MESH","D000001"))' 2>&1)
if [ "$LEN1" -gt 0 ] 2>/dev/null; then
  pass "BM25LEN D000001 = $LEN1"
else
  fail "BM25LEN D000001 > 0" "positive integer" "$LEN1"
fi

DF=$($NIMM -d $DB -x 'w $G(^BM25DF("hypertension","MESH"))' 2>&1)
if [ "$DF" -gt 0 ] 2>/dev/null; then
  pass "BM25DF hypertension = $DF"
else
  fail "BM25DF hypertension > 0" "positive integer" "$DF"
fi

TF=$($NIMM -d $DB -x 'w $G(^BM25("hypertension","MESH","D000001"))' 2>&1)
if [ "$TF" -gt 0 ] 2>/dev/null; then
  pass "BM25 TF hypertension/D000001 = $TF"
else
  fail "BM25 TF hypertension/D000001 > 0" "positive integer" "$TF"
fi

# Test scoring via $NI_SEARCH (M SCORE/SEARCH were deleted in FST Phase B).
echo "--- Testing BM25 scoring ---"
SCORE1=$($NIMM -d $DB -x 'w $NI_SEARCH("MESH","hypertension",10)' 2>&1)
if echo "$SCORE1" | grep -q "D000001"; then
  pass "Search 'hypertension' finds D000001: $SCORE1"
else
  fail "Search 'hypertension' finds D000001" "D000001" "$SCORE1"
fi

SCORE2=$($NIMM -d $DB -x 'w $NI_SEARCH("MESH","hypertension",10)' 2>&1)
if echo "$SCORE2" | grep -q "D000002"; then
  fail "Search 'hypertension' should NOT find D000002" "" "$SCORE2"
else
  pass "Search 'hypertension' excludes D000002 (not in doc)"
fi

SCORE3=$($NIMM -d $DB -x 'w $NI_SEARCH("MESH","diabetes",10)' 2>&1)
if echo "$SCORE3" | grep -q "D000001"; then
  fail "Search 'diabetes' should NOT find D000001" "" "$SCORE3"
else
  pass "Search 'diabetes' excludes D000001 (not in doc)"
fi

# Multi-term query: D000001 matches 'blood pressure'
SCORE4=$($NIMM -d $DB -x 'w $NI_SEARCH("MESH","blood pressure",10)' 2>&1)
if echo "$SCORE4" | grep -q "D000001"; then
  pass "Search 'blood pressure' finds D000001: $SCORE4"
else
  fail "Search 'blood pressure' finds D000001" "D000001" "$SCORE4"
fi

# Higher-ranked doc ranks higher for broad query
RANK1=$($NIMM -d $DB -x 'w $NI_SEARCH("MESH","hypertension blood pressure",10)' 2>&1 | head -1 | cut -f1)
if [ "$RANK1" = "D000001" ]; then
  pass "D000001 ranked first for 'hypertension blood pressure'"
else
  fail "D000001 ranked first" "D000001" "$RANK1"
fi

echo ""
echo "Result: $PASSED passed, $FAILED failed"
if [ $FAILED -gt 0 ]; then
  echo "=== Some tests FAILED ==="
  exit 1
else
  echo "=== All tests passed ==="
fi
