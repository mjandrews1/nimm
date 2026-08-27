#!/bin/bash
# test_lint.sh — Verify #384: linter (ZANALYZE + --lint / --lint-strict)
# Usage: ./tests/test_lint.sh

set -euo pipefail
NIMM="${1:-./bin/nimm}"
PASS=0; FAIL=0

check() {
  local label="$1" pattern="$2" actual="$3"
  if echo "$actual" | grep -q "$pattern"; then
    echo "  PASS: $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label (expected pattern '$pattern' not in output)"
    echo "    actual: '$actual'"
    FAIL=$((FAIL+1))
  fi
}

echo "=== #384: Linter ==="

# --- ZANALYZE checks ---

# Test 1: unused variable detection (W001)
cat > /tmp/lint1.m << 'EOF'
MAIN ;
 SET X=1
 SET Y=2
 WRITE X,!
 QUIT
EOF
OUT=$($NIMM -r /tmp/lint1.m -e 'ZANALYZE' 2>&1)
check "Unused variable (W001)" "W001" "$OUT"

# Test 2: undefined label detection (W003)
cat > /tmp/lint2.m << 'EOF'
MAIN ;
 WRITE "hi",!
 DO MISSING
 QUIT
EOF
OUT=$($NIMM -r /tmp/lint2.m -e 'ZANALYZE' 2>&1)
check "Undefined label (W003)" "W003" "$OUT"

# Test 3: unreachable code after QUIT (W002)
cat > /tmp/lint3.m << 'EOF'
MAIN ;
 WRITE "hi",!
 QUIT
 WRITE "unreachable",!
EOF
OUT=$($NIMM -r /tmp/lint3.m -e 'ZANALYZE' 2>&1)
check "Unreachable code (W002)" "W002" "$OUT"

# Test 4: unused label detection (W004)
cat > /tmp/lint4.m << 'EOF'
MAIN ;
 WRITE "hi",!
 QUIT
DEAD ;
 QUIT
EOF
OUT=$($NIMM -r /tmp/lint4.m -e 'ZANALYZE' 2>&1)
check "Unused label (W004)" "W004" "$OUT"

# Test 5: clean code has 0 warnings
cat > /tmp/lint5.m << 'EOF'
MAIN ;
 SET X=1
 WRITE X,!
 QUIT
EOF
OUT=$($NIMM -r /tmp/lint5.m -e 'ZANALYZE' 2>&1)
if echo "$OUT" | grep -q "0 warnings"; then
  echo "  PASS: Clean code has 0 warnings"
  PASS=$((PASS+1))
else
  echo "  FAIL: Clean code should have 0 warnings"
  echo "    actual: '$OUT'"
  FAIL=$((FAIL+1))
fi

# Test 6: report includes a summary line
OUT=$($NIMM -r /tmp/lint1.m -e 'ZANALYZE' 2>&1)
check "Report has summary" "Summary:" "$OUT"

# --- --lint / --lint-strict CLI ---

# Test 7: --lint -r prints report without executing (no output side-effects)
OUT=$($NIMM --lint -r /tmp/lint3.m 2>&1)
check "--lint prints W002" "W002" "$OUT"
if echo "$OUT" | grep -q '^hi'; then
  echo "  FAIL: --lint should not execute routine (WRITE 'hi' leaked)"
  FAIL=$((FAIL+1))
else
  echo "  PASS: --lint does not execute (no WRITE output)"
  PASS=$((PASS+1))
fi

# Test 8: --lint-strict exits non-zero on warnings
if $NIMM --lint-strict -r /tmp/lint1.m > /dev/null 2>&1; then
  echo "  FAIL: --lint-strict should exit non-zero on warnings"
  FAIL=$((FAIL+1))
else
  echo "  PASS: --lint-strict exits non-zero on warnings"
  PASS=$((PASS+1))
fi

# Test 9: --lint on clean code exits zero
if $NIMM --lint -r /tmp/lint5.m > /dev/null 2>&1; then
  echo "  PASS: --lint exits zero on clean code"
  PASS=$((PASS+1))
else
  echo "  FAIL: --lint should exit zero on clean code"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
