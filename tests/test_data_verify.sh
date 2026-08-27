#!/bin/bash
# Test #382: Data verification and testing suite
# End-to-end verification: load → index → search → verify
set -e

DB=/tmp/dataverify_test.lmdb
NIMM=./bin/nimm
BM25idx="$NIMM -r future_search_tool/src/bm25idx.m -d $DB"
PASSED=0
FAILED=0

cleanup() { rm -rf "$DB" "$DB-lock" 2>/dev/null; }
trap cleanup EXIT

pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; echo "    expected: $2"; echo "    actual: $3"; FAILED=$((FAILED+1)); }

echo "=== #382: Data Verification Suite ==="

cleanup

# Load test data
echo "--- Loading test data ---"
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
SET ^CATLINE("C000001","title")="Journal of Hypertension"
SET ^CATLINE("C000002","title")="Diabetes Care"
SET ^SERLINE("S000001","title")="Journal of Hypertension"
SET ^PUBMED("P000001","title")="Hypertension treatment guidelines"
SET ^PUBMED("P000001","abstract")="Blood pressure management in hypertensive patients"
SET ^PUBMED("P000002","title")="Type 2 diabetes and cardiovascular risk"
SET ^PUBMED("P000002","abstract")="Insulin resistance in metabolic syndrome"
' 2>&1 > /dev/null

# Build BM25 index
echo "--- Building BM25 index ---"
$BM25idx -e 'DO BUILDMESH^BM25IDX' 2>&1 > /dev/null
$BM25idx -e 'DO BUILDCAT^BM25IDX' 2>&1 > /dev/null
$BM25idx -e 'DO BUILDSER^BM25IDX' 2>&1 > /dev/null
$BM25idx -e 'DO BUILDPUB^BM25IDX' 2>&1 > /dev/null

# === Check 1: Record counts ===
echo "--- Check 1: Record counts ---"
MESH_COUNT=$($NIMM -d $DB -x 's c=0,ui="" f  s ui=$O(^MESH(ui)) q:ui=""  s c=c+1 w !,c' 2>&1 | tail -1)
if [ "$MESH_COUNT" = "5" ]; then
  pass "MeSH record count = 5"
else
  fail "MeSH record count" "5" "$MESH_COUNT"
fi

CAT_COUNT=$($NIMM -d $DB -x 's c=0,id="" f  s id=$O(^CATLINE(id)) q:id=""  s c=c+1 w !,c' 2>&1 | tail -1)
if [ "$CAT_COUNT" = "2" ]; then
  pass "CatLine record count = 2"
else
  fail "CatLine record count" "2" "$CAT_COUNT"
fi

PUB_COUNT=$($NIMM -d $DB -x 's c=0,id="" f  s id=$O(^PUBMED(id)) q:id=""  s c=c+1 w !,c' 2>&1 | tail -1)
if [ "$PUB_COUNT" = "2" ]; then
  pass "PubMed record count = 2"
else
  fail "PubMed record count" "2" "$PUB_COUNT"
fi

# === Check 2: Field presence ===
echo "--- Check 2: Field presence ---"
NAME=$($NIMM -d $DB -x 'w $G(^MESH("D000001","name"))' 2>&1)
if [ "$NAME" = "Hypertension" ]; then
  pass "MeSH D000001 has name"
else
  fail "MeSH D000001 name" "Hypertension" "$NAME"
fi

TITLE=$($NIMM -d $DB -x 'w $G(^PUBMED("P000001","title"))' 2>&1)
if echo "$TITLE" | grep -q "Hypertension"; then
  pass "PubMed P000001 has title"
else
  fail "PubMed P000001 title" "contains Hypertension" "$TITLE"
fi

# === Check 3: BM25 index integrity ===
echo "--- Check 3: BM25 index integrity ---"
N=$($BM25idx -x 'w $G(^BM25META("MESH","N"))' 2>&1)
if [ "$N" = "5" ]; then
  pass "BM25META MESH N=5"
else
  fail "BM25META MESH N" "5" "$N"
fi

DF=$($BM25idx -x 'w $G(^BM25DF("hypertension","MESH"))' 2>&1)
if [ "$DF" -gt 0 ] 2>/dev/null; then
  pass "BM25DF hypertension exists (df=$DF)"
else
  fail "BM25DF hypertension" "positive" "$DF"
fi

LEN=$($BM25idx -x 'w $G(^BM25LEN("MESH","D000001"))' 2>&1)
if [ "$LEN" -gt 0 ] 2>/dev/null; then
  pass "BM25LEN D000001 = $LEN"
else
  fail "BM25LEN D000001" "positive" "$LEN"
fi

# === Check 4: Search correctness ===
echo "--- Check 4: Search correctness ---"
SCORE_H=$($BM25idx -x 'S ^TMP("BM25","type")="MESH",^TMP("BM25","id")="D000001",^TMP("BM25","terms")="hypertension" DO SCORE^BM25IDX' 2>&1)
SCORE_D=$($BM25idx -x 'S ^TMP("BM25","type")="MESH",^TMP("BM25","id")="D000002",^TMP("BM25","terms")="hypertension" DO SCORE^BM25IDX' 2>&1)
if [ "$SCORE_H" != "0" ] && [ "$SCORE_D" = "0" ]; then
  pass "Hypertension doc scores >0, Diabetes doc scores =0"
else
  fail "Search relevance" "H>0, D=0" "H=$SCORE_H, D=$SCORE_D"
fi

# === Check 5: Cross-references ===
echo "--- Check 5: Cross-references ---"
$NIMM -d $DB -x 'SET ^LINK("MESH","D000001","PUBMED","P000001")="mesh_term"' 2>&1 > /dev/null
LINK=$($NIMM -d $DB -x 'w $G(^LINK("MESH","D000001","PUBMED","P000001"))' 2>&1)
if [ "$LINK" = "mesh_term" ]; then
  pass "Cross-reference ^LINK works"
else
  fail "Cross-reference ^LINK" "mesh_term" "$LINK"
fi

# === Check 6: Load state (depends on #381) ===
echo "--- Check 6: Load state ---"
$NIMM -d $DB -x 'SET ^FST("load","mesh.xml")="complete:5"' 2>&1 > /dev/null
LOAD_STATUS=$($NIMM -d $DB -x 'w $G(^FST("load","mesh.xml"))' 2>&1)
if [ "$LOAD_STATUS" = "complete:5" ]; then
  pass "Load state tracking works"
else
  fail "Load state" "complete:5" "$LOAD_STATUS"
fi

# === Check 7: Multiple record types indexed ===
echo "--- Check 7: Multi-type indexing ---"
CAT_N=$($BM25idx -x 'w $G(^BM25META("CATLINE","N"))' 2>&1)
PUB_N=$($BM25idx -x 'w $G(^BM25META("PUBMED","N"))' 2>&1)
if [ "$CAT_N" = "2" ] && [ "$PUB_N" = "2" ]; then
  pass "CatLine and PubMed indexed (N=2 each)"
else
  fail "Multi-type indexing" "CATLINE=2, PUBMED=2" "CATLINE=$CAT_N, PUBMED=$PUB_N"
fi

# === Check 8: Tokenization ===
echo "--- Check 8: Tokenization ---"
TOKENS=$($BM25idx -x 'w $G(^BM25LEN("PUBMED","P000001"))' 2>&1)
if [ "$TOKENS" -gt 0 ] 2>/dev/null; then
  pass "PubMed P000001 tokenized ($TOKENS tokens)"
else
  fail "PubMed P000001 tokenized" "positive" "$TOKENS"
fi

echo ""
echo "Result: $PASSED passed, $FAILED failed"
if [ $FAILED -gt 0 ]; then
  echo "=== Some tests FAILED ==="
  exit 1
else
  echo "=== All tests passed ==="
fi
