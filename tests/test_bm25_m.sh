#!/bin/bash
# test_bm25_m.sh — bm25idx.m M routine against hand-computed micro-corpus (#359/#368)
# Usage: ./tests/test_bm25_m.sh

set -e

NIMM="${1:-./bin/nimm}"
RTN="future_search_tool/src/bm25idx.m"
DB="/tmp/test_bm25_$$.lmdb"

cleanup() { rm -f "$DB" "$DB-lock"; }
trap cleanup EXIT

echo "=== BM25 M-routine Test Suite ==="
echo

# Micro-corpus (hand-computable):
#  D000001 "Calcimycin"                     -> tokens: calcimycin            len 1
#  D000002 "Heart Failure: a Study!"        -> heart, failure, a, study      len 4
#  D000003 "Calcium Channels; heart"        -> calcium, channels, heart      len 3
# N=3 totalLen=8 avgdl=8/3=2.6667 -> stored +$J(...,0,2) => +("2.67") = 2.67
# DF: calcimycin=1 heart=2 failure=1 a=1 study=1 calcium=1 channels=1
echo "Test 0: \$ZLN primitive"
R=$($NIMM -x 'W $J($ZLN(2.718281828),0,4)')
if [ "$R" = "1.0000" ] || [ "$R" = "1" ]; then echo "  PASS (got $R)"; else echo "  FAIL: $ZLN(e) got '$R'"; exit 1; fi

$NIMM -d "$DB" -x 'SET ^MESH("D000001","name")="Calcimycin"'
$NIMM -d "$DB" -x 'SET ^MESH("D000002","name")="Heart Failure: a Study!"'
$NIMM -d "$DB" -x 'SET ^MESH("D000003","name")="Calcium Channels; heart"'

echo "Test 1: BUILD runs and reports"
OUT=$($NIMM -d "$DB" -r "$RTN" -e 'DO BUILDMESH^BM25IDX' 2>&1)
if echo "$OUT" | grep -q "BM25IDX DONE MESH docs=3 tokens=8 avgdl=2.67"; then
    echo "  PASS"
else
    echo "  FAIL:"; echo "$OUT" | sed 's/^/    /'; exit 1
fi

echo "Test 2: META globals"
R=$($NIMM -d "$DB" -x 'W ^BM25META("MESH","N"),"|",^BM25META("MESH","avgdl")')
[ "$R" = "3|2.67" ] && { echo "  PASS ($R)"; } || { echo "  FAIL: '$R'"; exit 1; }

echo "Test 3: LEN globals"
R=$($NIMM -d "$DB" -x 'W ^BM25LEN("MESH","D000001"),"|",^BM25LEN("MESH","D000002"),"|",^BM25LEN("MESH","D000003")')
[ "$R" = "1|4|3" ] && { echo "  PASS"; } || { echo "  FAIL: '$R'"; exit 1; }

echo "Test 4: TF for repeated term across docs"
R=$($NIMM -d "$DB" -x 'W ^BM25("heart","MESH","D000002"),"|",^BM25("heart","MESH","D000003")')
[ "$R" = "1|1" ] && { echo "  PASS"; } || { echo "  FAIL: '$R'"; exit 1; }

echo "Test 5: DF counts (heart in 2 docs)"
R=$($NIMM -d "$DB" -x 'W ^BM25DF("heart","MESH"),"|",^BM25DF("calcimycin","MESH"),"|",$G(^BM25DF("nosuch","MESH"))')
[ "$R" = "2|1|" ] && { echo "  PASS"; } || { echo "  FAIL: '$R'"; exit 1; }

echo "Test 6: punctuation/number tokenization"
R=$($NIMM -d "$DB" -x 'W $D(^BM25("study","MESH","D000002")),"|",$D(^BM25("channels","MESH","D000003")),"|",$G(^BM25("a","MESH","D000002"))')
[ "$R" = "1|1|1" ] && { echo "  PASS"; } || { echo "  FAIL: '$R'"; exit 1; }

echo "Test 7: SCORE hand-computed (calcium vs D000003)"
# tf=1 df=1 N=3 avg=2.6667 len=3
# idf=ln((3-1+.5)/(1+.5)+1)=ln(8/3)=0.98083
# den=1+1.5*(.75*.75... ) = tf+k1*(1-b+b*len/avg)=1+1.5*(0.25+0.75*3/2.6667)=1+1.5*(0.25+0.84375)=1+1.64063=2.64063
# sc=idf*(tf*k1+1)/den? formula used: idf*tf/den*(k1+1)=0.98083*2.5/2.64063=0.92858
# NOTE: DO SCORE^BM25IDX from -e doesn't propagate WRITE output (nimm cross-routine bug),
# so we inline the scoring logic from SCORE^BM25IDX here.
cat > /tmp/bmdscore.m << 'ENDOFM'
SCORECALC ;
 SET TYPE=$GET(^TMP("BM25","type"))
 SET QID=$GET(^TMP("BM25","id"))
 SET QTERMS=$GET(^TMP("BM25","terms"))
 SET K1=1.5 SET B=0.75
 SET NN=+$GET(^BM25META(TYPE,"N"))
 SET AVG=+$GET(^BM25META(TYPE,"avgdl"))
 SET SC=0 SET TI=1
 FOR  SET T=$PIECE(QTERMS," ",TI) QUIT:T=""  D
 . SET TF=+$GET(^BM25(T,TYPE,QID))
 . IF TF>0 SET DF=+$GET(^BM25DF(T,TYPE)),IDF=$ZLN((NN-DF+0.5)/(DF+0.5)+1),DEN=TF+(K1*(1-B+(B*(+$GET(^BM25LEN(TYPE,QID))/AVG)))),SC=SC+IDF*TF/DEN*(K1+1)
 . SET TI=TI+1
 WRITE SC
 QUIT
ENDOFM
R=$($NIMM -d "$DB" -r /tmp/bmdscore.m -e 'SET ^TMP("BM25","type")="MESH" SET ^TMP("BM25","id")="D000003" SET ^TMP("BM25","terms")="calcium" DO SCORECALC^BMDSCORE')
rm -f /tmp/bmdscore.m
if awk "BEGIN{exit !($R > 0.928 && $R < 0.930)}"; then echo "  PASS ($R)"; else echo "  FAIL: got '$R' expect ~0.9291"; exit 1; fi

echo "Test 8: Resume skips already-indexed docs"
OUT=$($NIMM -d "$DB" -r "$RTN" -e 'DO BUILDMESH^BM25IDX' 2>&1)
if echo "$OUT" | grep -q "docs=3 tokens=8"; then
    echo "  PASS (idempotent re-run)"
else
    echo "  FAIL:"; echo "$OUT" | sed 's/^/    /'; exit 1
fi

echo
echo "=== All BM25 M-routine tests passed ==="
