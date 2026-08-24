#!/bin/bash
# test_fst.sh — Test FST data loading and search functionality
# Usage: ./tests/test_fst.sh

set -e

DB="/tmp/test_fst_$$"
NIMM="./nimm"
LOADER="python3 future_search_tool/src/fst_load.py"
DATA_DIR="/Users/mark/_diary-data"

echo "=== FST Test Suite ==="
echo "Database: $DB"
echo

# Cleanup
cleanup() {
    rm -f "$DB" "$DB-lock"
}
trap cleanup EXIT

# Test1: Load small MeSH subset
echo "Test 1: Load MeSH descriptors (10 records)"
$LOADER --db "$DB" --data-dir "$DATA_DIR" --skip catline serline pubmed --max-records 10
echo "  PASS: MeSH loaded"

# Test2: Verify data integrity
echo "Test 2: Verify MeSH data"
RESULT=$($NIMM -d "$DB" -x 'W ^MESH("D000001","name")')
if [ "$RESULT" = "Calcimycin" ]; then
    echo "  PASS: D000001 = Calcimycin"
else
    echo "  FAIL: Expected 'Calcimycin', got '$RESULT'"
    exit 1
fi

# Test3: Verify tree numbers
echo "Test 3: Verify tree numbers"
RESULT=$($NIMM -d "$DB" -x 'S t="" F  S t=$O(^MESH("D000001","treeNumber",t)) Q:t=""  W t," "')
if echo "$RESULT" | grep -q "D02.540.576.625.125"; then
    echo "  PASS: Tree numbers present"
else
    echo "  FAIL: Tree numbers missing"
    exit 1
fi

# Test4: Verify qualifiers
echo "Test 4: Verify qualifiers"
RESULT=$($NIMM -d "$DB" -x 'W ^QUAL("Q000002","name")')
if [ "$RESULT" = "abnormalities" ]; then
    echo "  PASS: Q000002 = abnormalities"
else
    echo "  FAIL: Expected 'abnormalities', got '$RESULT'"
    exit 1
fi

# Test5: Verify FST status
echo "Test 5: Verify FST status"
RESULT=$($NIMM -d "$DB" -x 'W ^FST("status")')
if [ "$RESULT" = "loaded" ]; then
    echo "  PASS: FST status = loaded"
else
    echo "  FAIL: Expected 'loaded', got '$RESULT'"
    exit 1
fi

# Test6: Verify record count
echo "Test 6: Verify record count"
RESULT=$($NIMM -d "$DB" -x 'W ^FST("records")')
if [ "$RESULT" -gt 0 ] 2>/dev/null; then
    echo "  PASS: Records = $RESULT"
else
    echo "  FAIL: Invalid record count: $RESULT"
    exit 1
fi

echo
echo "=== All FST tests passed ==="
