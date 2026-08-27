#!/bin/bash
# Test #381: ZLOADXML load-state tracking
# Verifies ^FST("load",file) tracks in-progress/complete status
set -e

DB=/tmp/loadstate_test.lmdb
NIMM=./bin/nimm
PASSED=0
FAILED=0

cleanup() {
  rm -rf "$DB" "$DB-lock" 2>/dev/null
  rm -f /tmp/loadstate_fixture.xml 2>/dev/null
}
trap cleanup EXIT

pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; echo "    expected: $2"; echo "    actual: $3"; FAILED=$((FAILED+1)); }

# Create helper routine for FOR loop detection
cat > /tmp/DETECT.m << 'MEOF'
DETECT ; find incomplete loads
 N f s f="" f s f=$O(^FST("load",f)) q:f="" d
 . i $G(^FST("load",f))="in-progress" w f," "
 q
MEOF

echo "=== #381: ZLOADXML Load-State Tracking ==="

# Test 1: Initial state — no load records
echo "--- Test: Initial state ---"
INITIAL=$($NIMM -d $DB -x 'w $G(^FST("load","test.xml"))' 2>&1)
if [ -z "$INITIAL" ]; then
  pass "No load record initially"
else
  fail "No load record initially" "(empty)" "$INITIAL"
fi

# Test 2: Simulate load start — mark in-progress
echo "--- Test: Mark in-progress ---"
$NIMM -d $DB -x 'SET ^FST("load","test.xml")="in-progress"' > /dev/null 2>&1
STATUS=$($NIMM -d $DB -x 'w $G(^FST("load","test.xml"))' 2>&1)
if [ "$STATUS" = "in-progress" ]; then
  pass "Load marked in-progress"
else
  fail "Load marked in-progress" "in-progress" "$STATUS"
fi

# Test 3: Simulate load complete — mark complete with count
echo "--- Test: Mark complete ---"
$NIMM -d $DB -x 'SET ^FST("load","test.xml")="complete:12345"' > /dev/null 2>&1
STATUS=$($NIMM -d $DB -x 'w $G(^FST("load","test.xml"))' 2>&1)
if [ "$STATUS" = "complete:12345" ]; then
  pass "Load marked complete:12345"
else
  fail "Load marked complete:12345" "complete:12345" "$STATUS"
fi

# Test 4: Multiple files tracked independently
echo "--- Test: Multiple files ---"
$NIMM -d $DB -x 'SET ^FST("load","mesh.xml")="complete:5000",^FST("load","pubmed.xml")="in-progress",^FST("load","catline.xml")="complete:1200"' > /dev/null 2>&1

MESH=$($NIMM -d $DB -x 'w $G(^FST("load","mesh.xml"))' 2>&1)
PUB=$($NIMM -d $DB -x 'w $G(^FST("load","pubmed.xml"))' 2>&1)
CAT=$($NIMM -d $DB -x 'w $G(^FST("load","catline.xml"))' 2>&1)
if [ "$MESH" = "complete:5000" ] && [ "$PUB" = "in-progress" ] && [ "$CAT" = "complete:1200" ]; then
  pass "Multiple files tracked independently"
else
  fail "Multiple files tracked independently" "complete:5000 / in-progress / complete:1200" "$MESH / $PUB / $CAT"
fi

# Test 5: Detect incomplete loads
echo "--- Test: Detect incomplete loads ---"
INCOMPLETE=$($NIMM -r /tmp/DETECT.m -d $DB -e 'DO DETECT^DETECT' 2>&1)
if [ "$INCOMPLETE" = "pubmed.xml " ]; then
  pass "Detected incomplete load: pubmed.xml"
else
  fail "Detected incomplete load" "pubmed.xml " "$INCOMPLETE"
fi

# Test 6: No incomplete loads after all complete
echo "--- Test: All complete ---"
$NIMM -d $DB -x 'SET ^FST("load","pubmed.xml")="complete:99999"' > /dev/null 2>&1
INCOMPLETE=$($NIMM -r /tmp/DETECT.m -d $DB -e 'DO DETECT^DETECT' 2>&1)
if [ -z "$INCOMPLETE" ]; then
  pass "No incomplete loads after all complete"
else
  fail "No incomplete loads" "(empty)" "$INCOMPLETE"
fi

# Test 7: Real ZLOADXML integration — marks load complete with count
echo "--- Test: ZLOADXML marks load complete ---"
cat > /tmp/loadstate_fixture.xml << 'XEOF'
<?xml version="1.0"?>
<DescriptorRecordSet>
<DescriptorRecord>
<DescriptorUI>D000001</DescriptorUI>
<DescriptorName><String>Hypertension</String></DescriptorName>
</DescriptorRecord>
<DescriptorRecord>
<DescriptorUI>D000002</DescriptorUI>
<DescriptorName><String>Diabetes</String></DescriptorName>
</DescriptorRecord>
</DescriptorRecordSet>
XEOF
RESULT=$($NIMM -d $DB -x 'ZLOADXML "/tmp/loadstate_fixture.xml","^MESH","mesh" W $G(^FST("load","loadstate_fixture.xml"))' 2>&1 | tail -1)
if [ "$RESULT" = "complete:2" ]; then
  pass "ZLOADXML marks load complete:2"
else
  fail "ZLOADXML marks load complete" "complete:2" "$RESULT"
fi

# Test 8: Loaded records are present
echo "--- Test: Loaded records present ---"
MESH_NAME=$($NIMM -d $DB -x 'w $G(^MESH("D000001","name"))' 2>&1)
if [ "$MESH_NAME" = "Hypertension" ]; then
  pass "ZLOADXML loaded records correctly"
else
  fail "ZLOADXML loaded records" "Hypertension" "$MESH_NAME"
fi

echo ""
echo "Result: $PASSED passed, $FAILED failed"
if [ $FAILED -gt 0 ]; then
  echo "=== Some tests FAILED ==="
  exit 1
else
  echo "=== All tests passed ==="
fi
