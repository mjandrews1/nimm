#!/bin/bash
# formal/verify.sh — run Dafny on all formal models.
# Usage: ./formal/verify.sh
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v dafny >/dev/null 2>&1; then
    echo "dafny not found — install via: brew install dafny"
    exit 1
fi

# key_encoding is a dependency of globals_order, so verify them together.
dafny verify key_encoding.dfy globals_order.dfy
dafny verify pattern.dfy
echo "formal models verified."
