#!/bin/bash
# test_zloadxml.sh — Test ZLOADXML command (self-contained)
# Generates its own fixture files; requires MeSH XML in DATA_DIR.
# Usage: ./tests/test_zloadxml.sh [data_dir]

set -e

NIMM="./nimm"
DATA_DIR="${1:-/Users/mark/_diary-data}"
FIXTURE="/tmp/test_zloadxml_fixture_$$"

echo "=== ZLOADXML Test Suite ==="
echo

# Cleanup
cleanup() {
    rm -f "$FIXTURE" /tmp/test_zloadxml_*_$$ "$DB-lock"
}
trap cleanup EXIT
DB=""

# --- Fixture generation ---
echo "Generating fixtures..."
if [ ! -f "$DATA_DIR/mesh-staging/xml/desc2026.xml" ]; then
    echo "  FAIL: $DATA_DIR/mesh-staging/xml/desc2026.xml not found"
    exit 1
fi
python3 -c "
import xml.etree.ElementTree as ET
tree = ET.parse('$DATA_DIR/mesh-staging/xml/desc2026.xml')
root = tree.getroot()
with open('$FIXTURE', 'w') as f:
    f.write('<?xml version=\"1.0\"?>\n<DescriptorRecordSet>\n')
    count = 0
    for rec in root.findall('.//DescriptorRecord'):
        if count >= 2: break
        ui = rec.findtext('DescriptorUI', '')
        name = rec.findtext('DescriptorName/String', '')
        trees = [t.text for t in rec.findall('.//TreeNumber') if t.text]
        scope = rec.findtext('ScopeNote', '') or ''
        f.write('<DescriptorRecord>')
        f.write(f'<DescriptorUI>{ui}</DescriptorUI>')
        f.write(f'<DescriptorName><String>{name}</String></DescriptorName>')
        for t in trees[:2]:
            f.write(f'<TreeNumber>{t}</TreeNumber>')
        f.write('</DescriptorRecord>\n')
        count += 1
    f.write('</DescriptorRecordSet>\n')
print('  Fixture created')
"

# Test1: Load small MeSH file
echo "Test 1: Load small MeSH file"
DB="/tmp/test_zloadxml_1_$$"
RESULT=$($NIMM -d "$DB" -x "ZLOADXML \"$FIXTURE\",\"^MESH\",\"mesh\" W \$G(^ZLOADXML)" | tail -1)
rm -f "$DB" "$DB-lock"; DB=""
if [ "$RESULT" = "2" ]; then
    echo "  PASS: Loaded 2 records"
else
    echo "  FAIL: Expected 2, got '$RESULT'"
    exit 1
fi

# Test2: Verify name field
echo "Test 2: Verify name field"
DB="/tmp/test_zloadxml_2_$$"
RESULT=$($NIMM -d "$DB" -x "ZLOADXML \"$FIXTURE\",\"^MESH\",\"mesh\" W \$G(^MESH(\"D000001\",\"name\"))" | tail -1)
rm -f "$DB" "$DB-lock"; DB=""
if [ "$RESULT" = "Calcimycin" ]; then
    echo "  PASS: D000001 = Calcimycin"
else
    echo "  FAIL: Expected Calcimycin, got '$RESULT'"
    exit 1
fi

# Test3: Verify tree numbers stored
echo "Test 3: Verify tree numbers stored"
DB="/tmp/test_zloadxml_3_$$"
RESULT=$($NIMM -d "$DB" -x "ZLOADXML \"$FIXTURE\",\"^MESH\",\"mesh\" W \$DATA(^MESH(\"D000001\",\"treeNumber\"))" | tail -1)
rm -f "$DB" "$DB-lock"; DB=""
if [ "$RESULT" != "0" ] && [ -n "$RESULT" ]; then
    echo "  PASS: Tree numbers present (\$DATA=$RESULT)"
else
    echo "  FAIL: No tree numbers found"
    exit 1
fi

# Test4: Load MeSH qualifiers from real file
echo "Test 4: Load MeSH qualifiers"
DB="/tmp/test_zloadxml_4_$$"
RESULT=$($NIMM -d "$DB" -x "ZLOADXML \"$DATA_DIR/mesh-staging/xml/qual2026.xml\",\"^QUAL\",\"qualifier\" W \$G(^QUAL(\"Q000002\",\"name\"))" | tail -1)
rm -f "$DB" "$DB-lock"; DB=""
if [ "$RESULT" = "abnormalities" ]; then
    echo "  PASS: Q000002 = abnormalities"
else
    echo "  FAIL: Expected abnormalities, got '$RESULT'"
    exit 1
fi

# Test5: Unknown format rejected
echo "Test 5: Unknown format rejected"
DB="/tmp/test_zloadxml_5_$$"
RESULT=$($NIMM -d "$DB" -x "ZLOADXML \"$FIXTURE\",\"^X\",\"bogus-format\" W \"ok\"" 2>&1 | grep -c "error")
rm -f "$DB" "$DB-lock"; DB=""
if [ "$RESULT" -ge 1 ]; then
    echo "  PASS: Error reported for unknown format"
else
    echo "  FAIL: No error for bogus format"
    exit 1
fi

# Test6: Missing file reported
echo "Test 6: Missing file reported"
DB="/tmp/test_zloadxml_6_$$"
RESULT=$($NIMM -d "$DB" -x "ZLOADXML \"/nonexistent/file.xml\",\"^X\",\"mesh\" W \"ok\"" 2>&1 | grep -c "error")
rm -f "$DB" "$DB-lock"; DB=""
if [ "$RESULT" -ge 1 ]; then
    echo "  PASS: Error reported for missing file"
else
    echo "  FAIL: No error for missing file"
    exit 1
fi

echo
echo "=== All ZLOADXML tests passed ==="
