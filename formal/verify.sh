#!/bin/bash
# formal/verify.sh — run Dafny on all formal models.
# Usage: ./formal/verify.sh
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v dafny >/dev/null 2>&1; then
    echo "dafny not found — install via: brew install dafny"
    exit 1
fi

# key_encoding is a dependency of the others, so verify it together with each.
dafny verify key_encoding.dfy globals_order.dfy
dafny verify key_encoding.dfy globals_order.dfy order_pairs.dfy
dafny verify key_encoding.dfy numeric_encoding.dfy
dafny verify key_encoding.dfy txn_overlay.dfy
dafny verify key_encoding.dfy txn_overlay.dfy data_tristate.dfy
dafny verify numeric_prefix.dfy functions_more.dfy
# Standalone models, alphabetically sorted (progress indicator).
dafny verify bm25.dfy
dafny verify bytecode_bisim.dfy
dafny verify bytecode_stack.dfy
dafny verify collation.dfy
dafny verify control_flow_bisim.dfy
dafny verify data_structures.dfy
dafny verify entry_term_expansion.dfy
dafny verify for_loop_bisim.dfy
dafny verify hybrid_merge.dfy
dafny verify lock_semantics.dfy
dafny verify pattern.dfy
dafny verify scope_stack.dfy
dafny verify special_vars.dfy
dafny verify string_functions.dfy
dafny verify subscript_bisim.dfy
dafny verify value_format.dfy
dafny verify vm_opcodes.dfy
echo "formal models verified."
