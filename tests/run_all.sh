#!/bin/bash
# run_all.sh — Rebuild the binary, then run the full fast test suite.
# Long-running (soak_018, overnight) and data/network-dependent suites are
# NOT included here; run those separately.
# Usage: ./tests/run_all.sh

set -euo pipefail
cd "$(dirname "$0")/.."

NIMM="./bin/nimm"

# Fast, self-contained shell suites (each takes the binary as $1).
SHELL_SUITES=(
    test_zmisc test_scripting test_zwrite test_scoping
    test_key_encoding test_order_lmdb test_lint
    test_store_parity
    test_bytecode_conformance test_bytecode_kill test_bytecode_control
    test_bytecode_subscripts test_bytecode_fallback
    test_zconvert test_ni_system test_zsave test_zallocate
    test_pemdas test_txn_lmdb test_tcommit_scope test_ni_structures
    test_mode_gates test_unwired_args test_for_zeof
    test_zinspect test_introspection test_source test_errorloc
    test_txn_reads test_mcp_introspection test_mcp_auth
    test_etrap
)

echo "=== NimM Test Runner (fresh binary) ==="
echo

echo "--- Build: nim c -d:release -o:bin/nimm main.nim ---"
if ! nim c -d:release -o:bin/nimm main.nim; then
    echo "BUILD FAILED"
    exit 1
fi
echo "Build OK."
echo

PASS=0
FAIL=0
FAILED=""

run_suite() {
    local suite="$1"
    local log
    log="$(mktemp /tmp/run_all_XXXXXX.log)"
    echo "--- tests/$suite.sh ---"
    if bash "tests/$suite.sh" "$NIMM" >"$log" 2>&1; then
        echo "  RESULT: PASS"
        PASS=$((PASS + 1))
    else
        echo "  RESULT: FAIL"
        FAIL=$((FAIL + 1))
        FAILED="$FAILED $suite"
        tail -5 "$log" | sed 's/^/    /'
    fi
    rm -f "$log"
    echo
}

for suite in "${SHELL_SUITES[@]}"; do
    run_suite "$suite"
done

echo "--- nim unit tests (tests/test_*.nim) ---"
for t in tests/test_*.nim; do
    name="$(basename "$t" .nim)"
    echo "  $name:"
    if nim c -r "$t" >/dev/null 2>&1; then
        echo "    PASS"
        PASS=$((PASS + 1))
    else
        echo "    FAIL"
        FAIL=$((FAIL + 1))
        FAILED="$FAILED $name"
    fi
done
echo

echo "=== Summary: $PASS passed, $FAIL failed ==="
if [ $FAIL -gt 0 ]; then
    echo "Failed:$FAILED"
    exit 1
fi
