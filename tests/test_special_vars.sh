#!/bin/bash
# test_special_vars.sh — special-variable property test
# (mirrors formal/special_vars.dfy: $STACK/$ZLEVEL depth discipline).
#
# Usage: bash tests/test_special_vars.sh [nimm-binary]
set -euo pipefail

NIMM="${1:-./bin/nimm}"

check() {
    local desc="$1" expected="$2" code="$3"
    local out
    out=$("$NIMM" -x "$code" 2>&1)
    if [ "$out" = "$expected" ]; then
        echo "  ✓ $desc"
    else
        echo "  ✗ $desc — expected '$expected', got '$out'"
        exit 1
    fi
}

echo "Special-variable test (mirrors formal/special_vars.dfy)..."

check "\$STACK base depth" '0' 'W $STACK'
check "\$ZLEVEL base depth" '0' 'W $ZLEVEL'

echo "  all checks passed"
echo "Special-variable tests passed!"
