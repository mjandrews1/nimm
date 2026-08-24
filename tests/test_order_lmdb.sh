#!/bin/bash
# test_order_lmdb.sh — Regression tests for $ORDER with LMDB storage
# Tests fix for #355 ($ORDER skips first key)
# Usage: ./tests/test_order_lmdb.sh

set -e

NIMM="./nimm"

echo "=== \$ORDER LMDB Test Suite ==="
echo

# Test1: Forward $ORDER from empty string
echo "Test 1: Forward \$ORDER from empty string"
DB="/tmp/test_order_1_$$"
RESULT=$($NIMM -d "$DB" -x 'S ^T("A")=1 S ^T("B")=2 S ^T("C")=3 W $O(^T(""))')
rm -f "$DB" "$DB-lock"
if [ "$RESULT" = "A" ]; then
    echo "  PASS"
else
    echo "  FAIL: Expected A, got '$RESULT'"
    exit 1
fi

# Test2: Forward $ORDER iteration
echo "Test 2: Forward \$ORDER iteration"
DB="/tmp/test_order_2_$$"
RESULT=$($NIMM -d "$DB" -x 'S ^T("A")=1 S ^T("B")=2 S ^T("C")=3 W $O(^T("A"))," ",$O(^T("B"))," ",$O(^T("C"))')
rm -f "$DB" "$DB-lock"
if [ "$RESULT" = "B C " ]; then
    echo "  PASS"
else
    echo "  FAIL: Expected 'B C ', got '$RESULT'"
    exit 1
fi

# Test3: Reverse $ORDER from last key
echo "Test 3: Reverse \$ORDER from last key"
DB="/tmp/test_order_3_$$"
RESULT=$($NIMM -d "$DB" -x 'S ^T("A")=1 S ^T("B")=2 S ^T("C")=3 W $O(^T("C"),-1)')
rm -f "$DB" "$DB-lock"
if [ "$RESULT" = "B" ]; then
    echo "  PASS"
else
    echo "  FAIL: Expected B, got '$RESULT'"
    exit 1
fi

# Test4: Reverse $ORDER from empty string (§9.9: returns empty)
echo "Test 4: Reverse \$ORDER from empty string"
DB="/tmp/test_order_4_$$"
RESULT=$($NIMM -d "$DB" -x 'S ^T("A")=1 S ^T("B")=2 S ^T("C")=3 W $O(^T(""),-1)')
rm -f "$DB" "$DB-lock"
if [ "$RESULT" = "" ]; then
    echo "  PASS"
else
    echo "  FAIL: Expected empty, got '$RESULT'"
    exit 1
fi

# Test5: LMDB vs in-memory consistency
echo "Test 5: LMDB vs in-memory consistency"
DB="/tmp/test_order_5_$$"
LMDB_RESULT=$($NIMM -d "$DB" -x 'S ^T("A")=1 S ^T("B")=2 S ^T("C")=3 W $O(^T("")),",",$O(^T("A")),",",$O(^T("B")),",",$O(^T("C"))')
rm -f "$DB" "$DB-lock"
MEM_RESULT=$($NIMM -x 'K ^T S ^T("A")=1 S ^T("B")=2 S ^T("C")=3 W $O(^T("")),",",$O(^T("A")),",",$O(^T("B")),",",$O(^T("C"))')
if [ "$LMDB_RESULT" = "$MEM_RESULT" ]; then
    echo "  PASS"
else
    echo "  FAIL: LMDB='$LMDB_RESULT' vs in-memory='$MEM_RESULT'"
    exit 1
fi

# Test6: Single key
echo "Test 6: Single key"
DB="/tmp/test_order_6_$$"
RESULT=$($NIMM -d "$DB" -x 'S ^T("X")=1 W $O(^T("")),",",$O(^T("X"))')
rm -f "$DB" "$DB-lock"
if [ "$RESULT" = "X," ]; then
    echo "  PASS"
else
    echo "  FAIL: Expected 'X,', got '$RESULT'"
    exit 1
fi

# Test7: Empty global
echo "Test 7: Empty global"
DB="/tmp/test_order_7_$$"
RESULT=$($NIMM -d "$DB" -x 'W $O(^T(""))')
rm -f "$DB" "$DB-lock"
if [ "$RESULT" = "" ]; then
    echo "  PASS"
else
    echo "  FAIL: Expected empty, got '$RESULT'"
    exit 1
fi

echo
echo "=== All \$ORDER LMDB tests passed ==="
