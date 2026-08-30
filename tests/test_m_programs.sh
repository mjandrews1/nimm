#!/usr/bin/env bash
# test_m_programs.sh — Runtime mirror for formal/m_programs.dfy.
# Runs each deterministic M script and checks its computed output.
# Environment/I-O-dependent scripts (test_ni, test_special, test_job, eric_*,
# bm25idx) are covered separately or documented as non-deterministic.
set -euo pipefail
NIMM="${1:-./bin/nimm}"
PASS=0; FAIL=0

check_contains() {
  local label="$1" needle="$2" actual="$3"
  if echo "$actual" | grep -qF "$needle"; then
    echo "  PASS: $label"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $label (expected '$needle' in output)"
    echo "    got: $actual"
    FAIL=$((FAIL+1))
  fi
}

echo "=== M program verification mirrors ==="

# samples/hello.m
OUT=$($NIMM -r samples/hello.m -x 'DO HELLO' 2>&1)
check_contains "hello.m greeting" 'Hello from a routine file!' "$OUT"

# tests/test.m (ENTRY: X+Y=30)
OUT=$($NIMM -r tests/test.m -x 'DO ENTRY' 2>&1)
check_contains "test.m X+Y=30" 'X + Y = 30' "$OUT"

# tests/test_batch.m
OUT=$($NIMM -r tests/test_batch.m -x 'DO ENTRY' 2>&1)
check_contains "test_batch.m X+Y=30" 'X + Y = 30' "$OUT"

# samples/labeled.m (FOR loop sum 1..5 = 15)
OUT=$($NIMM -r samples/labeled.m -x 'DO LABELED' 2>&1)
check_contains "labeled.m SUM=15" 'SUM=15' "$OUT"
check_contains "labeled.m PASS-LOOP" 'PASS-LOOP' "$OUT"

# samples/strict.m (FizzBuzz + string tour)
OUT=$($NIMM -r samples/strict.m -x 'DO STRICT' 2>&1)
check_contains "strict.m FizzBuzz" 'FizzBuzz' "$OUT"
check_contains "strict.m string tour" 'ANSI|M|19|ISNA' "$OUT"

# samples/rsmext.m (exponent + numeric collation)
OUT=$($NIMM -r samples/rsmext.m -x 'DO RSMEXT' 2>&1)
check_contains "rsmext.m exponents" '2000 100 4000 -2000 1' "$OUT"
check_contains "rsmext.m collation" '2,10,30,A' "$OUT"

# tests/test_ctrl_transfer.m (GOTO skips, DO transfers)
OUT=$($NIMM -r tests/test_ctrl_transfer.m -x 'DO GO' 2>&1)
check_contains "ctrl_transfer GO" '1' "$OUT"
OUT=$($NIMM -r tests/test_ctrl_transfer.m -x 'DO DOIT' 2>&1)
check_contains "ctrl_transfer DOIT" '6' "$OUT"

# tests/test_functions.m (intrinsic functions)
OUT=$($NIMM -r tests/test_functions.m -x 'DO ENTRY' 2>&1)
check_contains "functions \$ASCII" '$ASCII: 65' "$OUT"
check_contains "functions \$EXTRACT" '$EXTRACT: ell' "$OUT"
check_contains "functions \$FIND" '$FIND: 4' "$OUT"
check_contains "functions \$PIECE" '$PIECE: b' "$OUT"
check_contains "functions \$TRANSLATE" '$TRANSLATE: HELLo' "$OUT"
check_contains "functions \$FNUMBER" '$FNUMBER: 1,234.57' "$OUT"

# tests/test_data_structures.m (stack/queue/set/object)
OUT=$($NIMM -r tests/test_data_structures.m -x 'DO ENTRY' 2>&1)
check_contains "data_structures stack peek" 'Stack peek: second' "$OUT"
check_contains "data_structures queue peek" 'Queue peek: first' "$OUT"
check_contains "data_structures set len" 'Set len: 2' "$OUT"
check_contains "data_structures array len" 'Array len: 2' "$OUT"

# samples/nimmext.m (array -> bag -> sorted tally)
OUT=$($NIMM -r samples/nimmext.m -x 'DO NIMMEXT' 2>&1)
check_contains "nimmext tally" 'apple:2,banana:1,cherry:1' "$OUT"
check_contains "nimmext totals" 'total=4 raw=4' "$OUT"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
