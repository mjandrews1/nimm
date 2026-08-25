#!/bin/bash
# run_all.sh — Run all fast FST/storage test suites and report summary.
# Long-running suites (soak_018, overnight) are NOT included; run separately.
# Usage: ./tests/run_all.sh [data_dir]

DATA_DIR="${1:-/Users/mark/_diary-data}"
cd "$(dirname "$0")/.."

declare -a SUITES=(
    "tests/test_fst.sh"
    "tests/test_order_lmdb.sh"
    "tests/test_zloadxml.sh"
    "tests/test_zloadxml_catline.sh"
)

PASS=0
FAIL=0
FAILED_SUITES=""

echo "=== NimM Test Runner ==="
echo

for suite in "${SUITES[@]}"; do
    if [ ! -x "$suite" ]; then
        echo "SKIP: $suite (not executable)"
        continue
    fi
    echo "--- $suite ---"
    if "$suite" "$DATA_DIR" > /tmp/run_all_$$\.log 2>&1; then
        echo "  RESULT: PASS"
        PASS=$((PASS + 1))
    else
        echo "  RESULT: FAIL"
        FAIL=$((FAIL + 1))
        FAILED_SUITES="$FAILED_SUITES $suite"
        tail -5 /tmp/run_all_$$\.log | sed 's/^/    /'
    fi
    echo
done

rm -f /tmp/run_all_$$\.log
echo "=== Summary: $PASS passed, $FAIL failed ==="
if [ $FAIL -gt 0 ]; then
    echo "Failed suites:$FAILED_SUITES"
    exit 1
fi
