#!/bin/bash
# formal/check_contracts.sh — enforce the Dafny-model ↔ Nim-mirror mapping.
#
# 1. Every formal/*.dfy model must be listed in formal/CONTRACTS.md.
# 2. Every mirror path referenced in CONTRACTS.md must exist.
#
# Exit 0 iff both hold. Run by `make formal` (and thus `make verify`).
set -euo pipefail
cd "$(dirname "$0")/.."

CONTRACTS="formal/CONTRACTS.md"
fail=0

echo "contracts: checking model coverage ..."
for model in formal/*.dfy; do
    base="$(basename "$model")"
    if ! grep -qF "$base" "$CONTRACTS"; then
        echo "  MISSING from $CONTRACTS: $base"
        fail=1
    fi
done

echo "contracts: checking mirror paths ..."
# Extract referenced paths (tests/... and top-level source files).
for path in $(grep -oE 'tests/[A-Za-z0-9_./-]+\.(nim|sh|py)|(^|[[:space:]])(value|globals)\.nim' "$CONTRACTS" | sed 's/^[[:space:]]*//'); do
    if [ ! -f "$path" ]; then
        echo "  MISSING mirror: $path"
        fail=1
    fi
done

if [ "$fail" -ne 0 ]; then
    echo "contracts: FAILED"
    exit 1
fi
echo "contracts: OK ($(ls formal/*.dfy | wc -l | tr -d ' ') models mapped)"
