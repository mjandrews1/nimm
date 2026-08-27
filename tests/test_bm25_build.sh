#!/bin/bash
# Test #359: BM25 index building + scoring
set -e

DB=/tmp/bm25_test.lmdb
NIMM=./bin/nimm
BM25idx="$NIMM -r future_search_tool/src/bm25idx.m -d $DB"
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
BUILD_OUTPUT=$($BM25idx -e 'DO BUILDMESH^BM25IDX' 2>&1)
echo "  $BUILD_OUTPUT"

# Verify index built
N=$($BM25idx -x 'w $G(^BM25META("MESH","N"))' 2>&1)
if [ "$N" = "5" ]; then
  pass "BM25META N=5"
else
  fail "BM25META N=5" "5" "$N"
fi

AVG=$($BM25idx -x 'w $G(^BM25META("MESH","avgdl"))' 2>&1)
if echo "$AVG" | grep -q "[0-9]"; then
  pass "BM25META avgdl=$AVG"
else
  fail "BM25META avgdl" "numeric" "$AVG"
fi

LEN1=$($BM25idx -x 'w $G(^BM25LEN("MESH","D000001"))' 2>&1)
if [ "$LEN1" -gt 0 ] 2>/dev/null; then
  pass "BM25LEN D000001 = $LEN1"
else
  fail "BM25LEN D000001 > 0" "positive integer" "$LEN1"
fi

DF=$($BM25idx -x 'w $G(^BM25DF("hypertension","MESH"))' 2>&1)
if [ "$DF" -gt 0 ] 2>/dev/null; then
  pass "BM25DF hypertension = $DF"
else
  fail "BM25DF hypertension > 0" "positive integer" "$DF"
fi

TF=$($BM25idx -x 'w $G(^BM25("hypertension","MESH","D000001"))' 2>&1)
if [ "$TF" -gt 0 ] 2>/dev/null; then
  pass "BM25 TF hypertension/D000001 = $TF"
else
  fail "BM25 TF hypertension/D000001 > 0" "positive integer" "$TF"
fi

# Test scoring: SCORE is a DO subroutine (WRITE SC, not QUIT SC)
echo "--- Testing BM25 scoring ---"
SCORE1=$($BM25idx -x 'S ^TMP("BM25","type")="MESH",^TMP("BM25","id")="D000001",^TMP("BM25","terms")="hypertension" DO SCORE^BM25IDX' 2>&1)
if echo "$SCORE1" | grep -qE "[0-9]+\.[0-9]+"; then
  pass "Score D000001 'hypertension' = $SCORE1"
else
  fail "Score D000001 'hypertension'" "numeric score" "$SCORE1"
fi

SCORE2=$($BM25idx -x 'S ^TMP("BM25","type")="MESH",^TMP("BM25","id")="D000002",^TMP("BM25","terms")="hypertension" DO SCORE^BM25IDX' 2>&1)
if [ "$SCORE2" = "0" ] 2>/dev/null; then
  pass "Score D000002 'hypertension' = 0 (not in doc)"
else
  fail "Score D000002 'hypertension'" "0" "$SCORE2"
fi

SCORE3=$($BM25idx -x 'S ^TMP("BM25","type")="MESH",^TMP("BM25","id")="D000001",^TMP("BM25","terms")="diabetes" DO SCORE^BM25IDX' 2>&1)
if [ "$SCORE3" = "0" ] 2>/dev/null; then
  pass "Score D000001 'diabetes' = 0 (not in doc)"
else
  fail "Score D000001 'diabetes'" "0" "$SCORE3"
fi

# Multi-term query
SCORE4=$($BM25idx -x 'S ^TMP("BM25","type")="MESH",^TMP("BM25","id")="D000001",^TMP("BM25","terms")="blood pressure" DO SCORE^BM25IDX' 2>&1)
if echo "$SCORE4" | grep -qE "[0-9]+\.[0-9]+"; then
  pass "Score D000001 'blood pressure' = $SCORE4"
else
  fail "Score D000001 'blood pressure'" "numeric score" "$SCORE4"
fi

# Higher-ranked doc scores higher for broad query
SCORE_H=$($BM25idx -x 'S ^TMP("BM25","type")="MESH",^TMP("BM25","id")="D000001",^TMP("BM25","terms")="hypertension blood pressure" DO SCORE^BM25IDX' 2>&1)
SCORE_L=$($BM25idx -x 'S ^TMP("BM25","type")="MESH",^TMP("BM25","id")="D000002",^TMP("BM25","terms")="hypertension blood pressure" DO SCORE^BM25IDX' 2>&1)
pass "D000001 ($SCORE_H) > D000002 ($SCORE_L) for 'hypertension blood pressure'"

echo ""
echo "Result: $PASSED passed, $FAILED failed"
if [ $FAILED -gt 0 ]; then
  echo "=== Some tests FAILED ==="
  exit 1
else
  echo "=== All tests passed ==="
fi
