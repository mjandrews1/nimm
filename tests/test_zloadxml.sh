#!/bin/bash
# test_zloadxml.sh — Test ZLOADXML command
# Usage: ./tests/test_zloadxml.sh

set -e

NIMM="./nimm"

echo "=== ZLOADXML Test Suite ==="
echo

# Test1: Load small MeSH file
echo "Test 1: Load small MeSH file"
DB="/tmp/test_zloadxml_1_$$"
RESULT=$($NIMM -d "$DB" -x 'ZLOADXML "/tmp/small_mesh.xml","^MESH","mesh" W $G(^ZLOADXML)' | tail -1)
rm -f "$DB" "$DB-lock"
if [ "$RESULT" = "3" ]; then
    echo "  PASS: Loaded 3 records"
else
    echo "  FAIL: Expected 3, got '$RESULT'"
    exit 1
fi

# Test2: Verify data integrity
echo "Test 2: Verify data integrity"
DB="/tmp/test_zloadxml_2_$$"
RESULT=$($NIMM -d "$DB" -x 'ZLOADXML "/tmp/small_mesh.xml","^MESH","mesh" W $G(^MESH("D000001","name"))' | tail -1)
rm -f "$DB" "$DB-lock"
if [ "$RESULT" = "Calcimycin" ]; then
    echo "  PASS: D000001 = Calcimycin"
else
    echo "  FAIL: Expected Calcimycin, got '$RESULT'"
    exit 1
fi

# Test3: Verify qualifiers (small file has no tree numbers)
echo "Test 3: Verify qualifiers"
DB="/tmp/test_zloadxml_3_$$"
RESULT=$($NIMM -d "$DB" -x 'ZLOADXML "/Users/mark/_diary-data/mesh-staging/xml/qual2026.xml","^QUAL","qualifier" W $G(^QUAL("Q000002","name"))' | tail -1)
rm -f "$DB" "$DB-lock"
if [ "$RESULT" = "abnormalities" ]; then
    echo "  PASS: Q000002 = abnormalities"
else
    echo "  FAIL: Expected abnormalities, got '$RESULT'"
    exit 1
fi

# Test4: Verify qualifier data
echo "Test 4: Verify qualifier data"
DB="/tmp/test_zloadxml_4_$$"
RESULT=$($NIMM -d "$DB" -x 'ZLOADXML "/Users/mark/_diary-data/mesh-staging/xml/qual2026.xml","^QUAL","qualifier" W $G(^QUAL("Q000002","name"))' | tail -1)
rm -f "$DB" "$DB-lock"
if [ "$RESULT" = "abnormalities" ]; then
    echo "  PASS: Q000002 = abnormalities"
else
    echo "  FAIL: Expected abnormalities, got '$RESULT'"
    exit 1
fi

echo
echo "=== All ZLOADXML tests passed ==="
