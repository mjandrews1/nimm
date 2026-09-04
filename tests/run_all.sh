#!/bin/bash
# run_all.sh — Rebuild the binary, then run the full fast test suite.
# Long-running (soak_018, overnight) and data/network-dependent suites are
# NOT included here; run those separately.
# Usage: ./tests/run_all.sh

set -euo pipefail
cd "$(dirname "$0")/.."

NIMM="./bin/nimm"

# Fast, self-contained shell suites (each takes the binary as $1).
# Kept alphabetically sorted so the run order doubles as a progress indicator.
SHELL_SUITES=(
    test_bytecode_conformance
    test_bytecode_control
    test_bytecode_fallback
    test_bytecode_kill
    test_bytecode_subscripts
    test_crash_recovery
    test_errorloc
    test_etrap
    test_for_zeof
    test_fst_integrity
    test_introspection
    test_key_encoding
    test_lint
    test_m_programs
    test_mcp_auth
    test_mcp_introspection
    test_mode_gates
    test_ni_search
    test_ni_bool
    test_ni_sql
    test_ni_structures
    test_ni_system
    test_order_lmdb
    test_pemdas
    test_refresh
    test_scoping
    test_scripting
    test_source
    test_special_vars
    test_store_parity
    test_string_functions
    test_tcommit_scope
    test_txn_lmdb
    test_txn_reads
    test_unwired_args
    test_zallocate
    test_zconvert
    test_zinspect
    test_zmisc
    test_zsave
    test_zwrite
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
TESTBIN="$(mktemp -d /tmp/nimm_tests.XXXXXX)"
for t in tests/test_*.nim; do
    name="$(basename "$t" .nim)"
    echo "  $name:"
    if nim c -r --outdir:"$TESTBIN" "$t" >/dev/null 2>&1; then
        echo "    PASS"
        PASS=$((PASS + 1))
    else
        echo "    FAIL"
        FAIL=$((FAIL + 1))
        FAILED="$FAILED $name"
    fi
done
rm -rf "$TESTBIN"
echo

echo "=== Summary: $PASS passed, $FAIL failed ==="
if [ $FAIL -gt 0 ]; then
    echo "Failed:$FAILED"
    exit 1
fi
