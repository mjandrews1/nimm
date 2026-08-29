#!/bin/bash
# test_zloadxml_catline.sh — Test ZLOADXML with CatLine data
# Usage: ./tests/test_zloadxml_catline.sh [data_dir]

set -e

DATA_DIR="${1:-/Users/mark/_diary-data}"
DB="/tmp/test_catline_$$.lmdb"
NIMM="${1:-./bin/nimm}"

echo "=== ZLOADXML CatLine Test Suite ==="
echo "Database: $DB"
echo "Data directory: $DATA_DIR"
echo

# Cleanup
cleanup() {
    rm -f "$DB" "$DB-lock"
}
trap cleanup EXIT

# Test1: Load small CatLine file
echo "Test 1: Load small CatLine file"
# Create small test file
python3 -c "
import xml.etree.ElementTree as ET
ns = {'marc': 'http://www.loc.gov/MARC21/slim'}
tree = ET.parse('$DATA_DIR/nlm-staging/catplus-marcxml/catplus.20260701.marcxml.xml')
root = tree.getroot()
with open('/tmp/small_catline.xml', 'w') as f:
    f.write('<?xml version=\"1.0\"?>\n<marc:collection xmlns:marc=\"http://www.loc.gov/MARC21/slim\">\n')
    count = 0
    for rec in root.findall('.//marc:record', ns):
        if count >= 3: break
        nlm_id = ''
        for cf in rec.findall('marc:controlfield', ns):
            if cf.get('tag') == '001':
                nlm_id = cf.text.strip() if cf.text else ''
                break
        title = ''
        for df in rec.findall('marc:datafield', ns):
            if df.get('tag') == '245':
                for sf in df.findall('marc:subfield', ns):
                    if sf.get('code') == 'a':
                        title = sf.text.strip() if sf.text else ''
                        break
                break
        if nlm_id and title:
            f.write(f'<marc:record><marc:controlfield tag=\"001\">{nlm_id}</marc:controlfield><marc:datafield tag=\"245\"><marc:subfield code=\"a\">{title}</marc:subfield></marc:datafield></marc:record>\n')
            count += 1
    f.write('</marc:collection>\n')
print(f'Created /tmp/small_catline.xml with {count} records')
" 2>&1

RESULT=$($NIMM -d "$DB" -x 'ZLOADXML "/tmp/small_catline.xml","^CATLINE","catline" W $G(^ZLOADXML)' | tail -1)
if [ "$RESULT" = "3" ]; then
    echo "  PASS: Loaded 3 records"
else
    echo "  FAIL: Expected 3, got '$RESULT'"
    exit 1
fi

# Test2: Verify data integrity
echo "Test 2: Verify data integrity"
RESULT=$($NIMM -d "$DB" -x 'W $G(^CATLINE("9919264005306676","title"))' | tail -1)
if echo "$RESULT" | grep -q "manual of personal hygiene"; then
    echo "  PASS: Title present"
else
    echo "  FAIL: Title missing, got '$RESULT'"
    exit 1
fi

# Test3: Load full CatLine (timing test)
echo "Test 3: Load full CatLine (timing test)"
rm -f "$DB" "$DB-lock"
START=$(date +%s)
$NIMM -d "$DB" -x "ZLOADXML \"$DATA_DIR/nlm-staging/catplus-marcxml/catplus.20260701.marcxml.xml\",\"^CATLINE\",\"catline\"" > /dev/null 2>&1
END=$(date +%s)
ELAPSED=$((END - START))
echo "  INFO: Loaded in $ELAPSED seconds"

# Test4: Verify full load
echo "Test 4: Verify full load"
RESULT=$($NIMM -d "$DB" -x 'W $G(^CATLINE("9919264005306676","title"))' | tail -1)
if echo "$RESULT" | grep -q "manual of personal hygiene"; then
    echo "  PASS: First record present"
else
    echo "  FAIL: First record missing"
    exit 1
fi

echo
echo "=== All ZLOADXML CatLine tests passed ==="
