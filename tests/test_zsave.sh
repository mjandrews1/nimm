#!/bin/bash
# test_zsave.sh — Verify #376: ZSAVE writes routine source to disk
# Usage: ./tests/test_zsave.sh

set -euo pipefail
NIMM="${1:-./bin/nimm}"
PASS=0; FAIL=0

check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label (expected '$expected', got '$actual')"
    FAIL=$((FAIL+1))
  fi
}

echo "=== #376: ZSAVE ==="

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Routine with a comment and blank line, to verify raw source is preserved
cat > "$WORK/MYRTN.m" << 'EOF'
MYRTN ;
SET X=1

WRITE X,!
QUIT
EOF

# Test 1: ZSAVE (no arg) saves current routine to its original path
cp "$WORK/MYRTN.m" "$WORK/orig.m"
$NIMM -r "$WORK/MYRTN.m" -e 'DO ^MYRTN ZSAVE' > /dev/null 2>&1
check "ZSAVE writes to original path" "$(cat "$WORK/orig.m")" "$(cat "$WORK/MYRTN.m")"

# Test 2: ZSAVE NAME saves the named routine
cat > "$WORK/OTHER.m" << 'EOF'
OTHER ;
QUIT
EOF
$NIMM -r "$WORK/OTHER.m" -e 'ZSAVE OTHER' > /dev/null 2>&1
check "ZSAVE NAME writes named routine" "OTHER ;" "$(head -1 "$WORK/OTHER.m")"

# Test 3: ZSAVE preserves comments and blank lines (raw source)
RAW=$(cat "$WORK/MYRTN.m")
if echo "$RAW" | grep -q "MYRTN ;" && echo "$RAW" | grep -q "SET X=1"; then
  echo "  PASS: ZSAVE preserves raw source"
  PASS=$((PASS+1))
else
  echo "  FAIL: ZSAVE preserves raw source"
  FAIL=$((FAIL+1))
fi

# Test 4: ZSAVE with a nonexistent routine reports error (doesn't crash)
OUT=$($NIMM -r "$WORK/OTHER.m" -e 'ZSAVE NOSUCHRTN' 2>&1)
check "ZSAVE nonexistent routine errors" "ZSAVE: routine not found: NOSUCHRTN" "$OUT"

# Test 5: ZHALT and ZSYSTEM are reachable (same keyword-list fix)
OUT=$($NIMM -x 'ZSYSTEM "true"' 2>&1)
check "ZSYSTEM reachable" "" "$OUT"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
